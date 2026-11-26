# Plain JSON policy definition emitter (ADR-0027).
#
#   { "name": ..., "properties": { displayName, policyType, mode, description?, metadata?,
#     parameters?, policyRule } }
#
# The layout Azure publishes built-in definitions in, without id. Unlike EPAC, the policy is
# emitted as written: a literal effect stays literal, no parameter display names are generated,
# and empty description, metadata and parameters are left out.

function Test-BylawPlainJsonPolicy {
    # Plain JSON has no rules beyond the language's own, which validation already checked. The
    # parameter is part of the emitter contract (Emitter.ps1).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Policy', Justification = 'Required by the emitter contract; plain JSON has no format rules.')]
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)
}

function ConvertTo-BylawPlainJsonDocument {
    # The plain JSON file as an ordered dictionary. The policy must be compiled (Policy.Rule set).
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    if ($null -eq $Policy.Rule) {
        throw [System.ArgumentException]::new("Policy '$($Policy.Name)' has not been compiled.")
    }

    $properties = [ordered]@{
        displayName = $Policy.Properties.DisplayName
        policyType  = 'Custom'
        mode        = Get-BylawCanonicalMode -Properties $Policy.Properties
    }
    if ($Policy.Properties.Description) {
        $properties['description'] = $Policy.Properties.Description
    }
    $metadata = ConvertTo-BylawMetadataObject -Properties $Policy.Properties
    if ($metadata.Count -gt 0) {
        $properties['metadata'] = $metadata
    }
    if ($Policy.Parameters.Count -gt 0) {
        $parameters = [ordered]@{}
        foreach ($parameter in $Policy.Parameters) {
            $displayName = Get-BylawParameterMetadataText -Parameter $parameter -Key displayName
            $description = Get-BylawParameterMetadataText -Parameter $parameter -Key description
            $parameters[(Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName)] = ConvertTo-BylawParameterObject -Parameter $parameter -DisplayName $displayName -Description $description
        }
        $properties['parameters'] = $parameters
    }
    $properties['policyRule'] = ConvertTo-BylawPolicyRuleObject -Policy $Policy

    [ordered]@{
        name       = $Policy.Name
        properties = $properties
    }
}
