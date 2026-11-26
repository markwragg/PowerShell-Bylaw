# Policy layer -> ordered objects, shared by every emitter (ADR-0006, ADR-0009 key order).

$script:BylawSupportedEffects = @('Audit', 'Deny', 'Disabled')

function Get-BylawParameterJsonName {
    # Emitted parameter name (ADR-0018): JsonName if set, else the DSL name with its
    # first character lower-cased (Effect -> effect, AllowedLocations -> allowedLocations).
    param([Parameter(Mandatory)] [string] $Name, [string] $JsonName)

    if ($JsonName) {
        return $JsonName
    }
    $Name.Substring(0, 1).ToLowerInvariant() + $Name.Substring(1)
}

function Get-BylawCanonicalEffect {
    # Canonical casing for a supported literal effect, or '' when it isn't supported in 1.0.
    param([Parameter(Mandatory)] [string] $Effect)

    foreach ($candidate in $script:BylawSupportedEffects) {
        if ([string]::Equals($candidate, $Effect, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }
    ''
}

function ConvertTo-BylawValueObject {
    # The JSON value for an IR value.
    param(
        [AllowNull()] [BylawValue] $Value,
        [Parameter(Mandatory)] [BylawPolicy] $Policy
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [BylawParamRef]) {
        $parameter = $Policy.FindParameter($Value.Name)
        $jsonName = if ($parameter) {
            Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
        }
        else {
            Get-BylawParameterJsonName -Name $Value.Name
        }
        return "[parameters('$jsonName')]"
    }
    if ($Value -is [BylawExpr]) {
        return $Value.Text
    }
    # Keep arrays as arrays even when they have one element.
    , $Value.Value
}

function ConvertTo-BylawConditionObject {
    # The JSON object for a policy-layer condition.
    param(
        [Parameter(Mandatory)] [BylawCondition] $Condition,
        [Parameter(Mandatory)] [BylawPolicy] $Policy
    )

    if ($Condition -is [BylawGroup]) {
        $key = if ($Condition.Kind -eq [BylawGroupKind]::AllOf) { 'allOf' } else { 'anyOf' }
        $children = foreach ($child in $Condition.Children) {
            ConvertTo-BylawConditionObject -Condition $child -Policy $Policy
        }
        return [ordered]@{ $key = @($children) }
    }
    if ($Condition -is [BylawNot]) {
        return [ordered]@{ not = (ConvertTo-BylawConditionObject -Condition $Condition.Child -Policy $Policy) }
    }
    if ($Condition -is [BylawFieldCondition]) {
        $result = [ordered]@{ field = (Get-BylawFieldName -Field $Condition.Field) }
        $result[$Condition.Operator] = ConvertTo-BylawValueObject -Value $Condition.Value -Policy $Policy
        return $result
    }
    if ($Condition -is [BylawValueCondition]) {
        $result = [ordered]@{ value = (ConvertTo-BylawValueObject -Value $Condition.Subject -Policy $Policy) }
        $result[$Condition.Operator] = ConvertTo-BylawValueObject -Value $Condition.Value -Policy $Policy
        return $result
    }
    if ($Condition -is [BylawCountCondition]) {
        $count = [ordered]@{}
        if ($null -ne $Condition.Field) {
            $count['field'] = Get-BylawFieldName -Field $Condition.Field
        }
        else {
            $count['value'] = ConvertTo-BylawValueObject -Value $Condition.ValueSource -Policy $Policy
        }
        if ($Condition.Name) {
            $count['name'] = $Condition.Name
        }
        if ($null -ne $Condition.Where) {
            $count['where'] = ConvertTo-BylawConditionObject -Condition $Condition.Where -Policy $Policy
        }
        $result = [ordered]@{ count = $count }
        $result[$Condition.Operator] = ConvertTo-BylawValueObject -Value $Condition.Value -Policy $Policy
        return $result
    }
    throw [System.ArgumentException]::new("Unsupported condition type [$($Condition.GetType().Name)].")
}

function ConvertTo-BylawPolicyRuleObject {
    # { "if": ..., "then": { "effect": ... } }
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $effectValue = $Policy.Rule.Then.Value
    $effect = if ($effectValue -is [BylawLiteral]) {
        $canonical = Get-BylawCanonicalEffect -Effect ([string] $effectValue.Value)
        if ($canonical) { $canonical } else { [string] $effectValue.Value }
    }
    else {
        ConvertTo-BylawValueObject -Value $effectValue -Policy $Policy
    }
    [ordered]@{
        if   = ConvertTo-BylawConditionObject -Condition $Policy.Rule.If -Policy $Policy
        then = [ordered]@{ effect = $effect }
    }
}

function Get-BylawFieldName {
    param([Parameter(Mandatory)] [BylawFieldRef] $Field)

    if ($Field.Resolved) {
        return $Field.Resolved
    }
    $Field.Name
}
