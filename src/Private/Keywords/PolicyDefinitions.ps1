# PolicyDefinition and DefinitionGroup, inside Initiative (ADR-0033).

# definitionVersion: a major version, then a minor version or *, then a patch or *, optionally -preview.
$script:BylawDefinitionVersionPattern = '^\d+\.(\d+|\*)\.(\d+|\*)(-preview)?$'

function PolicyDefinition {
    <#
    .SYNOPSIS
        A policy the initiative includes: a policy from this build by name, or any definition by ID.

    .EXAMPLE
        PolicyDefinition 'tags-require-mandatory-tags' -Parameters @{ effect = Param Effect }

    .EXAMPLE
        PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' -ReferenceId 'InheritCostCenter' -Version '1.*.*' -Parameters @{ tagName = 'CostCenter' }
    #>
    [CmdletBinding()]
    param(
        # The name of a policy in this build.
        [Parameter(Position = 0)]
        [string] $Name,

        # A definition ID, for a built-in policy or one outside this build.
        [string] $Id,

        # The member's policyDefinitionReferenceId. Defaults to the policy name; required with -Id.
        [string] $ReferenceId,

        # Values for the member's parameters: a literal, Param, Arm or ResourceGroupTag.
        [System.Collections.IDictionary] $Parameters,

        # The definition version to use, e.g. '1.*.*'.
        [string] $Version,

        # The definition groups the member belongs to.
        [string[]] $Group
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'PolicyDefinition')
    $frame = Test-BylawParent -Keyword 'PolicyDefinition' -Allowed 'Initiative' -Location $location
    if ($null -eq $frame) {
        return
    }
    # Initiative reports "no PolicyDefinition" only when there was none at all, not when each one failed.
    $frame.Singletons['PolicyDefinition'] = $location

    $hasName = -not [string]::IsNullOrWhiteSpace($Name)
    $hasId = -not [string]::IsNullOrWhiteSpace($Id)
    if ($hasName -eq $hasId) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1055' -Location $location -Message (
            "PolicyDefinition takes a policy name or -Id, not both: PolicyDefinition 'policy-name' for a policy in this build, or PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/<guid>' -ReferenceId 'Name'."
        )
        return
    }
    $member = [BylawInitiativeMember]::new()
    $member.Location = $location
    $valid = $true

    if ($hasName) {
        $member.PolicyName = $Name
    }
    else {
        $member.DefinitionId = $Id
    }
    if ($PSBoundParameters.ContainsKey('ReferenceId')) {
        if ([string]::IsNullOrWhiteSpace($ReferenceId)) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1056' -Location $location -Message '-ReferenceId needs a value, e.g. -ReferenceId InheritCostCenter.'
            $valid = $false
        }
        $member.ReferenceId = $ReferenceId
    }
    elseif ($hasId) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1056' -Location $location -Message (
            'PolicyDefinition -Id needs -ReferenceId: the short name the initiative uses for the member, e.g. -ReferenceId InheritCostCenter.'
        )
        $valid = $false
    }
    else {
        $member.ReferenceId = $Name
    }

    if ($PSBoundParameters.ContainsKey('Version')) {
        if ($Version -notmatch $script:BylawDefinitionVersionPattern) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1053' -Location $location -Message (
                "-Version '$Version' is not a definition version. Use a major version, then a minor version or *, then a patch or *, e.g. '1.*.*' or '2.1.*'."
            )
            $valid = $false
        }
        $member.Version = $Version
    }

    if ($PSBoundParameters.ContainsKey('Parameters')) {
        # An [ordered] hashtable keeps its order; a plain one is sorted, so the output is stable.
        $keys = [string[]] @($Parameters.Keys)
        if ($Parameters -isnot [System.Collections.Specialized.IOrderedDictionary]) {
            [array]::Sort($keys, [System.StringComparer]::Ordinal)
        }
        foreach ($key in $keys) {
            $value = ConvertTo-BylawValue -Value $Parameters[$key] -Location $location
            if ($null -eq $value) {
                $valid = $false
                continue
            }
            $member.Parameters[$key] = $value
        }
    }

    $groups = @($Group | Where-Object { $null -ne $_ })
    if (@($groups | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1057' -Location $location -Message '-Group needs the names of definition groups, e.g. -Group AC-2.'
        $valid = $false
    }
    $member.GroupNames = [string[]] $groups

    if ($valid) {
        $frame.Node.Members.Add($member)
    }
}

function DefinitionGroup {
    <#
    .SYNOPSIS
        A policy definition group in an initiative, such as a regulatory compliance control.

    .EXAMPLE
        DefinitionGroup 'AC-2' -DisplayName 'Account Management' -Category 'Access Control'
    #>
    [CmdletBinding()]
    param(
        # The group's name, which PolicyDefinition -Group refers to.
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Name,

        [string] $DisplayName,
        [string] $Category,
        [string] $Description,

        # The ID of a policyMetadata object with more about the group, such as a control's details.
        [string] $AdditionalMetadataId
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'DefinitionGroup')
    $frame = Test-BylawParent -Keyword 'DefinitionGroup' -Allowed 'Initiative' -Location $location
    if ($null -eq $frame) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1057' -Location $location -Message "DefinitionGroup needs a name, e.g. DefinitionGroup 'AC-2' -DisplayName 'Account Management'."
        return
    }
    $group = [BylawDefinitionGroup]::new($Name)
    $group.Location = $location
    foreach ($property in 'DisplayName', 'Category', 'Description', 'AdditionalMetadataId') {
        if ($PSBoundParameters.ContainsKey($property)) {
            $group.$property = $PSBoundParameters[$property]
        }
    }
    $frame.Node.Groups.Add($group)
}
