# EPAC policy definition emitter (ADR-0011, ADR-0023).
#
#   { "$schema": ..., "name": ..., "properties": { displayName, policyType, mode, description,
#     metadata, parameters, policyRule } }
#
# Test-BylawEpacPolicy reports what the EPAC schema needs that the policy lacks; run it first.

$script:BylawEpacSchemaUrl = 'https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json'
$script:BylawEffectDescription = 'Enable or disable the execution of the policy'

function Get-BylawEpacEffectParameter {
    # The parameter behind the effect: the declared one for Effect (Param X), or a generated
    # 'effect' parameter for a literal effect (ADR-0023). $null for an Arm effect.
    # Returns @{ Parameter; Generated }.
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $value = $Policy.Effect.Value
    if ($value -is [BylawParamRef]) {
        $declared = $Policy.FindParameter($value.Name)
        if ($null -eq $declared) {
            return $null
        }
        return @{ Parameter = $declared; Generated = $false }
    }
    if ($value -isnot [BylawLiteral]) {
        return $null
    }
    # A keyword in place of Effect allows its own effect and Disabled, as built-in policies do
    # (ADR-0024, ADR-0029).
    $supported = Get-BylawAllowedEffect -Effect $Policy.Effect -Generated
    $generated = [BylawParameter]::new('effect')
    $generated.JsonName = 'effect'
    $generated.Type = 'String'
    $generated.AllowedValues = $supported
    $generated.HasDefault = $true
    $generated.DefaultValue = Get-BylawCanonicalEffect -Effect ([string] $value.Value) -Supported $supported
    $generated.Location = $Policy.Effect.Location
    @{ Parameter = $generated; Generated = $true }
}

function Test-BylawEpacPolicy {
    # BYL4xxx: rules of the EPAC schema that Azure doesn't enforce (ADR-0023).
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $properties = $Policy.Properties
    $propertiesLocation = if ($properties) { $properties.Location } else { $Policy.Location }
    $new = {
        param([string] $Code, [string] $Message, [BylawSourceLocation] $Location, [BylawSeverity] $Severity = [BylawSeverity]::Error)
        [BylawDiagnostic]::new($Severity, $Code, $Message, $Location)
    }

    if (-not $properties -or -not $properties.Category) {
        & $new 'BYL4001' "EPAC definitions need a category: add Category to Properties, e.g. Category = 'Storage' (ADR-0023)." $propertiesLocation
    }
    if (-not $properties -or -not $properties.Version) {
        & $new 'BYL4002' "EPAC definitions need a version: add Version to Properties, e.g. Version = '1.0.0' (ADR-0023)." $propertiesLocation
    }

    foreach ($parameter in $Policy.Parameters) {
        if ($parameter.Type -eq 'DateTime') {
            & $new 'BYL4009' "Parameter '$($parameter.Name)' is a DateTime. Azure accepts it, but the EPAC schema doesn't list the type, so editors will flag the file." $parameter.Location ([BylawSeverity]::Warning)
        }
    }

    if ($null -eq $Policy.Effect) {
        return
    }
    if ($Policy.Effect -is [BylawAppend]) {
        & $new 'BYL4010' "Append details are an array, as Azure requires. EPAC deploys it, but the EPAC schema says details is an object, so editors will flag the file (ADR-0030)." $Policy.Effect.Location ([BylawSeverity]::Warning)
    }
    $effectValue = $Policy.Effect.Value
    if ($effectValue -is [BylawExpr]) {
        & $new 'BYL4008' "EPAC definitions need the effect to be [parameters('effect')]. Use Effect (Param Effect) instead of an Arm expression (ADR-0023)." $Policy.Effect.Location
        return
    }

    $effect = Get-BylawEpacEffectParameter -Policy $Policy
    if ($null -eq $effect) {
        # An undeclared parameter, already reported by validation.
        return
    }
    if ($effect.Generated) {
        $clash = $Policy.Parameters | Where-Object { (Get-BylawParameterJsonName -Name $_.Name -JsonName $_.JsonName) -eq 'effect' } | Select-Object -First 1
        if ($clash) {
            & $new 'BYL4007' "Effect is a literal, but parameter '$($clash.Name)' already has the JSON name 'effect'. Use Effect (Param $($clash.Name))." $Policy.Effect.Location
        }
        return
    }

    $parameter = $effect.Parameter
    $jsonName = Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
    if ($jsonName -cne 'effect') {
        & $new 'BYL4003' "EPAC needs the effect parameter to be named 'effect', but '$($parameter.Name)' is emitted as '$jsonName'. Rename it to Effect, or set JsonName = 'effect'." $parameter.Location
    }
    if (-not $parameter.HasDefault -or $null -eq $parameter.DefaultValue) {
        & $new 'BYL4004' "EPAC needs the effect parameter '$($parameter.Name)' to have a default, e.g. -Default Deny." $parameter.Location
    }
    $distinct = @($parameter.AllowedValues | ForEach-Object { ([string] $_).ToLowerInvariant() } | Select-Object -Unique)
    if ($distinct.Count -lt 2) {
        & $new 'BYL4005' "EPAC needs the effect parameter '$($parameter.Name)' to allow at least 2 distinct effects, e.g. -AllowedValues Audit, Deny, Disabled." $parameter.Location
    }
    $displayName = Get-BylawParameterMetadataText -Parameter $parameter -Key displayName
    if ($displayName -and $displayName -cne 'Effect') {
        & $new 'BYL4006' "EPAC needs the effect parameter's display name to be 'Effect' (it is '$displayName'). Remove DisplayName; Bylaw sets it." $parameter.Location
    }
}

function ConvertTo-BylawEpacDocument {
    # The EPAC file as an ordered dictionary. The policy must be compiled (Policy.Rule set).
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    if ($null -eq $Policy.Rule) {
        throw [System.ArgumentException]::new("Policy '$($Policy.Name)' has not been compiled.")
    }

    $effect = Get-BylawEpacEffectParameter -Policy $Policy
    $effectParameter = if ($effect) { $effect.Parameter } else { $null }

    $parameters = [ordered]@{}
    foreach ($parameter in $Policy.Parameters) {
        $isEffect = [object]::ReferenceEquals($parameter, $effectParameter)
        $parameters[(Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName)] = ConvertTo-BylawEpacParameterObject -Parameter $parameter -IsEffect $isEffect
    }
    if ($effect -and $effect.Generated) {
        $parameters['effect'] = ConvertTo-BylawEpacParameterObject -Parameter $effectParameter -IsEffect $true
    }

    $policyRule = ConvertTo-BylawPolicyRuleObject -Policy $Policy
    if ($effect -and $effect.Generated) {
        $policyRule['then']['effect'] = "[parameters('effect')]"
    }

    $properties = [ordered]@{
        displayName = $Policy.Properties.DisplayName
        policyType  = 'Custom'
        mode        = Get-BylawCanonicalMode -Properties $Policy.Properties
    }
    if ($Policy.Properties.Description) {
        $properties['description'] = $Policy.Properties.Description
    }
    $properties['metadata'] = ConvertTo-BylawMetadataObject -Properties $Policy.Properties
    $properties['parameters'] = $parameters
    $properties['policyRule'] = $policyRule

    [ordered]@{
        '$schema'  = $script:BylawEpacSchemaUrl
        name       = $Policy.Name
        properties = $properties
    }
}

function ConvertTo-BylawEpacParameterObject {
    # A parameter with EPAC's metadata: displayName is always set (ADR-0023).
    param([Parameter(Mandatory)] [BylawParameter] $Parameter, [Parameter(Mandatory)] [bool] $IsEffect)

    $displayName = Get-BylawParameterMetadataText -Parameter $Parameter -Key displayName
    $description = Get-BylawParameterMetadataText -Parameter $Parameter -Key description
    if ($IsEffect) {
        $displayName = 'Effect'
        if (-not $description) {
            $description = $script:BylawEffectDescription
        }
    }
    elseif (-not $displayName) {
        $displayName = Get-BylawGeneratedDisplayName -Name $Parameter.Name
    }
    ConvertTo-BylawParameterObject -Parameter $Parameter -DisplayName $displayName -Description $description
}
