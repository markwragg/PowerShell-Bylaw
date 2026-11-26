# Validation pass (ADR-0010, ADR-0015, ADR-0016, ADR-0017, plus Azure limits).
#
# Invoke-BylawValidation checks the DSL layer after alias resolution. Test-BylawRuleLimit checks
# the compiled rule against the limits Azure enforces when a definition is created.

$script:BylawLaterEffects = [ordered]@{
    Modify            = 'Modify arrives in Milestone 2.'
    Append            = 'Append is not planned; use Modify (Milestone 2), which Azure recommends over Append.'
    AuditIfNotExists  = 'AuditIfNotExists is planned for a later milestone.'
    DeployIfNotExists = 'DeployIfNotExists is planned for a later milestone.'
    DenyAction        = 'DenyAction is not supported in language version 1.0.'
    Manual            = 'Manual is not supported in language version 1.0.'
}

function Invoke-BylawValidation {
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Code, [string] $Message, [BylawSourceLocation] $Location, [BylawSeverity] $Severity = [BylawSeverity]::Error)
        $diagnostics.Add([BylawDiagnostic]::new($Severity, $Code, $Message, $Location))
    }

    # Name (ADR-0010).
    $name = $Policy.Name
    if ($name.Length -lt 3 -or $name.Length -gt 64 -or $name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        & $add 'BYL3001' "Policy name '$name' must be 3 to 64 characters of lowercase letters, digits and single hyphens, e.g. 'storage-deny-public-network-access' (ADR-0010)." $Policy.Location
    }

    Test-BylawPolicyProperty -Policy $Policy -Add $add
    Test-BylawPolicyParameter -Policy $Policy -Add $add
    Test-BylawEffect -Policy $Policy -Add $add

    $scope = $Policy.Resource
    $assertions = if ($null -ne $scope) { @(Get-BylawAssertion -Scope $scope) } else { @() }
    $used = Get-BylawUsedParameterName -Policy $Policy -Assertions $assertions
    foreach ($parameter in $Policy.Parameters) {
        if (-not $used.Contains($parameter.Name)) {
            & $add 'BYL3029' "Parameter '$($parameter.Name)' is declared but never used." $parameter.Location ([BylawSeverity]::Warning)
        }
    }

    if ($null -ne $scope) {
        foreach ($assertion in $assertions) {
            Test-BylawAssertionValue -Assertion $assertion -Policy $Policy -Add $add
            Test-BylawTagParameter -Assertion $assertion -Policy $Policy -Add $add
        }

        if ($scope.Requirements.Count -eq 0) {
            $message = if ($scope.IsAnyType() -and $scope.When.Count -eq 0) {
                $null
            }
            else {
                "Policy '$name' has no Require block, so every resource that matches the type and When conditions is non-compliant."
            }
            if ($message) {
                & $add 'BYL3041' $message $scope.Location ([BylawSeverity]::Warning)
            }
        }
        if ($scope.IsAnyType() -and $scope.When.Count -eq 0 -and $scope.Requirements.Count -eq 0) {
            & $add 'BYL3042' "Policy '$name' has no conditions at all: Resource * with no When or Require would match every resource." $scope.Location
        }

        $mode = if ($Policy.Properties -and $Policy.Properties.Mode) { $Policy.Properties.Mode } else { 'All' }
        if ($mode -eq 'All') {
            $tagOrLocation = $assertions | Where-Object {
                $null -ne $_.Field -and (
                    $_.Field.Kind -eq [BylawFieldKind]::Tag -or
                    ($_.Field.Resolved -and ($_.Field.Resolved -eq 'location' -or $_.Field.Resolved -like 'tags*'))
                )
            } | Select-Object -First 1
            if ($tagOrLocation) {
                & $add 'BYL3040' "Mode is All but the rule checks '$($tagOrLocation.Field)'. Policies on tags or location usually want Mode = 'Indexed', so resources that don't support them aren't evaluated (ADR-0016)." $tagOrLocation.Location ([BylawSeverity]::Warning)
            }
        }
    }

    $diagnostics
}

function Test-BylawPolicyProperty {
    param([Parameter(Mandatory)] [BylawPolicy] $Policy, [Parameter(Mandatory)] [scriptblock] $Add)

    $properties = $Policy.Properties
    $location = if ($properties) { $properties.Location } else { $Policy.Location }

    if (-not $properties -or [string]::IsNullOrWhiteSpace($properties.DisplayName)) {
        & $Add 'BYL3002' "Policy '$($Policy.Name)' needs a DisplayName: Properties @{ DisplayName = '...' } (ADR-0016)." $location
    }
    elseif ($properties.DisplayName.Length -gt 128) {
        & $Add 'BYL3002' "DisplayName is $($properties.DisplayName.Length) characters; Azure allows at most 128." $location
    }
    if (-not $properties) {
        return
    }
    if ($properties.Description -and $properties.Description.Length -gt 512) {
        & $Add 'BYL3003' "Description is $($properties.Description.Length) characters; Azure allows at most 512." $location
    }
    if ($properties.Mode -and $properties.Mode -notin 'All', 'Indexed') {
        & $Add 'BYL3004' "Mode '$($properties.Mode)' is not supported in language version 1.0. Use 'All' or 'Indexed' (ADR-0016)." $location
    }
    if ($properties.Version -and $properties.Version -notmatch '^\d+\.\d+\.\d+(-preview)?$') {
        & $Add 'BYL3005' "Version '$($properties.Version)' must be major.minor.patch, optionally with -preview, e.g. '1.0.0'." $location
    }
    if ($properties.Metadata) {
        foreach ($key in $properties.Metadata.Keys) {
            if ([string] $key -in 'version', 'category', 'preview', 'deprecated') {
                & $Add 'BYL3006' "Metadata key '$key' is set from Properties; use Properties @{ $((Get-Culture).TextInfo.ToTitleCase([string] $key)) = ... } instead." $location
                continue
            }
            if ([string] $key -eq 'deployedBy') {
                & $Add 'BYL3006' "Metadata key 'deployedBy' is set by EPAC at deploy time; don't set it in the definition (ADR-0011)." $location
                continue
            }
            $serialized = try { ConvertTo-BylawJson -InputObject $properties.Metadata[$key] } catch { $null }
            if ($null -eq $serialized) {
                & $Add 'BYL3007' "Metadata key '$key' has a value with no JSON form." $location
            }
            elseif ($serialized.TrimEnd("`n").Length -gt 1024) {
                & $Add 'BYL3007' "Metadata key '$key' is longer than the 1024 characters Azure allows per metadata property." $location
            }
        }
    }
}

function Test-BylawPolicyParameter {
    param([Parameter(Mandatory)] [BylawPolicy] $Policy, [Parameter(Mandatory)] [scriptblock] $Add)

    $seen = @{}
    foreach ($parameter in $Policy.Parameters) {
        $jsonName = Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
        $key = $jsonName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            & $Add 'BYL3022' "Parameters '$($seen[$key])' and '$($parameter.Name)' both emit the JSON name '$jsonName'. Set JsonName on one of them." $parameter.Location
        }
        else {
            $seen[$key] = $parameter.Name
        }
        # For an Array parameter, allowedValues lists the values each element may take.
        $isArray = $parameter.Type -eq 'Array'
        if ($parameter.HasDefault -and -not (Test-BylawParameterValueType -Value $parameter.DefaultValue -Type $parameter.Type)) {
            & $Add 'BYL3027' "Parameter '$($parameter.Name)' is of type $($parameter.Type), but its default '$($parameter.DefaultValue)' is not." $parameter.Location
        }
        elseif ($parameter.HasDefault -and $parameter.AllowedValues -and $null -ne $parameter.DefaultValue) {
            $defaults = if ($isArray) { @($parameter.DefaultValue) } else { , $parameter.DefaultValue }
            $outside = @($defaults | Where-Object { -not (Test-BylawValueIn -Value $_ -Values $parameter.AllowedValues) })
            if ($outside.Count -gt 0) {
                & $Add 'BYL3021' "Parameter '$($parameter.Name)' has default '$($outside -join ', ')', which is not one of its allowed values ($($parameter.AllowedValues -join ', '))." $parameter.Location
            }
        }
        if ($parameter.AllowedValues -and -not $isArray) {
            $wrong = @($parameter.AllowedValues | Where-Object { -not (Test-BylawParameterValueType -Value $_ -Type $parameter.Type) })
            if ($wrong.Count -gt 0) {
                & $Add 'BYL3028' "Parameter '$($parameter.Name)' is of type $($parameter.Type), but these allowed values are not: $($wrong -join ', ')." $parameter.Location
            }
        }
    }
}

function Test-BylawEffect {
    param([Parameter(Mandatory)] [BylawPolicy] $Policy, [Parameter(Mandatory)] [scriptblock] $Add)

    $effect = $Policy.Effect
    if ($null -eq $effect) {
        return
    }
    $value = $effect.Value
    if ($value -is [BylawLiteral]) {
        Test-BylawEffectName -Name ([string] $value.Value) -Location $effect.Location -Add $Add
        return
    }
    if ($value -isnot [BylawParamRef]) {
        # An Arm expression: can't be checked at compile time.
        return
    }
    $parameter = $Policy.FindParameter($value.Name)
    if ($null -eq $parameter) {
        & $Add 'BYL3020' "Effect uses parameter '$($value.Name)', which is not declared. Add: Parameter $($value.Name) -AllowedValues Audit, Deny, Disabled -Default Deny." $value.Location
        return
    }
    if ($parameter.Type -ne 'String') {
        & $Add 'BYL3031' "Effect parameter '$($parameter.Name)' must be of type String (it is $($parameter.Type))." $parameter.Location
    }
    if (-not $parameter.AllowedValues) {
        & $Add 'BYL3032' "Effect parameter '$($parameter.Name)' needs -AllowedValues, e.g. -AllowedValues Audit, Deny, Disabled (ADR-0017)." $parameter.Location
        return
    }
    foreach ($allowed in $parameter.AllowedValues) {
        Test-BylawEffectName -Name ([string] $allowed) -Location $parameter.Location -Add $Add -Code 'BYL3033' -Context "Allowed value of effect parameter '$($parameter.Name)'"
    }
}

function Test-BylawEffectName {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name,
        [BylawSourceLocation] $Location,
        [Parameter(Mandatory)] [scriptblock] $Add,
        [string] $Code = 'BYL3030',
        [string] $Context = 'Effect'
    )

    if (Get-BylawCanonicalEffect -Effect $Name) {
        return
    }
    $later = $script:BylawLaterEffects.Keys | Where-Object { $_ -eq $Name } | Select-Object -First 1
    $reason = if ($later) { ' ' + $script:BylawLaterEffects[$later] } else { '' }
    & $Add $Code "$Context '$Name' is not supported in language version 1.0. Supported effects: $($script:BylawSupportedEffects -join ', ').$reason" $Location
}

function Test-BylawAssertionValue {
    # Per-operator value rules (ADR-0015) and parameter references.
    param(
        [Parameter(Mandatory)] [BylawAssertion] $Assertion,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $value = $Assertion.Value
    $location = $Assertion.Location
    $operatorName = '-' + $Assertion.DslOperator

    if ($value -is [BylawParamRef]) {
        $parameter = $Policy.FindParameter($value.Name)
        if ($null -eq $parameter) {
            & $Add 'BYL3020' "Parameter '$($value.Name)' is used but not declared. Add a Parameter $($value.Name) declaration." $value.Location
            return
        }
        Test-BylawParameterOperator -Parameter $parameter -DslOperator $Assertion.DslOperator -Location $value.Location -Add $Add
        return
    }
    if ($value -is [BylawResourceGroupTag] -and $Assertion.DslOperator -eq 'BeIn') {
        & $Add 'BYL3017' '-BeIn needs a list, but ResourceGroupTag is a single value. Use -Be.' $location
        return
    }
    if ($value -isnot [BylawLiteral]) {
        return
    }

    $literal = $value.Value
    $isArray = $literal -is [System.Array]
    $dslOperator = $Assertion.DslOperator

    if ($dslOperator -eq 'Be' -and $isArray) {
        & $Add 'BYL3010' '-Be compares with a single value; use -BeIn for a list of values.' $location
    }

    if ($dslOperator -in 'BeLike', 'Match', 'MatchCase', 'ContainText', 'ContainKey') {
        if ($literal -isnot [string]) {
            & $Add 'BYL3014' "$operatorName needs a string value." $location
            return
        }
        if ($dslOperator -eq 'BeLike' -and ($literal.Length - $literal.Replace('*', '').Length) -gt 1) {
            & $Add 'BYL3011' "-BeLike pattern '$literal' has more than one '*'; Azure allows at most one wildcard." $location
        }
        if ($dslOperator -eq 'ContainText' -and $literal.Contains('*')) {
            & $Add 'BYL3012' "-ContainText value '$literal' contains '*'; Azure doesn't allow wildcards in contains. Use -BeLike for a wildcard match." $location
        }
        if ($dslOperator -in 'Match', 'MatchCase' -and $literal -match '\^|\$|\\d|\[|\(|\+') {
            & $Add 'BYL3013' "$operatorName pattern '$literal' looks like a regular expression. Azure match patterns are not regex: '#' is a digit, '?' a letter, '.' any character; everything else is literal." $location ([BylawSeverity]::Warning)
        }
    }

    if ($dslOperator -in 'BeGreaterThan', 'BeGreaterOrEqual', 'BeLessThan', 'BeLessOrEqual') {
        if ($isArray -or $literal -is [bool] -or $literal -is [System.Collections.IDictionary]) {
            & $Add 'BYL3016' "$operatorName needs a number, string or date string to compare with." $location
        }
    }
}

function Test-BylawTagParameter {
    # Parameters used by Tag, by ResourceGroupTag, and as the subject of a value condition must be
    # declared. One that holds a tag name must be a String (ADR-0020, ADR-0025).
    param(
        [Parameter(Mandatory)] [BylawAssertion] $Assertion,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $tagNames = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Assertion.Field -and $Assertion.Field.Kind -eq [BylawFieldKind]::Tag) {
        $tagNames.Add($Assertion.Field.TagName)
    }
    foreach ($value in $Assertion.Subject, $Assertion.Value) {
        if ($value -is [BylawResourceGroupTag]) {
            $tagNames.Add($value.TagName)
        }
    }
    foreach ($tagName in $tagNames) {
        if ($tagName -isnot [BylawParamRef]) {
            continue
        }
        $parameter = $Policy.FindParameter($tagName.Name)
        if ($null -eq $parameter) {
            & $Add 'BYL3020' "Parameter '$($tagName.Name)' is used as a tag name but not declared. Add: Parameter $($tagName.Name) -Type String." $tagName.Location
        }
        elseif ($parameter.Type -ne 'String') {
            & $Add 'BYL3034' "Parameter '$($parameter.Name)' holds a tag name, so it must be of type String (it is $($parameter.Type))." $tagName.Location
        }
    }

    $subject = $Assertion.Subject
    if ($subject -is [BylawParamRef] -and $null -eq $Policy.FindParameter($subject.Name)) {
        & $Add 'BYL3020' "Parameter '$($subject.Name)' is used but not declared. Add a Parameter $($subject.Name) declaration." $subject.Location
    }
}

function Test-BylawParameterOperator {
    # A parameter's type against the operator that uses it (ADR-0021).
    param(
        [Parameter(Mandatory)] [BylawParameter] $Parameter,
        [Parameter(Mandatory)] [string] $DslOperator,
        [BylawSourceLocation] $Location,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $name = $Parameter.Name
    $type = $Parameter.Type
    $operatorName = '-' + $DslOperator
    $singleValue = @('Be', 'BeLike', 'Match', 'MatchCase', 'ContainText', 'ContainKey', 'BeGreaterThan', 'BeGreaterOrEqual', 'BeLessThan', 'BeLessOrEqual')
    $comparison = @('BeGreaterThan', 'BeGreaterOrEqual', 'BeLessThan', 'BeLessOrEqual')
    $text = @('BeLike', 'Match', 'MatchCase', 'ContainText')

    if ($DslOperator -eq 'BeIn') {
        if ($type -ne 'Array') {
            & $Add 'BYL3024' "-BeIn needs a list, but parameter '$name' is of type $type. Declare it with -Type Array, or use -Be." $Location
        }
        return
    }
    if ($type -eq 'Array' -and $DslOperator -in $singleValue) {
        $hint = if ($DslOperator -eq 'Be') { ' Use -BeIn to match any value in the list.' } else { '' }
        & $Add 'BYL3023' "$operatorName compares with a single value, but parameter '$name' is an Array.$hint" $Location
        return
    }
    if ($type -in 'Boolean', 'Object' -and $DslOperator -in $text) {
        & $Add 'BYL3025' "$operatorName needs a string, but parameter '$name' is of type $type." $Location
        return
    }
    if ($DslOperator -in $comparison -and $type -notin 'Integer', 'Float', 'String', 'DateTime') {
        & $Add 'BYL3026' "$operatorName needs a number, string or date, but parameter '$name' is of type $type." $Location
    }
}

function Test-BylawParameterValueType {
    # Whether a PowerShell value fits an Azure parameter type (ADR-0021).
    param([AllowNull()] [object] $Value, [Parameter(Mandatory)] [string] $Type)

    if ($null -eq $Value) {
        return $true
    }
    switch ($Type) {
        'String' { return $Value -is [string] }
        'Boolean' { return $Value -is [bool] }
        'Integer' { return $Value -is [int] -or $Value -is [long] }
        'Float' { return $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] }
        'DateTime' {
            if ($Value -is [datetime]) {
                return $true
            }
            $parsed = [datetime]::MinValue
            return $Value -is [string] -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref] $parsed)
        }
        'Object' { return $Value -is [System.Collections.IDictionary] }
        'Array' { return $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary] }
    }
    $false
}

function Get-BylawUsedParameterName {
    # DSL names of the parameters a policy references: Param values and value-condition subjects in
    # assertions, tag names in Tag and ResourceGroupTag, the effect, and parameters('...') inside
    # Arm expressions (ADR-0021).
    param([Parameter(Mandatory)] [BylawPolicy] $Policy, [object[]] $Assertions = @())

    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($assertion in $Assertions) {
        foreach ($value in $assertion.Value, $assertion.Subject) {
            if ($null -ne $value) {
                $values.Add($value)
            }
        }
        if ($null -ne $assertion.Field -and $null -ne $assertion.Field.TagName) {
            $values.Add($assertion.Field.TagName)
        }
    }
    if ($null -ne $Policy.Effect -and $null -ne $Policy.Effect.Value) {
        $values.Add($Policy.Effect.Value)
    }
    # ResourceGroupTag (Param X) uses X.
    foreach ($value in @($values)) {
        if ($value -is [BylawResourceGroupTag]) {
            $values.Add($value.TagName)
        }
    }

    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $values) {
        if ($value -is [BylawParamRef]) {
            $null = $used.Add($value.Name)
        }
        elseif ($value -is [BylawExpr]) {
            foreach ($parameter in $Policy.Parameters) {
                $jsonName = Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
                if ($value.Text -match ("parameters\(\s*'" + [regex]::Escape($jsonName) + "'\s*\)")) {
                    $null = $used.Add($parameter.Name)
                }
            }
        }
    }
    , $used
}

function Get-BylawAssertion {
    # Every assertion in a resource scope, in source order, including inside Each and groups.
    param([Parameter(Mandatory)] [BylawResourceScope] $Scope)

    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($applicability in $Scope.When) {
        $queue.AddRange($applicability.Children)
    }
    foreach ($requirement in $Scope.Requirements) {
        $queue.AddRange($requirement.Children)
    }
    $index = 0
    while ($index -lt $queue.Count) {
        $node = $queue[$index]
        $index++
        if ($node -is [BylawEach] -or $node -is [BylawConditionGroup]) {
            $queue.InsertRange($index, $node.Children)
        }
        elseif ($node -is [BylawAssertion]) {
            $node
        }
    }
}

function Test-BylawValueIn {
    param([AllowNull()] [object] $Value, [object[]] $Values)

    foreach ($candidate in $Values) {
        if ($Value -is [string] -and $candidate -is [string]) {
            if ([string]::Equals($Value, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        elseif ($Value -eq $candidate) {
            return $true
        }
    }
    $false
}

function Test-BylawRuleLimit {
    # Limits Azure enforces when the definition is created (definition-structure-policy-rule).
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    if ($null -eq $Policy.Rule -or $null -eq $Policy.Rule.If) {
        return
    }
    $stats = @{ Conditions = 0; Counts = @{} }
    Measure-BylawCondition -Condition $Policy.Rule.If -Stats $stats

    if ($stats.Conditions -gt 4096) {
        [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL3051', "The compiled rule has $($stats.Conditions) condition expressions in 'if'; Azure allows at most 4096.", $Policy.Location)
    }
    foreach ($entry in $stats.Counts.GetEnumerator()) {
        if ($entry.Value.Count -gt 5) {
            [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL3050', "The compiled rule has $($entry.Value.Count) field count expressions on '$($entry.Key)'; Azure allows at most 5 per array. Combine the Each blocks for this array.", $entry.Value.Location)
        }
    }
}

function Measure-BylawCondition {
    param([Parameter(Mandatory)] [BylawCondition] $Condition, [Parameter(Mandatory)] [hashtable] $Stats)

    $Stats.Conditions++
    if ($Condition -is [BylawGroup]) {
        foreach ($child in $Condition.Children) {
            Measure-BylawCondition -Condition $child -Stats $Stats
        }
    }
    elseif ($Condition -is [BylawNot]) {
        Measure-BylawCondition -Condition $Condition.Child -Stats $Stats
    }
    elseif ($Condition -is [BylawCountCondition]) {
        if ($null -ne $Condition.Field) {
            $key = (Get-BylawFieldName -Field $Condition.Field).ToLowerInvariant()
            if (-not $Stats.Counts.ContainsKey($key)) {
                $Stats.Counts[$key] = @{ Count = 0; Location = $Condition.Location }
            }
            $Stats.Counts[$key].Count++
        }
        if ($null -ne $Condition.Where) {
            Measure-BylawCondition -Condition $Condition.Where -Stats $Stats
        }
    }
}
