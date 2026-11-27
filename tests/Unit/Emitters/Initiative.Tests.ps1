BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:InheritTag = '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54'
    $script:Scope = '/providers/Microsoft.Management/managementGroups/contoso'
    $script:SetSchema = Join-Path $PSScriptRoot '../../Schemas/epac-policy-set-definition-schema.json'

    function Format-Initiative {
        param(
            [string] $Body = @"
Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
DefinitionGroup 'Tags'
PolicyDefinition 'tags-require-mandatory-tags' -Group Tags -Parameters @{ effect = Param Effect }
PolicyDefinition -Id '$InheritTag' -ReferenceId InheritCostCenter -Version '1.*.*' -Parameters @{ tagName = 'CostCenter' }
"@,
            [string] $Properties = "DisplayName = 'Tagging baseline'; Description = 'Tags every resource.'; Category = 'Tags'; Version = '1.0.0'"
        )
        @"
Initiative 'tagging-baseline' {
    Properties @{ $Properties }
    $Body
}
"@
    }

    function Invoke-InitiativeEmit {
        # Runs the script, then the initiative's checks and emitter. Returns the emitter result.
        param([string] $Script = (Format-Initiative), [string] $Format = 'Epac', [string] $DefinitionScope)
        $frontEnd = Invoke-BylawTestScript -Script $Script
        $frontEnd.Diagnostics | Should -BeNullOrEmpty
        InModuleScope Bylaw -Parameters @{ Initiative = $frontEnd.Initiatives[0]; Format = $Format; Scope = $DefinitionScope } {
            param($Initiative, $Format, $Scope)
            @(Invoke-BylawInitiativeValidation -Initiative $Initiative | Where-Object { $_.Severity.ToString() -eq 'Error' }) | Should -BeNullOrEmpty
            Invoke-BylawInitiativeEmitter -Initiative $Initiative -Format $Format -DefinitionScope $Scope
        }
    }

    function Get-DiagnosticCode {
        param([Parameter(Mandatory)] $Result)
        @($Result.Diagnostics | ForEach-Object Code)
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'EPAC initiative output (ADR-0035)' {
    BeforeAll {
        $script:Epac = Invoke-InitiativeEmit
        $script:Document = $Epac.Document
    }

    It 'emits $schema, name and properties, in the schema''s order' {
        $Epac.Diagnostics | Should -BeNullOrEmpty
        $Document.Keys | Should -Be @('$schema', 'name', 'properties')
        $Document['$schema'] | Should -BeExactly 'https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-set-definition-schema.json'
        $Document['properties'].Keys | Should -Be @('displayName', 'policyType', 'description', 'metadata', 'parameters', 'policyDefinitions', 'policyDefinitionGroups')
        $Document['properties']['policyType'] | Should -BeExactly 'Custom'
        $Document['properties']['metadata'].Keys | Should -Be @('version', 'category')
    }

    It 'references a member from the build by policyDefinitionName, and others by policyDefinitionId' {
        $members = $Document['properties']['policyDefinitions']
        $members[0].Keys | Should -Be @('policyDefinitionReferenceId', 'policyDefinitionName', 'parameters', 'groupNames')
        $members[0]['policyDefinitionName'] | Should -BeExactly 'tags-require-mandatory-tags'
        $members[0]['parameters']['effect'].Keys | Should -Be @('value')
        $members[0]['parameters']['effect']['value'] | Should -BeExactly "[parameters('effect')]"
        , $members[0]['groupNames'] | Should -BeOfType [object[]]
        $members[1].Keys | Should -Be @('policyDefinitionReferenceId', 'policyDefinitionId', 'definitionVersion', 'parameters')
        $members[1]['policyDefinitionId'] | Should -BeExactly $InheritTag
        $members[1]['definitionVersion'] | Should -BeExactly '1.*.*'
        $members[1]['parameters']['tagName']['value'] | Should -BeExactly 'CostCenter'
    }

    It 'generates parameter display names, as for a policy' {
        $Document['properties']['parameters']['effect']['metadata']['displayName'] | Should -BeExactly 'Effect'
    }

    It 'emits only the name and additionalMetadataId of a group' {
        $script = Format-Initiative -Body "DefinitionGroup A -AdditionalMetadataId '/providers/Microsoft.PolicyInsights/policyMetadata/a'; PolicyDefinition 'p' -Group A"
        $group = (Invoke-InitiativeEmit -Script $script).Document['properties']['policyDefinitionGroups'][0]
        $group.Keys | Should -Be @('name', 'additionalMetadataId')
    }

    It 'always emits metadata and parameters, and leaves out empty member parameters and groups' {
        $document = (Invoke-InitiativeEmit -Script (Format-Initiative -Body "PolicyDefinition 'p'")).Document
        $document['properties'].Keys | Should -Be @('displayName', 'policyType', 'description', 'metadata', 'parameters', 'policyDefinitions')
        $document['properties']['parameters'].Count | Should -Be 0
        $document['properties']['policyDefinitions'][0].Keys | Should -Be @('policyDefinitionReferenceId', 'policyDefinitionName')
    }

    It 'is valid against the EPAC policy set definition schema' {
        Test-Json -Json $Epac.Text -SchemaFile $SetSchema | Should -BeTrue
    }

    It 'reports <Code> for <Case>' -ForEach @(
        @{ Code = 'BYL4001'; Case = 'no Category'; Properties = "DisplayName = 'x'; Version = '1.0.0'"; Body = "PolicyDefinition 'p'" }
        @{ Code = 'BYL4002'; Case = 'no Version'; Properties = "DisplayName = 'x'; Category = 'Tags'"; Body = "PolicyDefinition 'p'" }
        @{ Code = 'BYL4011'; Case = 'a group with a display name'; Properties = "DisplayName = 'x'; Category = 'Tags'; Version = '1.0.0'"; Body = "DefinitionGroup A -DisplayName 'A'; PolicyDefinition 'p' -Group A" }
        @{ Code = 'BYL4009'; Case = 'a DateTime parameter'; Properties = "DisplayName = 'x'; Category = 'Tags'; Version = '1.0.0'"; Body = "Parameter When -Type DateTime -Default '2026-01-01T00:00:00Z'; PolicyDefinition 'p' -Parameters @{ when = Param When }" }
    ) {
        $result = Invoke-InitiativeEmit -Script (Format-Initiative -Properties $Properties -Body $Body)
        Get-DiagnosticCode $result | Should -Contain $Code
    }

    It 'explains which group properties EPAC can''t emit' {
        $result = Invoke-InitiativeEmit -Script (Format-Initiative -Body "DefinitionGroup A -DisplayName 'A' -Category 'C'; PolicyDefinition 'p' -Group A")
        ($result.Diagnostics | Where-Object Code -EQ 'BYL4011').Message | Should -BeLike "*so -DisplayName, -Category can't be emitted for 'A'*"
        $result.Text | Should -BeNullOrEmpty
    }
}

Describe 'Plain JSON initiative output (ADR-0035)' {
    BeforeAll {
        $script:Plain = Invoke-InitiativeEmit -Format PlainJson -DefinitionScope $Scope
        $script:Document = $Plain.Document
    }

    It 'emits name and properties, with no $schema' {
        $Plain.Diagnostics | Should -BeNullOrEmpty
        $Document.Keys | Should -Be @('name', 'properties')
        $Document['properties'].Keys | Should -Be @('displayName', 'policyType', 'description', 'metadata', 'parameters', 'policyDefinitions', 'policyDefinitionGroups')
    }

    It 'gives a member from the build a full ID at the definition scope' {
        $members = $Document['properties']['policyDefinitions']
        $members[0].Keys | Should -Be @('policyDefinitionReferenceId', 'policyDefinitionId', 'parameters', 'groupNames')
        $members[0]['policyDefinitionId'] | Should -BeExactly "$Scope/providers/Microsoft.Authorization/policyDefinitions/tags-require-mandatory-tags"
        $members[1]['policyDefinitionId'] | Should -BeExactly $InheritTag
    }

    It 'emits parameters as written, with no generated display names' {
        $Document['properties']['parameters']['effect'].Keys | Should -Not -Contain 'metadata'
    }

    It 'emits every property of a group, in Learn''s order' {
        $script = Format-Initiative -Body "DefinitionGroup A -DisplayName 'Name' -Category 'Cat' -Description 'Desc' -AdditionalMetadataId '/m'; PolicyDefinition -Id '$InheritTag' -ReferenceId r -Group A"
        $group = (Invoke-InitiativeEmit -Script $script -Format PlainJson).Document['properties']['policyDefinitionGroups'][0]
        $group.Keys | Should -Be @('name', 'category', 'displayName', 'description', 'additionalMetadataId')
    }

    It 'leaves out empty metadata and parameters' {
        $document = (Invoke-InitiativeEmit -Script (Format-Initiative -Properties "DisplayName = 'x'" -Body "PolicyDefinition -Id '$InheritTag' -ReferenceId r") -Format PlainJson).Document
        $document['properties'].Keys | Should -Be @('displayName', 'policyType', 'policyDefinitions')
    }

    It 'reports BYL4012 for a member from the build without a definition scope' {
        $result = Invoke-InitiativeEmit -Format PlainJson
        ($result.Diagnostics | Where-Object Code -EQ 'BYL4012').Message | Should -BeLike "Plain JSON needs a full ID for member 'tags-require-mandatory-tags'*-DefinitionScope*"
    }

    It 'needs no definition scope when every member has an ID' {
        $result = Invoke-InitiativeEmit -Script (Format-Initiative -Body "PolicyDefinition -Id '$InheritTag' -ReferenceId r") -Format PlainJson
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'allows group display names, which EPAC refuses' {
        $result = Invoke-InitiativeEmit -Script (Format-Initiative -Body "DefinitionGroup A -DisplayName 'A'; PolicyDefinition -Id '$InheritTag' -ReferenceId r -Group A") -Format PlainJson
        $result.Diagnostics | Should -BeNullOrEmpty
    }
}
