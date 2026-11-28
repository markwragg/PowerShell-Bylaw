# Semantic comparison of definitions (ADR-0041). ConvertTo-Bylaw proves each converted file with it,
# and the round-trip tests use it (ADR-0039, ADR-0042).
#
# Rules are compared by meaning: each if condition is rewritten into a normal form, and if the two
# forms differ, both are evaluated for every assignment of their leaf conditions (atoms) as
# independent propositions. Equivalent is only reported when it is true. Everything else is compared
# exactly, after normalising key order and the case Azure ignores.

# Operators Azure compares ignoring case (Learn: policy definition structure, conditions).
$script:BylawCaseInsensitiveOperators = @('equals', 'like', 'contains', 'in', 'containskey', 'matchinsensitively')
# Negated operators, as not(positive).
$script:BylawPositiveOperator = @{
    notequals             = 'equals'
    notin                 = 'in'
    notlike               = 'like'
    notmatch              = 'match'
    notmatchinsensitively = 'matchinsensitively'
    notcontains           = 'contains'
    notcontainskey        = 'containskey'
}
# Metadata Azure or EPAC adds to a deployed definition, which isn't part of its meaning.
$script:BylawIgnoredMetadataKeys = @('deployedby', 'createdby', 'createdon', 'updatedby', 'updatedon')
# String values whose case Azure ignores, by key.
$script:BylawCaseInsensitiveKeys = @('mode', 'policytype', 'type', 'effect', 'name', 'evaluationdelay', 'existencescope', 'deploymentscope', 'conflicteffect', 'operation', 'actionnames', 'cascadebehaviors', 'defaultstate')
# The truth table's limit: 16 atoms is 65,536 assignments.
$script:BylawTruthTableAtomLimit = 16

function Compare-BylawDefinition {
    # Compares two policy or policy set definitions, as JSON text or parsed dictionaries, in the
    # EPAC, plain or properties-only shape. Returns Result (Equivalent, Different,
    # DifferentAsWritten or Unproven) and Differences, each with a Path and a Message.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Reference,
        [Parameter(Mandatory)] [AllowNull()] [object] $Difference
    )

    $left = ConvertTo-BylawComparableDefinition -Definition $Reference
    $right = ConvertTo-BylawComparableDefinition -Definition $Difference
    $differences = [System.Collections.Generic.List[object]]::new()
    $context = [pscustomobject]@{ CountWheres = [System.Collections.Generic.List[object]]::new() }
    $ruleResult = 'Equivalent'

    if ($null -ne $left.Name -and $null -ne $right.Name -and -not [string]::Equals($left.Name, $right.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
        $differences.Add([pscustomobject]@{ Path = 'name'; Message = "The names differ: '$($left.Name)' and '$($right.Name)'." })
    }

    # Everything but the rule and an initiative's members, exactly after normalising.
    $special = @('policyrule', 'policydefinitions', 'policydefinitiongroups')
    $leftRest = ConvertTo-BylawComparableValue -Value $left.Properties -Exclude $special
    $rightRest = ConvertTo-BylawComparableValue -Value $right.Properties -Exclude $special
    foreach ($found in Find-BylawValueDifference -Left $leftRest -Right $rightRest -Path 'properties') {
        $differences.Add($found)
    }

    # The rule: then exactly (with an existence condition by meaning), if by meaning.
    $leftRule = Get-BylawDictionaryValue -Dictionary $left.Properties -Key 'policyRule'
    $rightRule = Get-BylawDictionaryValue -Dictionary $right.Properties -Key 'policyRule'
    if (($null -eq $leftRule) -ne ($null -eq $rightRule)) {
        $differences.Add([pscustomobject]@{ Path = 'properties.policyRule'; Message = 'Only one of them has a policy rule.' })
    }
    elseif ($null -ne $leftRule) {
        $leftThen = Get-BylawDictionaryValue -Dictionary $leftRule -Key 'then'
        $rightThen = Get-BylawDictionaryValue -Dictionary $rightRule -Key 'then'
        $leftExistence = Get-BylawExistenceCondition -Then $leftThen
        $rightExistence = Get-BylawExistenceCondition -Then $rightThen
        # The existence condition is compared by meaning below, not as part of the details.
        $leftThenValue = ConvertTo-BylawComparableValue -Value $leftThen
        $rightThenValue = ConvertTo-BylawComparableValue -Value $rightThen
        foreach ($thenValue in $leftThenValue, $rightThenValue) {
            if ($thenValue -is [System.Collections.IDictionary] -and $thenValue.Contains('details') -and $thenValue['details'] -is [System.Collections.IDictionary]) {
                $thenValue['details'].Remove('existencecondition')
            }
        }
        foreach ($found in Find-BylawValueDifference -Left $leftThenValue -Right $rightThenValue -Path 'properties.policyRule.then') {
            $differences.Add($found)
        }
        $conditions = @(
            @{ Path = 'properties.policyRule.if'; Left = (Get-BylawDictionaryValue -Dictionary $leftRule -Key 'if'); Right = (Get-BylawDictionaryValue -Dictionary $rightRule -Key 'if') }
        )
        if ($null -ne $leftExistence -or $null -ne $rightExistence) {
            $conditions += @{ Path = 'properties.policyRule.then.details.existenceCondition'; Left = $leftExistence; Right = $rightExistence }
        }
        foreach ($condition in $conditions) {
            if (($null -eq $condition.Left) -ne ($null -eq $condition.Right)) {
                $differences.Add([pscustomobject]@{ Path = $condition.Path; Message = 'Only one of them has this condition.' })
                continue
            }
            if ($null -eq $condition.Left) {
                continue
            }
            $leftForm = ConvertTo-BylawNormalForm -Condition $condition.Left -Context $context
            $rightForm = ConvertTo-BylawNormalForm -Condition $condition.Right -Context $context
            $proof = Test-BylawNormalFormEquivalence -Left $leftForm -Right $rightForm
            if ($proof.Result -eq 'Unproven') {
                $ruleResult = 'Unproven'
                $differences.Add([pscustomobject]@{ Path = $condition.Path; Message = $proof.Message })
            }
            elseif ($proof.Result -ne 'Equivalent') {
                if ($ruleResult -ne 'Unproven') {
                    $ruleResult = 'DifferentAsWritten'
                }
                $differences.Add([pscustomobject]@{ Path = $condition.Path; Message = $proof.Message })
            }
        }
    }

    # An initiative's members and groups, as sets.
    foreach ($set in @(@{ Key = 'policyDefinitions'; Id = 'policyDefinitionReferenceId' }, @{ Key = 'policyDefinitionGroups'; Id = 'name' })) {
        $leftItems = Get-BylawDictionaryValue -Dictionary $left.Properties -Key $set.Key
        $rightItems = Get-BylawDictionaryValue -Dictionary $right.Properties -Key $set.Key
        foreach ($found in Compare-BylawKeyedSet -Left $leftItems -Right $rightItems -IdKey $set.Id -Path "properties.$($set.Key)") {
            $differences.Add($found)
        }
    }

    $ruleDifferences = @($differences | Where-Object { $_.Path -like 'properties.policyRule.if*' -or $_.Path -like '*existenceCondition' })
    $result = if ($differences.Count -eq 0) {
        'Equivalent'
    }
    elseif ($differences.Count -gt $ruleDifferences.Count) {
        'Different'
    }
    else {
        $ruleResult
    }
    [pscustomobject]@{ Result = $result; Differences = $differences.ToArray() }
}

function ConvertTo-BylawComparableDefinition {
    # Name and properties of a definition, as JSON text, { name, properties }, EPAC's
    # { $schema, name, properties }, or properties alone.
    param([AllowNull()] [object] $Definition)

    $data = if ($Definition -is [string]) { ConvertFrom-BylawJson -Json $Definition } else { $Definition }
    if ($data -isnot [System.Collections.IDictionary]) {
        throw [System.ArgumentException]::new('A definition must be a JSON object.')
    }
    $properties = Get-BylawDictionaryValue -Dictionary $data -Key 'properties'
    if ($properties -is [System.Collections.IDictionary]) {
        return [pscustomobject]@{ Name = (Get-BylawDictionaryValue -Dictionary $data -Key 'name'); Properties = $properties }
    }
    [pscustomobject]@{ Name = $null; Properties = $data }
}

function Get-BylawDictionaryValue {
    # The value for a key matched ignoring case, or $null.
    param([AllowNull()] [object] $Dictionary, [Parameter(Mandatory)] [string] $Key)

    if ($Dictionary -isnot [System.Collections.IDictionary]) {
        return $null
    }
    foreach ($candidate in $Dictionary.Keys) {
        if ([string]::Equals([string] $candidate, $Key, [System.StringComparison]::OrdinalIgnoreCase)) {
            return , $Dictionary[$candidate]
        }
    }
    $null
}

function Get-BylawExistenceCondition {
    param([AllowNull()] [object] $Then)

    $details = Get-BylawDictionaryValue -Dictionary $Then -Key 'details'
    Get-BylawDictionaryValue -Dictionary $details -Key 'existenceCondition'
}

function ConvertTo-BylawComparableValue {
    # A value with the differences Azure ignores taken out: keys lower-cased and sorted, the case of
    # names and kinds such as mode and effect, role definition IDs as GUIDs, and metadata Azure or
    # EPAC adds. Exclude drops keys, at the top level only.
    param([AllowNull()] [object] $Value, [string[]] $Exclude = @(), [string] $Key = '')

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        $keys = @($Value.Keys | ForEach-Object { [string] $_ } | Sort-Object { $_.ToLowerInvariant() } -Culture ([cultureinfo]::InvariantCulture))
        foreach ($name in $keys) {
            $lower = $name.ToLowerInvariant()
            if ($lower -in $Exclude) {
                continue
            }
            if ($Key -eq 'metadata' -and $lower -in $script:BylawIgnoredMetadataKeys) {
                continue
            }
            $result[$lower] = ConvertTo-BylawComparableValue -Value $Value[$name] -Key $lower
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) {
            , (ConvertTo-BylawComparableValue -Value $item -Key $Key)
        }
        if ($Key -eq 'roledefinitionids') {
            $items = @($items | ForEach-Object { ([string] $_).Substring(([string] $_).LastIndexOf('/') + 1).ToLowerInvariant() } | Sort-Object)
        }
        return , [object[]] @($items)
    }
    if ($Value -is [string] -and $Key -in $script:BylawCaseInsensitiveKeys -and -not $Value.StartsWith('[')) {
        return $Value.ToLowerInvariant()
    }
    , $Value
}

function Find-BylawValueDifference {
    # The first difference in each branch of two comparable values, with its path.
    param([AllowNull()] [object] $Left, [AllowNull()] [object] $Right, [Parameter(Mandatory)] [string] $Path)

    if ($Left -is [System.Collections.IDictionary] -and $Right -is [System.Collections.IDictionary]) {
        foreach ($name in @(@($Left.Keys) + @($Right.Keys) | Sort-Object -Unique)) {
            if (-not $Left.Contains($name)) {
                [pscustomobject]@{ Path = "$Path.$name"; Message = "Only the second has $name." }
            }
            elseif (-not $Right.Contains($name)) {
                [pscustomobject]@{ Path = "$Path.$name"; Message = "Only the first has $name." }
            }
            else {
                Find-BylawValueDifference -Left $Left[$name] -Right $Right[$name] -Path "$Path.$name"
            }
        }
        return
    }
    $leftJson = ConvertTo-BylawJson -InputObject $Left
    $rightJson = ConvertTo-BylawJson -InputObject $Right
    if ($leftJson -cne $rightJson) {
        $show = { param($Text) $one = ($Text -replace '\s+', ' ').Trim(); if ($one.Length -gt 120) { $one.Substring(0, 117) + '...' } else { $one } }
        [pscustomobject]@{ Path = $Path; Message = "The values differ: $(& $show $leftJson) and $(& $show $rightJson)." }
    }
}

function Compare-BylawKeyedSet {
    # Two lists of objects compared as sets, by an ID matched ignoring case: an initiative's members
    # by reference ID, its groups by name.
    param([AllowNull()] [object] $Left, [AllowNull()] [object] $Right, [Parameter(Mandatory)] [string] $IdKey, [Parameter(Mandatory)] [string] $Path)

    $leftMap = Get-BylawKeyedMap -Items $Left -IdKey $IdKey
    $rightMap = Get-BylawKeyedMap -Items $Right -IdKey $IdKey
    foreach ($id in @(@($leftMap.Keys) + @($rightMap.Keys) | Sort-Object -Unique)) {
        if (-not $leftMap.Contains($id)) {
            [pscustomobject]@{ Path = "$Path[$id]"; Message = "Only the second has '$id'." }
            continue
        }
        if (-not $rightMap.Contains($id)) {
            [pscustomobject]@{ Path = "$Path[$id]"; Message = "Only the first has '$id'." }
            continue
        }
        $leftItem = ConvertTo-BylawComparableMember -Member $leftMap[$id]
        $rightItem = ConvertTo-BylawComparableMember -Member $rightMap[$id]
        Find-BylawValueDifference -Left $leftItem -Right $rightItem -Path "$Path[$id]"
    }
}

function Get-BylawKeyedMap {
    # Items by their ID, lower-cased, in order.
    param([AllowNull()] [object] $Items, [Parameter(Mandatory)] [string] $IdKey)

    $map = [ordered]@{}
    foreach ($item in @($Items | Where-Object { $null -ne $_ })) {
        $id = [string] (Get-BylawDictionaryValue -Dictionary $item -Key $IdKey)
        $map[$id.ToLowerInvariant()] = $item
    }
    $map
}

function ConvertTo-BylawComparableMember {
    # A member or group, with IDs compared ignoring case and group names as a set.
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Member)

    $value = ConvertTo-BylawComparableValue -Value $Member
    foreach ($key in 'policydefinitionid', 'policydefinitionreferenceid') {
        if ($value.Contains($key) -and $value[$key] -is [string]) {
            $value[$key] = $value[$key].ToLowerInvariant()
        }
    }
    if ($value.Contains('groupnames')) {
        $value['groupnames'] = [object[]] @($value['groupnames'] | ForEach-Object { ([string] $_).ToLowerInvariant() } | Sort-Object)
    }
    $value
}

#region Normal form

function New-BylawFormNode {
    # A normal-form node: and, or, atom, true or false. Text is canonical: equal for equal nodes.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory node only.')]
    param([Parameter(Mandatory)] [string] $Kind, [object[]] $Children = @(), [string] $Key = '', [bool] $Negated = $false)

    $text = switch ($Kind) {
        'atom' { if ($Negated) { "!$Key" } else { $Key } }
        'true' { 'true' }
        'false' { 'false' }
        default { "$Kind($(@($Children | ForEach-Object Text) -join ','))" }
    }
    [pscustomobject]@{ Kind = $Kind; Children = $Children; Key = $Key; Negated = $Negated; Text = $text }
}

function Join-BylawFormNode {
    # and or or of children: flattened, constants folded, repeats removed, sorted.
    param([Parameter(Mandatory)] [string] $Kind, [object[]] $Children)

    $absorbing = if ($Kind -eq 'and') { 'false' } else { 'true' }
    $neutral = if ($Kind -eq 'and') { 'true' } else { 'false' }
    $flat = [System.Collections.Generic.List[object]]::new()
    foreach ($child in $Children) {
        if ($child.Kind -eq $absorbing) {
            return New-BylawFormNode -Kind $absorbing
        }
        if ($child.Kind -eq $neutral) {
            continue
        }
        if ($child.Kind -eq $Kind) {
            $flat.AddRange([object[]] @($child.Children))
        }
        else {
            $flat.Add($child)
        }
    }
    $unique = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($child in $flat) {
        $unique[$child.Text] = $child
    }
    if ($unique.Count -eq 0) {
        return New-BylawFormNode -Kind $neutral
    }
    if ($unique.Count -eq 1) {
        return @($unique.Values)[0]
    }
    New-BylawFormNode -Kind $Kind -Children ([object[]] @($unique.Values))
}

function ConvertTo-BylawNormalForm {
    # The normal form of a policy condition (a parsed JSON object): not pushed to the leaves,
    # negated operators as not(positive), groups flattened and sorted, values in the form Azure
    # compares them, and a count's comparison as a range over the non-negative integers.
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Condition,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [bool] $Negate = $false
    )

    if ($Condition -isnot [System.Collections.IDictionary]) {
        return New-BylawFormNode -Kind 'atom' -Key ('raw|' + (ConvertTo-BylawJson -InputObject $Condition).Trim()) -Negated $Negate
    }
    foreach ($group in 'allOf', 'anyOf') {
        $children = Get-BylawDictionaryValue -Dictionary $Condition -Key $group
        if ($null -ne $children) {
            $kind = if (($group -eq 'allOf') -ne $Negate) { 'and' } else { 'or' }
            $forms = foreach ($child in @($children)) {
                ConvertTo-BylawNormalForm -Condition $child -Context $Context -Negate $Negate
            }
            return Join-BylawFormNode -Kind $kind -Children @($forms)
        }
    }
    $inner = Get-BylawDictionaryValue -Dictionary $Condition -Key 'not'
    if ($null -ne $inner) {
        return ConvertTo-BylawNormalForm -Condition $inner -Context $Context -Negate (-not $Negate)
    }

    $count = Get-BylawDictionaryValue -Dictionary $Condition -Key 'count'
    $subjectKey = if ($null -ne $count) { 'count' } elseif ($null -ne (Get-BylawDictionaryValue -Dictionary $Condition -Key 'field')) { 'field' } else { 'value' }
    $operatorKeys = @($Condition.Keys | Where-Object { -not [string]::Equals([string] $_, $subjectKey, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($operatorKeys.Count -ne 1) {
        return New-BylawFormNode -Kind 'atom' -Key ('raw|' + (ConvertTo-BylawJson -InputObject (ConvertTo-BylawComparableValue -Value $Condition)).Trim()) -Negated $Negate
    }
    $operator = ([string] $operatorKeys[0]).ToLowerInvariant()
    $value = $Condition[$operatorKeys[0]]
    $negated = $Negate
    if ($script:BylawPositiveOperator.ContainsKey($operator)) {
        $operator = $script:BylawPositiveOperator[$operator]
        $negated = -not $negated
    }

    if ($null -ne $count) {
        return ConvertTo-BylawCountForm -Count $count -Operator $operator -Value $value -Negated $negated -Context $Context
    }

    $subject = if ($subjectKey -eq 'field') {
        'field:' + ([string] (Get-BylawDictionaryValue -Dictionary $Condition -Key 'field')).ToLowerInvariant()
    }
    else {
        'value:' + (ConvertTo-BylawCanonicalOperand -Value (Get-BylawDictionaryValue -Dictionary $Condition -Key 'value') -Operator 'value')
    }
    if ($operator -eq 'exists') {
        $exists = if ($value -is [bool]) { $value } elseif ([string] $value -in 'true', 'false') { [bool]::Parse([string] $value) } else { $null }
        if ($null -eq $exists) {
            return New-BylawFormNode -Kind 'atom' -Key "$subject|exists|$(ConvertTo-BylawCanonicalOperand -Value $value -Operator 'exists')" -Negated $negated
        }
        return New-BylawFormNode -Kind 'atom' -Key "$subject|exists" -Negated ($negated -xor -not $exists)
    }
    # in with one value is equals.
    if ($operator -eq 'in' -and $value -is [System.Collections.IEnumerable] -and $value -isnot [string] -and $value -isnot [System.Collections.IDictionary] -and @($value).Count -eq 1) {
        $operator = 'equals'
        $value = @($value)[0]
    }
    New-BylawFormNode -Kind 'atom' -Key "$subject|$operator|$(ConvertTo-BylawCanonicalOperand -Value $value -Operator $operator)" -Negated $negated
}

function ConvertTo-BylawCanonicalOperand {
    # A value as Azure compares it, as JSON text: strings ignoring case for the operators Azure
    # compares that way, in as a set, and ARM expressions exactly.
    param([AllowNull()] [object] $Value, [Parameter(Mandatory)] [string] $Operator)

    $insensitive = $Operator -in $script:BylawCaseInsensitiveOperators
    $normalise = {
        param($Item)
        if ($Item -is [string] -and $insensitive -and -not ($Item.StartsWith('[') -and -not $Item.StartsWith('[['))) {
            return $Item.ToLowerInvariant()
        }
        , (ConvertTo-BylawComparableValue -Value $Item)
    }
    $canonical = if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) {
        $items = @(foreach ($item in $Value) { , (& $normalise $item) })
        if ($Operator -eq 'in') {
            $items = @($items | Sort-Object { ConvertTo-BylawJson -InputObject $_ } -Unique)
        }
        , [object[]] $items
    }
    else {
        & $normalise $Value
    }
    ((ConvertTo-BylawJson -InputObject $canonical) -replace '\s+', ' ').Trim()
}

function ConvertTo-BylawCountForm {
    # A count condition: an atom for what is counted and how it is compared. A comparison with a
    # whole number is a range of the non-negative integers, so greater 0, greaterOrEquals 1 and
    # notEquals 0 are the same atom; a range that holds for every count is true.
    param(
        [Parameter(Mandatory)] [object] $Count,
        [Parameter(Mandatory)] [string] $Operator,
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [bool] $Negated,
        [Parameter(Mandatory)] [pscustomobject] $Context
    )

    $field = Get-BylawDictionaryValue -Dictionary $Count -Key 'field'
    $source = Get-BylawDictionaryValue -Dictionary $Count -Key 'value'
    $name = Get-BylawDictionaryValue -Dictionary $Count -Key 'name'
    $where = Get-BylawDictionaryValue -Dictionary $Count -Key 'where'
    $base = if ($null -ne $field) { 'field:' + ([string] $field).ToLowerInvariant() } else { 'value:' + (ConvertTo-BylawCanonicalOperand -Value $source -Operator 'value') }
    if ($null -ne $name) {
        $base += "|name:$(([string] $name).ToLowerInvariant())"
    }
    $whereText = if ($null -eq $where) { 'all' } else { Resolve-BylawCountWhereText -Base $base -Where $where -Context $Context }
    $key = "count|$base|where:$whereText"

    $number = $null
    if ($Value -is [int] -or $Value -is [long] -or ($Value -is [double] -and $Value -eq [math]::Floor($Value))) {
        $number = [long] $Value
    }
    if ($null -eq $number -or $Operator -notin 'equals', 'greater', 'greaterorequals', 'less', 'lessorequals') {
        return New-BylawFormNode -Kind 'atom' -Key "$key|$Operator|$(ConvertTo-BylawCanonicalOperand -Value $Value -Operator $Operator)" -Negated $Negated
    }
    # The range [low, high] of counts that match; high is -1 for no upper bound.
    $low, $high = switch ($Operator) {
        'equals' { $number, $number }
        'greater' { ($number + 1), -1 }
        'greaterorequals' { $number, -1 }
        'less' { 0, ($number - 1) }
        'lessorequals' { 0, $number }
    }
    if ($low -lt 0) {
        $low = 0
    }
    if ($Negated) {
        # The complement is one range when the range starts at 0 or has no upper bound.
        if ($low -eq 0 -and $high -ge 0) {
            $low, $high = ($high + 1), -1
            $Negated = $false
        }
        elseif ($high -eq -1) {
            $low, $high = 0, ($low - 1)
            $Negated = $false
        }
    }
    if ($high -ne -1 -and $high -lt $low) {
        return New-BylawFormNode -Kind $(if ($Negated) { 'true' } else { 'false' })
    }
    if ($low -eq 0 -and $high -eq -1) {
        return New-BylawFormNode -Kind $(if ($Negated) { 'false' } else { 'true' })
    }
    $range = if ($high -eq -1) { "$low.." } else { "$low..$high" }
    New-BylawFormNode -Kind 'atom' -Key "$key|range:$range" -Negated $Negated
}

function Resolve-BylawCountWhereText {
    # The canonical text for a count's where. Two wheres of the same count that are equivalent get
    # the same text, so the counts are the same atom.
    param([Parameter(Mandatory)] [string] $Base, [Parameter(Mandatory)] [object] $Where, [Parameter(Mandatory)] [pscustomobject] $Context)

    $form = ConvertTo-BylawNormalForm -Condition $Where -Context $Context
    foreach ($seen in $Context.CountWheres) {
        if ($seen.Base -ne $Base) {
            continue
        }
        if ($seen.Form.Text -ceq $form.Text) {
            return $seen.Form.Text
        }
        if ((Test-BylawNormalFormEquivalence -Left $seen.Form -Right $form).Result -eq 'Equivalent') {
            return $seen.Form.Text
        }
    }
    $Context.CountWheres.Add([pscustomobject]@{ Base = $Base; Form = $form })
    $form.Text
}

#endregion

#region Truth table

function Get-BylawFormAtom {
    # The distinct atom keys of a normal form.
    param([Parameter(Mandatory)] [object] $Form, [System.Collections.Generic.HashSet[string]] $Into)

    if ($Form.Kind -eq 'atom') {
        $null = $Into.Add($Form.Key)
        return
    }
    foreach ($child in $Form.Children) {
        Get-BylawFormAtom -Form $child -Into $Into
    }
}

function Test-BylawNormalFormEquivalence {
    # Equivalent when the two forms are identical, or agree for every assignment of their atoms as
    # independent propositions; otherwise DifferentAsWritten with an example, or Unproven above the
    # atom limit. Returns Result and Message.
    param([Parameter(Mandatory)] [object] $Left, [Parameter(Mandatory)] [object] $Right)

    if ($Left.Text -ceq $Right.Text) {
        return [pscustomobject]@{ Result = 'Equivalent'; Message = '' }
    }
    $atoms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    Get-BylawFormAtom -Form $Left -Into $atoms
    Get-BylawFormAtom -Form $Right -Into $atoms
    $names = [string[]] @($atoms | Sort-Object)
    if ($names.Count -gt $script:BylawTruthTableAtomLimit) {
        return [pscustomobject]@{ Result = 'Unproven'; Message = "The conditions are written differently, and have $($names.Count) distinct leaf conditions, more than the $script:BylawTruthTableAtomLimit the comparison can check." }
    }

    $assignments = [long] 1 -shl $names.Count
    $words = [int] [math]::Max(1, $assignments / 64)
    $leftBits = Get-BylawTruthVector -Form $Left -Atoms $names -Words $words
    $rightBits = Get-BylawTruthVector -Form $Right -Atoms $names -Words $words
    $valid = if ($assignments -ge 64) { [uint64]::MaxValue } else { [uint64] (([uint64] 1 -shl [int] $assignments) - [uint64] 1) }
    for ($word = 0; $word -lt $words; $word++) {
        $different = ($leftBits[$word] -bxor $rightBits[$word]) -band $valid
        if ($different -ne 0) {
            $bit = 0
            while ((($different -shr $bit) -band 1) -eq 0) {
                $bit++
            }
            $assignment = [long] $word * 64 + $bit
            $leftMatches = (($leftBits[$word] -shr $bit) -band 1) -eq 1
            $parts = for ($index = 0; $index -lt $names.Count; $index++) {
                $state = if ((($assignment -shr $index) -band 1) -eq 1) { 'true' } else { 'false' }
                "$(Format-BylawAtom -Key $names[$index]) $state"
            }
            $which = if ($leftMatches) { 'the first matches and the second doesn''t' } else { 'the second matches and the first doesn''t' }
            return [pscustomobject]@{
                Result  = 'DifferentAsWritten'
                Message = "The conditions differ as written: with $($parts -join ', '), $which. Leaf conditions are treated as independent, so they may still be equivalent."
            }
        }
    }
    [pscustomobject]@{ Result = 'Equivalent'; Message = '' }
}

function Format-BylawAtom {
    # An atom's key, readable: 'field:x|equals|"y"' as 'x equals "y"'.
    param([Parameter(Mandatory)] [string] $Key)

    $text = $Key -replace '^(field|value):', '' -replace '\|', ' '
    if ($text.Length -gt 100) {
        $text = $text.Substring(0, 97) + '...'
    }
    "[$text]"
}

function Get-BylawTruthVector {
    # The truth values of a form for every assignment, 64 to a word: bit j of the result is the
    # form's value when atom i is true exactly where bit i of j is set.
    param([Parameter(Mandatory)] [object] $Form, [Parameter(Mandatory)] [string[]] $Atoms, [Parameter(Mandatory)] [int] $Words)

    $all = [uint64]::MaxValue
    switch ($Form.Kind) {
        'true' {
            return , ([uint64[]] (@($all) * $Words))
        }
        'false' {
            return , ([uint64[]] (@([uint64] 0) * $Words))
        }
        'atom' {
            $index = [array]::IndexOf($Atoms, $Form.Key)
            $vector = [uint64[]]::new($Words)
            $patterns = @(
                [Convert]::ToUInt64('AAAAAAAAAAAAAAAA', 16), [Convert]::ToUInt64('CCCCCCCCCCCCCCCC', 16),
                [Convert]::ToUInt64('F0F0F0F0F0F0F0F0', 16), [Convert]::ToUInt64('FF00FF00FF00FF00', 16),
                [Convert]::ToUInt64('FFFF0000FFFF0000', 16), [Convert]::ToUInt64('FFFFFFFF00000000', 16)
            )
            for ($word = 0; $word -lt $Words; $word++) {
                $vector[$word] = if ($index -lt 6) { $patterns[$index] } elseif ((($word -shr ($index - 6)) -band 1) -eq 1) { $all } else { [uint64] 0 }
                if ($Form.Negated) {
                    $vector[$word] = $vector[$word] -bxor $all
                }
            }
            return , $vector
        }
    }
    $isAnd = $Form.Kind -eq 'and'
    $result = [uint64[]]::new($Words)
    for ($word = 0; $word -lt $Words; $word++) {
        $result[$word] = if ($isAnd) { $all } else { [uint64] 0 }
    }
    foreach ($child in $Form.Children) {
        $childVector = Get-BylawTruthVector -Form $child -Atoms $Atoms -Words $Words
        for ($word = 0; $word -lt $Words; $word++) {
            $result[$word] = if ($isAnd) { $result[$word] -band $childVector[$word] } else { $result[$word] -bor $childVector[$word] }
        }
    }
    , $result
}

#endregion
