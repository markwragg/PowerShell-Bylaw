# Reads a policy condition, as a hashtable or JSON text, into the policy-layer IR (ADR-0040). The
# Condition keyword uses it, and the decompiler will read whole rules with it (ADR-0039).
#
# A condition is exactly one of: allOf, anyOf or not; a field condition { field, <operator> }; a
# value condition { value, <operator> }; or a count { count = { field | value, name?, where? },
# <operator> }. Keys are matched ignoring case, as Azure does.

$script:BylawRawCountOperators = @('equals', 'notEquals', 'greater', 'greaterOrEquals', 'less', 'lessOrEquals', 'in', 'notIn')

function Find-BylawConditionKey {
    # The key in Dictionary that matches Name ignoring case, or $null.
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Dictionary, [Parameter(Mandatory)] [string] $Name)

    foreach ($key in $Dictionary.Keys) {
        if ([string]::Equals([string] $key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $key
        }
    }
    $null
}

function ConvertFrom-BylawConditionObject {
    # The policy-layer condition for Object, or $null after adding a message to Errors. Path names
    # the place in the condition for messages, e.g. 'allOf[1].count.where'.
    param(
        [AllowNull()] [object] $Object,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $Errors,
        [string] $Path = 'condition',
        [BylawSourceLocation] $Location
    )

    if ($Object -isnot [System.Collections.IDictionary]) {
        $Errors.Add("$Path must be a condition (a hashtable), not $(if ($null -eq $Object) { 'nothing' } else { "a $($Object.GetType().Name)" }).")
        return $null
    }

    $kinds = @('allOf', 'anyOf', 'not', 'field', 'value', 'count' | Where-Object { $null -ne (Find-BylawConditionKey -Dictionary $Object -Name $_) })
    if ($kinds.Count -ne 1) {
        $found = if ($kinds.Count -eq 0) { 'none' } else { $kinds -join ', ' }
        $Errors.Add("$Path needs exactly one of allOf, anyOf, not, field, value or count (found $found).")
        return $null
    }
    $kind = $kinds[0]
    $key = Find-BylawConditionKey -Dictionary $Object -Name $kind

    if ($kind -in 'allOf', 'anyOf') {
        if ($Object.Count -ne 1) {
            $Errors.Add("$Path.$kind can't have other keys beside it.")
            return $null
        }
        $items = $Object[$key]
        if ($items -isnot [System.Collections.IEnumerable] -or $items -is [string] -or $items -is [System.Collections.IDictionary] -or @($items).Count -eq 0) {
            $Errors.Add("$Path.$kind needs a list of conditions.")
            return $null
        }
        $children = [System.Collections.Generic.List[object]]::new()
        $index = 0
        foreach ($item in @($items)) {
            $child = ConvertFrom-BylawConditionObject -Object $item -Errors $Errors -Path "$Path.$kind[$index]" -Location $Location
            if ($null -ne $child) {
                $children.Add($child)
            }
            $index++
        }
        if ($children.Count -ne @($items).Count) {
            return $null
        }
        $group = [BylawGroup]::new([BylawGroupKind]::$kind, $children.ToArray())
        $group.Location = $Location
        return $group
    }

    if ($kind -eq 'not') {
        if ($Object.Count -ne 1) {
            $Errors.Add("$Path.not can't have other keys beside it.")
            return $null
        }
        $child = ConvertFrom-BylawConditionObject -Object $Object[$key] -Errors $Errors -Path "$Path.not" -Location $Location
        if ($null -eq $child) {
            return $null
        }
        $not = [BylawNot]::new($child)
        $not.Location = $Location
        return $not
    }

    # A field, value or count condition: the subject and exactly one operator.
    $operators = @($Object.Keys | Where-Object { -not [string]::Equals([string] $_, $key, [System.StringComparison]::OrdinalIgnoreCase) })
    $unknown = @($operators | Where-Object { -not [BylawOperator]::IsValid([string] $_) })
    if ($unknown.Count -gt 0) {
        $Errors.Add("$Path has $(if ($unknown.Count -eq 1) { 'an unknown key' } else { 'unknown keys' }): $($unknown -join ', '). A $kind condition takes one operator, such as equals, in, like or exists.")
        return $null
    }
    if ($operators.Count -ne 1) {
        $Errors.Add("$Path needs exactly one operator beside $kind (found $(if ($operators.Count -eq 0) { 'none' } else { $operators -join ', ' })).")
        return $null
    }
    $operator = [BylawOperator]::Canonical([string] $operators[0])
    $value = ConvertTo-BylawConditionValue -Value $Object[$operators[0]] -Operator $operator -Errors $Errors -Path "$Path.$operator" -Location $Location
    if ($null -eq $value) {
        return $null
    }

    if ($kind -eq 'field') {
        $name = $Object[$key]
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
            $Errors.Add("$Path.field needs a field name or alias.")
            return $null
        }
        $field = [BylawFieldRef]::new($name)
        $field.Location = $Location
        $condition = [BylawFieldCondition]::new($field, $operator, $value)
        $condition.Location = $Location
        return $condition
    }

    if ($kind -eq 'value') {
        $subject = ConvertTo-BylawConditionValue -Value $Object[$key] -Operator 'value' -Errors $Errors -Path "$Path.value" -Location $Location
        if ($null -eq $subject) {
            return $null
        }
        $condition = [BylawValueCondition]::new($subject, $operator, $value)
        $condition.Location = $Location
        return $condition
    }

    # count
    if ($operator -notin $script:BylawRawCountOperators) {
        $Errors.Add("$Path compares a count with $operator. A count takes $($script:BylawRawCountOperators -join ', ').")
        return $null
    }
    $count = $Object[$key]
    if ($count -isnot [System.Collections.IDictionary]) {
        $Errors.Add("$Path.count needs a hashtable with field or value, and optionally name and where.")
        return $null
    }
    $countField = Find-BylawConditionKey -Dictionary $count -Name 'field'
    $countValue = Find-BylawConditionKey -Dictionary $count -Name 'value'
    $countName = Find-BylawConditionKey -Dictionary $count -Name 'name'
    $countWhere = Find-BylawConditionKey -Dictionary $count -Name 'where'
    $extra = @($count.Keys | Where-Object { $_ -notin @($countField, $countValue, $countName, $countWhere) })
    if ($extra.Count -gt 0) {
        $Errors.Add("$Path.count has unknown keys: $($extra -join ', '). It takes field or value, name and where.")
        return $null
    }
    if (($null -eq $countField) -eq ($null -eq $countValue)) {
        $Errors.Add("$Path.count needs exactly one of field (an array alias ending in [*]) and value (a list).")
        return $null
    }
    $where = $null
    if ($null -ne $countWhere) {
        $where = ConvertFrom-BylawConditionObject -Object $count[$countWhere] -Errors $Errors -Path "$Path.count.where" -Location $Location
        if ($null -eq $where) {
            return $null
        }
    }
    $arrayField = $null
    if ($null -ne $countField) {
        $arrayName = $count[$countField]
        if ($arrayName -isnot [string] -or -not $arrayName.EndsWith('[*]')) {
            $Errors.Add("$Path.count.field needs an array alias ending in [*].")
            return $null
        }
        $arrayField = [BylawFieldRef]::new($arrayName)
        $arrayField.Location = $Location
    }
    $condition = [BylawCountCondition]::new($arrayField, $where, $operator, $value)
    $condition.Location = $Location
    if ($null -ne $countValue) {
        $source = ConvertTo-BylawConditionValue -Value $count[$countValue] -Operator 'count' -Errors $Errors -Path "$Path.count.value" -Location $Location
        if ($null -eq $source) {
            return $null
        }
        $condition.ValueSource = $source
    }
    if ($null -ne $countName) {
        $name = $count[$countName]
        if ($name -isnot [string] -or $name -notmatch '^[A-Za-z0-9]+$') {
            $Errors.Add("$Path.count.name needs letters and digits only.")
            return $null
        }
        if ($null -eq $countValue) {
            $Errors.Add("$Path.count.name is only for a value count.")
            return $null
        }
        $condition.Name = $name
    }
    $condition
}

function ConvertTo-BylawConditionValue {
    # An operator's value, a value condition's subject or a value count's list, as an IR value.
    # Param and Arm stay references; anything else is a literal (ConvertTo-BylawValue).
    param(
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [string] $Operator,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $Errors,
        [Parameter(Mandatory)] [string] $Path,
        [BylawSourceLocation] $Location
    )

    if ($Operator -eq 'exists') {
        if ($Value -is [bool] -or $Value -in 'true', 'false') {
            $literal = [BylawLiteral]::new([bool]::Parse([string] $Value))
            $literal.Location = $Location
            return $literal
        }
        $Errors.Add("$Path needs `$true or `$false.")
        return $null
    }
    if ($Value -is [BylawCount] -or $Value -is [BylawFieldRef]) {
        $Errors.Add("$Path can't be a $($Value.GetType().Name.Substring(5)); write it as an expression with Arm, e.g. Arm `"[current('name')]`".")
        return $null
    }
    # ConvertTo-BylawValue reports its own problems (BYL1020) and returns $null.
    ConvertTo-BylawValue -Value $Value -Location $Location
}
