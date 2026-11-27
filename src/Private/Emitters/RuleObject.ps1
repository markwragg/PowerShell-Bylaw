# Policy layer -> ordered objects, shared by every emitter (ADR-0006, ADR-0009 key order).

$script:BylawSupportedEffects = @('Audit', 'Deny', 'Disabled')
# Effects a Modify block's effect may take (ADR-0024). Audit was measured in the sandbox on
# 2026-11-26: with a managed identity, an assignment with effect Audit reports compliance.
$script:BylawModifyEffects = @('Modify', 'Audit', 'Disabled')
# The allowed values of the effect parameter generated for a literal Modify, as built-in Modify
# policies use.
$script:BylawModifyGeneratedEffects = @('Modify', 'Disabled')

# Keywords that take the place of Effect (ADR-0017). Allowed: the values the keyword's effect
# parameter may allow. Generated: the allowed values of the EPAC effect parameter generated for a
# literal effect, which is the keyword's own effect.
$script:BylawEffectKeywords = [ordered]@{
    Modify     = @{ Allowed = $script:BylawModifyEffects; Generated = $script:BylawModifyGeneratedEffects; Example = "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }" }
    Append     = @{ Allowed = @('Append', 'Disabled'); Generated = @('Append', 'Disabled'); Example = 'Append { Field supportsHttpsTrafficOnly | Add $true }' }
    AuditIfNotExists = @{ Allowed = @('AuditIfNotExists', 'Disabled'); Generated = @('AuditIfNotExists', 'Disabled'); Example = "AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' { Require ... }" }
    DeployIfNotExists = @{ Allowed = @('DeployIfNotExists', 'AuditIfNotExists', 'Disabled'); Generated = @('DeployIfNotExists', 'Disabled'); Example = "DeployIfNotExists -Type '...' -Role 'Contributor' { Require ...; Deployment ... }" }
    DenyAction = @{ Allowed = @('DenyAction', 'Disabled'); Generated = @('DenyAction', 'Disabled'); Example = 'DenyAction Delete' }
    Manual     = @{ Allowed = @('Manual', 'Disabled'); Generated = @('Manual', 'Disabled'); Example = 'Manual -DefaultState Unknown' }
}

function Get-BylawEffectKeyword {
    # The keyword that set an effect: Effect, Modify, DenyAction or Manual.
    [OutputType([string])]
    param([Parameter(Mandatory)] [BylawEffect] $Effect)

    if ($Effect -is [BylawModify]) { return 'Modify' }
    if ($Effect -is [BylawAppend]) { return 'Append' }
    if ($Effect -is [BylawAuditIfNotExists]) { return 'AuditIfNotExists' }
    if ($Effect -is [BylawDeployIfNotExists]) { return 'DeployIfNotExists' }
    if ($Effect -is [BylawDenyAction]) { return 'DenyAction' }
    if ($Effect -is [BylawManual]) { return 'Manual' }
    'Effect'
}

function Get-BylawAllowedEffect {
    # The effects an effect may take, by the keyword that set it. -Generated gives the allowed values
    # of a generated EPAC effect parameter instead.
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [BylawEffect] $Effect, [switch] $Generated)

    $keyword = Get-BylawEffectKeyword -Effect $Effect
    if ($keyword -eq 'Effect') {
        return $script:BylawSupportedEffects
    }
    $entry = $script:BylawEffectKeywords[$keyword]
    if ($Generated) { $entry.Generated } else { $entry.Allowed }
}

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
    param([Parameter(Mandatory)] [string] $Effect, [string[]] $Supported = $script:BylawSupportedEffects)

    foreach ($candidate in $Supported) {
        if ([string]::Equals($candidate, $Effect, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }
    ''
}

function Get-BylawCurrentExpression {
    # The expression for Current, without brackets (ADR-0032): current('name') for a named value
    # count, current('<array alias>[*]') for a field count, or current() for an unnamed value count.
    [OutputType([string])]
    param([Parameter(Mandatory)] [BylawCurrent] $Current)

    if ($Current.Name) {
        return "current('$($Current.Name)')"
    }
    $count = $Current.Count
    if ($count.IsFieldCount()) {
        return "current('$(Get-BylawFieldName -Field $count.Field)')"
    }
    if ($count.Name) {
        return "current('$($count.Name)')"
    }
    'current()'
}

function ConvertTo-BylawValueObject {
    # The JSON value for an IR value.
    param(
        [AllowNull()] [BylawValue] $Value,
        # A policy or an initiative: whatever declares the parameters a Param refers to.
        [Parameter(Mandatory)] [BylawNode] $Policy
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
    if ($Value -is [BylawParamLength]) {
        $parameterValue = ConvertTo-BylawValueObject -Value $Value.Parameter -Policy $Policy
        return "[length($($parameterValue.Substring(1, $parameterValue.Length - 2)))]"
    }
    if ($Value -is [BylawExpr]) {
        return $Value.Text
    }
    if ($Value -is [BylawCurrent]) {
        return "[$(Get-BylawCurrentExpression -Current $Value)]"
    }
    if ($Value -is [BylawResourceGroupTag]) {
        # [resourceGroup().tags['name']], or with a parameter [resourceGroup().tags[parameters('x')]].
        if ($Value.TagName -is [BylawCurrent]) {
            return "[resourceGroup().tags[$(Get-BylawCurrentExpression -Current $Value.TagName)]]"
        }
        if ($Value.TagName -is [BylawParamRef]) {
            $parameterValue = ConvertTo-BylawValueObject -Value $Value.TagName -Policy $Policy
            return "[resourceGroup().tags[$($parameterValue.Substring(1, $parameterValue.Length - 2))]]"
        }
        return "[resourceGroup().tags['$($Value.TagName.Value)']]"
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
    # { "if": ..., "then": { "effect": ..., "details": ... } }
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $then = $Policy.Rule.Then
    $supported = Get-BylawAllowedEffect -Effect $then
    $effectValue = $then.Value
    $effect = if ($effectValue -is [BylawLiteral]) {
        $canonical = Get-BylawCanonicalEffect -Effect ([string] $effectValue.Value) -Supported $supported
        if ($canonical) { $canonical } else { [string] $effectValue.Value }
    }
    else {
        ConvertTo-BylawValueObject -Value $effectValue -Policy $Policy
    }
    $thenObject = [ordered]@{ effect = $effect }
    if ($then -is [BylawModify]) {
        $thenObject['details'] = ConvertTo-BylawModifyDetailsObject -Modify $then -Policy $Policy
    }
    elseif ($then -is [BylawAppend]) {
        # [ { field, value } ], in the order written (ADR-0029).
        $operations = foreach ($operation in $then.Operations) {
            [ordered]@{
                field = Get-BylawFieldName -Field $operation.Field
                value = ConvertTo-BylawValueObject -Value $operation.Value -Policy $Policy
            }
        }
        $thenObject['details'] = [object[]] @($operations)
    }
    elseif ($then -is [BylawIfNotExists]) {
        $thenObject['details'] = ConvertTo-BylawIfNotExistsDetailsObject -Effect $then -Policy $Policy
    }
    elseif ($then -is [BylawDenyAction]) {
        # { actionNames, cascadeBehaviors? }, in Learn's order (ADR-0028).
        $details = [ordered]@{ actionNames = [object[]] @($then.ActionNames) }
        if ($then.CascadeBehavior) {
            $details['cascadeBehaviors'] = [ordered]@{ resourceGroup = $then.CascadeBehavior }
        }
        $thenObject['details'] = $details
    }
    elseif ($then -is [BylawManual] -and $then.DefaultState) {
        $thenObject['details'] = [ordered]@{ defaultState = $then.DefaultState }
    }
    [ordered]@{
        if   = ConvertTo-BylawConditionObject -Condition $Policy.Rule.If -Policy $Policy
        then = $thenObject
    }
}

function ConvertTo-BylawIfNotExistsDetailsObject {
    # { type, name?, resourceGroupName?, existenceScope?, evaluationDelay?, existenceCondition? },
    # in the order Learn documents them (ADR-0030).
    param([Parameter(Mandatory)] [BylawIfNotExists] $Effect, [Parameter(Mandatory)] [BylawPolicy] $Policy)

    $type = if ($Effect.ResolvedType) { $Effect.ResolvedType } else { $Effect.Type }
    $details = [ordered]@{ type = $type }
    if ($null -ne $Effect.Name) {
        $details['name'] = ConvertTo-BylawValueObject -Value $Effect.Name -Policy $Policy
    }
    if ($null -ne $Effect.ResourceGroupName) {
        $details['resourceGroupName'] = ConvertTo-BylawValueObject -Value $Effect.ResourceGroupName -Policy $Policy
    }
    if ($Effect.ExistenceScope) {
        $details['existenceScope'] = $Effect.ExistenceScope
    }
    if ($Effect.EvaluationDelay) {
        $details['evaluationDelay'] = $Effect.EvaluationDelay
    }
    if ($null -ne $Effect.ExistenceCondition) {
        $details['existenceCondition'] = ConvertTo-BylawConditionObject -Condition $Effect.ExistenceCondition -Policy $Policy
    }
    if ($Effect -is [BylawDeployIfNotExists]) {
        # roleDefinitionIds, deploymentScope?, deployment { location?, properties { mode, template,
        # parameters } } (ADR-0031).
        $details['roleDefinitionIds'] = [object[]] @($Effect.RoleDefinitionIds)
        $deployment = $Effect.Deployment
        if ($deployment.Scope) {
            $details['deploymentScope'] = $deployment.Scope
        }
        $deploymentObject = [ordered]@{}
        if ($null -ne $deployment.DeploymentLocation) {
            $deploymentObject['location'] = ConvertTo-BylawValueObject -Value $deployment.DeploymentLocation -Policy $Policy
        }
        $properties = [ordered]@{
            mode     = 'incremental'
            template = $deployment.Template
        }
        if ($deployment.Parameters.Count -gt 0) {
            $parameters = [ordered]@{}
            foreach ($entry in $deployment.Parameters.GetEnumerator()) {
                $parameters[$entry.Key] = [ordered]@{ value = ConvertTo-BylawValueObject -Value $entry.Value -Policy $Policy }
            }
            $properties['parameters'] = $parameters
        }
        $deploymentObject['properties'] = $properties
        $details['deployment'] = $deploymentObject
    }
    $details
}

function ConvertTo-BylawModifyDetailsObject {
    # { roleDefinitionIds, conflictEffect?, operations: [ { operation, field, value?, condition? } ] },
    # in the order Learn's examples use (ADR-0024).
    param([Parameter(Mandatory)] [BylawModify] $Modify, [Parameter(Mandatory)] [BylawPolicy] $Policy)

    $details = [ordered]@{ roleDefinitionIds = [object[]] @($Modify.RoleDefinitionIds) }
    if ($Modify.ConflictEffect) {
        $details['conflictEffect'] = $Modify.ConflictEffect
    }
    $operations = foreach ($operation in $Modify.Operations) {
        $object = [ordered]@{
            operation = $operation.Operation
            field     = Get-BylawFieldName -Field $operation.Field
        }
        if ($null -ne $operation.Value) {
            $object['value'] = ConvertTo-BylawValueObject -Value $operation.Value -Policy $Policy
        }
        if ($null -ne $operation.Condition) {
            $object['condition'] = $operation.Condition.Text
        }
        $object
    }
    $details['operations'] = [object[]] @($operations)
    $details
}

function Get-BylawFieldName {
    param([Parameter(Mandatory)] [BylawFieldRef] $Field)

    if ($Field.Resolved) {
        return $Field.Resolved
    }
    $Field.Name
}
