# Initiative (policy set definition) emitters (ADR-0035), for each format in the registry.
#
# EPAC:  { $schema, name, properties: { displayName, policyType, description?, metadata, parameters,
#          policyDefinitions, policyDefinitionGroups? } }. A member from the build is referenced by
#        policyDefinitionName, and EPAC resolves it; anything else by policyDefinitionId. Groups
#        only have name and additionalMetadataId, as the EPAC schema allows.
# Plain: { name, properties }, emitted as written. Every member has a full policyDefinitionId: for
#        a member from the build, <definitionScope>/providers/Microsoft.Authorization/... .

$script:BylawEpacSetSchemaUrl = 'https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-set-definition-schema.json'

function Invoke-BylawInitiativeEmitter {
    # Runs the initiative emitter for a format. Returns the file name, document, text and
    # diagnostics; Document and Text are $null when there are errors.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [BylawInitiative] $Initiative,
        [string] $Format = 'Epac',
        # The scope the build's policies are deployed at, for plain JSON member IDs (ADR-0035).
        [string] $DefinitionScope
    )

    $emitter = Get-BylawEmitter -Format $Format
    $diagnostics = @(& $emitter.TestInitiative -Initiative $Initiative -DefinitionScope $DefinitionScope)
    $document = $null
    $text = $null
    if (@($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -eq 0) {
        $document = & $emitter.EmitInitiative -Initiative $Initiative -DefinitionScope $DefinitionScope
        $text = & $emitter.Serialize -InputObject $document
    }
    [pscustomobject]@{
        Format      = $emitter.Name
        FileName    = $Initiative.Name + $emitter.FileExtension
        Document    = $document
        Text        = $text
        Diagnostics = $diagnostics
    }
}

function Test-BylawEpacInitiative {
    # BYL4xxx: EPAC schema rules for a policy set definition (ADR-0035).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DefinitionScope', Justification = 'Part of the emitter contract; EPAC resolves member names itself.')]
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative, [string] $DefinitionScope)

    $properties = $Initiative.Properties
    $location = if ($properties) { $properties.Location } else { $Initiative.Location }
    if (-not $properties -or -not $properties.Category) {
        [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL4001', "EPAC definitions need a category: add Category to Properties, e.g. Category = 'Tags' (ADR-0023).", $location)
    }
    if (-not $properties -or -not $properties.Version) {
        [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL4002', "EPAC definitions need a version: add Version to Properties, e.g. Version = '1.0.0' (ADR-0023).", $location)
    }
    foreach ($parameter in $Initiative.Parameters) {
        if ($parameter.Type -eq 'DateTime') {
            [BylawDiagnostic]::new([BylawSeverity]::Warning, 'BYL4009', "Parameter '$($parameter.Name)' is a DateTime. Azure accepts it, but the EPAC schema doesn't list the type, so editors will flag the file.", $parameter.Location)
        }
    }
    foreach ($group in $Initiative.Groups) {
        $extra = @('DisplayName', 'Category', 'Description' | Where-Object { $group.$_ })
        if ($extra.Count -gt 0) {
            [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL4011', "The EPAC schema only allows a name and -AdditionalMetadataId on a definition group, so -$($extra -join ', -') can't be emitted for '$($group.Name)'. Remove it, or build with -Format PlainJson (ADR-0035).", $group.Location)
        }
    }
}

function Test-BylawPlainJsonInitiative {
    # A member from the build needs the scope its policy is deployed at (ADR-0035).
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative, [string] $DefinitionScope)

    if ($DefinitionScope) {
        return
    }
    $member = $Initiative.Members | Where-Object PolicyName | Select-Object -First 1
    if ($member) {
        [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL4012', "Plain JSON needs a full ID for member '$($member.ReferenceId)', which is a policy in this build. Set the scope the build's policies are deployed at: Build-Bylaw -DefinitionScope '/providers/Microsoft.Management/managementGroups/<id>', or definitionScope in bylaw.json (ADR-0035).", $member.Location)
    }
}

function ConvertTo-BylawEpacInitiativeDocument {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DefinitionScope', Justification = 'Part of the emitter contract; EPAC resolves member names itself.')]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative, [string] $DefinitionScope)

    $properties = [ordered]@{
        displayName = $Initiative.Properties.DisplayName
        policyType  = 'Custom'
    }
    if ($Initiative.Properties.Description) {
        $properties['description'] = $Initiative.Properties.Description
    }
    $properties['metadata'] = ConvertTo-BylawMetadataObject -Properties $Initiative.Properties
    $parameters = [ordered]@{}
    foreach ($parameter in $Initiative.Parameters) {
        $parameters[(Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName)] = ConvertTo-BylawEpacParameterObject -Parameter $parameter -IsEffect $false
    }
    $properties['parameters'] = $parameters
    $properties['policyDefinitions'] = [object[]] @(foreach ($member in $Initiative.Members) {
            ConvertTo-BylawInitiativeMemberObject -Member $member -Initiative $Initiative -ByName
        })
    if ($Initiative.Groups.Count -gt 0) {
        $properties['policyDefinitionGroups'] = [object[]] @(foreach ($group in $Initiative.Groups) {
                $object = [ordered]@{ name = $group.Name }
                if ($group.AdditionalMetadataId) {
                    $object['additionalMetadataId'] = $group.AdditionalMetadataId
                }
                $object
            })
    }

    [ordered]@{
        '$schema'  = $script:BylawEpacSetSchemaUrl
        name       = $Initiative.Name
        properties = $properties
    }
}

function ConvertTo-BylawPlainJsonInitiativeDocument {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative, [string] $DefinitionScope)

    $properties = [ordered]@{
        displayName = $Initiative.Properties.DisplayName
        policyType  = 'Custom'
    }
    if ($Initiative.Properties.Description) {
        $properties['description'] = $Initiative.Properties.Description
    }
    $metadata = ConvertTo-BylawMetadataObject -Properties $Initiative.Properties
    if ($metadata.Count -gt 0) {
        $properties['metadata'] = $metadata
    }
    if ($Initiative.Parameters.Count -gt 0) {
        $parameters = [ordered]@{}
        foreach ($parameter in $Initiative.Parameters) {
            $displayName = Get-BylawParameterMetadataText -Parameter $parameter -Key displayName
            $description = Get-BylawParameterMetadataText -Parameter $parameter -Key description
            $parameters[(Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName)] = ConvertTo-BylawParameterObject -Parameter $parameter -DisplayName $displayName -Description $description
        }
        $properties['parameters'] = $parameters
    }
    $properties['policyDefinitions'] = [object[]] @(foreach ($member in $Initiative.Members) {
            ConvertTo-BylawInitiativeMemberObject -Member $member -Initiative $Initiative -DefinitionScope $DefinitionScope
        })
    if ($Initiative.Groups.Count -gt 0) {
        # In the order Learn lists a group's properties.
        $properties['policyDefinitionGroups'] = [object[]] @(foreach ($group in $Initiative.Groups) {
                $object = [ordered]@{ name = $group.Name }
                foreach ($property in 'Category', 'DisplayName', 'Description', 'AdditionalMetadataId') {
                    if ($group.$property) {
                        $object[$property.Substring(0, 1).ToLowerInvariant() + $property.Substring(1)] = $group.$property
                    }
                }
                $object
            })
    }

    [ordered]@{
        name       = $Initiative.Name
        properties = $properties
    }
}

function ConvertTo-BylawInitiativeMemberObject {
    # One entry of policyDefinitions: policyDefinitionReferenceId, policyDefinitionName or
    # policyDefinitionId, definitionVersion?, parameters?, groupNames? (ADR-0035). With -ByName, a
    # member from the build is referenced by name, as EPAC needs.
    param(
        [Parameter(Mandatory)] [BylawInitiativeMember] $Member,
        [Parameter(Mandatory)] [BylawInitiative] $Initiative,
        [switch] $ByName,
        [string] $DefinitionScope
    )

    $object = [ordered]@{ policyDefinitionReferenceId = $Member.ReferenceId }
    if ($Member.DefinitionId) {
        $object['policyDefinitionId'] = $Member.DefinitionId
    }
    elseif ($ByName) {
        $object['policyDefinitionName'] = $Member.PolicyName
    }
    else {
        $object['policyDefinitionId'] = "$($DefinitionScope.TrimEnd('/'))/providers/Microsoft.Authorization/policyDefinitions/$($Member.PolicyName)"
    }
    if ($Member.Version) {
        $object['definitionVersion'] = $Member.Version
    }
    if ($Member.Parameters.Count -gt 0) {
        $parameters = [ordered]@{}
        foreach ($entry in $Member.Parameters.GetEnumerator()) {
            $parameters[$entry.Key] = [ordered]@{ value = ConvertTo-BylawValueObject -Value $entry.Value -Policy $Initiative }
        }
        $object['parameters'] = $parameters
    }
    if ($Member.GroupNames.Count -gt 0) {
        $object['groupNames'] = [object[]] @($Member.GroupNames)
    }
    $object
}
