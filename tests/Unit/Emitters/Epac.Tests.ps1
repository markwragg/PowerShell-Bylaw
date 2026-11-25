BeforeDiscovery {
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
    $script:EpacProperties = "DisplayName = 'Test policy'; Category = 'Storage'; Version = '1.0.0'"
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
    $script:SchemaPath = Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json'
    $script:EpacProperties = "DisplayName = 'Test policy'; Category = 'Storage'; Version = '1.0.0'"

    function script:Invoke-EpacTest {
        # Compiles a test policy with EPAC-ready Properties and returns the emitter result.
        param([hashtable] $Policy = @{})
        if (-not $Policy.ContainsKey('Properties')) {
            $Policy['Properties'] = $script:EpacProperties
        }
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy @Policy)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $result.Emitted
    }

    function script:Test-EpacSchema([string] $Json) {
        Test-Json -Json $Json -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'EPAC document' {
    It 'compiles the spec storage example to a schema-valid file' {
        $script = @'
Policy 'storage-deny-public-network-access' {
    Properties @{
        DisplayName = 'Storage accounts should disable public network access'
        Description = 'Denies storage accounts that allow public network access or allow-all IP rules.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'All'
    }
    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny
    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Field kind | Must -BeIn 'StorageV2', 'BlockBlobStorage'
        }
        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }
        Require 'No allow-all IP rules' {
            Each networkAcls.ipRules[*] {
                Field value | Must -Not -Be '0.0.0.0/0'
            }
        }
    }
    Effect (Param Effect)
}
'@
        $result = Invoke-BylawTestCompile -Script $script
        $result.Diagnostics | Should -BeNullOrEmpty
        $emitted = $result.Emitted
        $emitted.Diagnostics | Should -BeNullOrEmpty
        $emitted.FileName | Should -Be 'storage-deny-public-network-access.json'
        Test-EpacSchema $emitted.Text | Should -BeTrue

        $document = $emitted.Document
        $document['$schema'] | Should -Be 'https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json'
        $document['name'] | Should -Be 'storage-deny-public-network-access'
        $properties = $document['properties']
        $properties['metadata'] | ConvertTo-Json -Compress | Should -Be '{"version":"1.0.0","category":"Storage"}'
        $properties['policyRule']['then']['effect'] | Should -Be "[parameters('effect')]"
        $properties['parameters']['effect']['metadata']['displayName'] | Should -Be 'Effect'
    }

    It 'orders the top-level keys $schema, name, properties' {
        @((Invoke-EpacTest).Document.Keys) | Should -Be @('$schema', 'name', 'properties')
    }

    It 'orders properties as in ADR-0009' {
        $properties = "$script:EpacProperties; Description = 'd'"
        @((Invoke-EpacTest @{ Properties = $properties }).Document['properties'].Keys) |
            Should -Be @('displayName', 'policyType', 'mode', 'description', 'metadata', 'parameters', 'policyRule')
    }

    It 'omits description when it is not set' {
        (Invoke-EpacTest).Document['properties'].Contains('description') | Should -BeFalse
    }

    It 'emits mode <Expected> for <Mode>' -ForEach @(
        @{ Mode = $null; Expected = 'All' }
        @{ Mode = 'all'; Expected = 'All' }
        @{ Mode = 'indexed'; Expected = 'Indexed' }
    ) {
        $properties = if ($Mode) { "$script:EpacProperties; Mode = '$Mode'" } else { $script:EpacProperties }
        (Invoke-EpacTest @{ Properties = $properties }).Document['properties']['mode'] | Should -Be $Expected
    }

    It 'orders metadata version, category, preview, deprecated, then sorted user keys' {
        $properties = "$script:EpacProperties; Deprecated = `$false; Preview = `$true; Metadata = @{ zeta = 1; Alpha = 2; beta = 3 }"
        @((Invoke-EpacTest @{ Properties = $properties }).Document['properties']['metadata'].Keys) |
            Should -Be @('version', 'category', 'preview', 'deprecated', 'Alpha', 'beta', 'zeta')
    }

    It 'keeps the order of ordered user metadata' {
        $properties = "$script:EpacProperties; Metadata = [ordered]@{ zeta = 1; alpha = 2 }"
        @((Invoke-EpacTest @{ Properties = $properties }).Document['properties']['metadata'].Keys) |
            Should -Be @('version', 'category', 'zeta', 'alpha')
    }

    It 'writes LF line endings and one trailing newline, the same every time' {
        $first = (Invoke-EpacTest).Text
        $second = (Invoke-EpacTest).Text
        $first | Should -BeExactly $second
        $first.Contains("`r") | Should -BeFalse
        $first.EndsWith("}`n") | Should -BeTrue
        $first.EndsWith("`n`n") | Should -BeFalse
    }
}

Describe 'EPAC effect' {
    It 'turns a literal effect into an effect parameter with the literal as default' {
        $document = (Invoke-EpacTest @{ Effect = 'deny' }).Document
        $document['properties']['policyRule']['then']['effect'] | Should -Be "[parameters('effect')]"
        $effect = $document['properties']['parameters']['effect']
        @($effect.Keys) | Should -Be @('type', 'metadata', 'allowedValues', 'defaultValue')
        $effect['type'] | Should -Be 'String'
        $effect['metadata']['displayName'] | Should -Be 'Effect'
        $effect['metadata']['description'] | Should -Be 'Enable or disable the execution of the policy'
        $effect['allowedValues'] | Should -Be @('Audit', 'Deny', 'Disabled')
        $effect['defaultValue'] | Should -BeExactly 'Deny'
    }

    It 'adds the generated effect parameter after the declared parameters' {
        $policy = @{
            Requirements = "Require 'r' { Field publicNetworkAccess | Must -Be (Param Access) }"
            Extra        = 'Parameter Access -Default Disabled'
            Effect       = 'Audit'
        }
        $parameters = (Invoke-EpacTest $policy).Document['properties']['parameters']
        @($parameters.Keys) | Should -Be @('access', 'effect')
        $parameters['effect']['defaultValue'] | Should -Be 'Audit'
    }

    It 'sets the display name and default description of a declared effect parameter' {
        $policy = @{ Extra = 'Parameter Effect -AllowedValues Audit, Disabled -Default Audit'; Effect = '(Param Effect)' }
        $effect = (Invoke-EpacTest $policy).Document['properties']['parameters']['effect']
        $effect['metadata']['displayName'] | Should -Be 'Effect'
        $effect['metadata']['description'] | Should -Be 'Enable or disable the execution of the policy'
        $effect['allowedValues'] | Should -Be @('Audit', 'Disabled')
    }

    It 'keeps the description of a declared effect parameter' {
        $policy = @{ Extra = "Parameter Effect -AllowedValues Audit, Deny -Default Audit -Description 'Audit or deny.'"; Effect = '(Param Effect)' }
        (Invoke-EpacTest $policy).Document['properties']['parameters']['effect']['metadata']['description'] | Should -Be 'Audit or deny.'
    }

    It 'accepts DisplayName Effect on the effect parameter' {
        $policy = @{ Extra = "Parameter Effect -AllowedValues Audit, Deny -Default Audit -DisplayName 'Effect'"; Effect = '(Param Effect)' }
        (Invoke-EpacTest $policy).Diagnostics | Should -BeNullOrEmpty
    }
}

Describe 'EPAC parameters' {
    BeforeAll {
        function script:Get-EpacParameter([string] $Declaration, [string] $Requirement = 'Field publicNetworkAccess | Must -Be (Param P)') {
            $policy = @{ Requirements = "Require 'r' { $Requirement }"; Extra = $Declaration }
            (Invoke-EpacTest $policy).Document['properties']['parameters']
        }
    }

    It 'generates a display name from the parameter name' {
        $parameters = Get-EpacParameter -Declaration 'Parameter AllowedLocations -Default @(''uksouth'')' -Requirement 'Field location | Must -BeIn (Param AllowedLocations)'
        $parameters['allowedLocations']['metadata']['displayName'] | Should -Be 'Allowed locations'
    }

    It 'keeps an explicit display name' {
        (Get-EpacParameter -Declaration "Parameter P -Default x -DisplayName 'Public access'")['p']['metadata']['displayName'] | Should -Be 'Public access'
    }

    It 'orders type, metadata, allowedValues, defaultValue' {
        @((Get-EpacParameter -Declaration 'Parameter P -AllowedValues Enabled, Disabled -Default Disabled')['p'].Keys) |
            Should -Be @('type', 'metadata', 'allowedValues', 'defaultValue')
    }

    It 'omits defaultValue when there is no default' {
        @((Get-EpacParameter -Declaration 'Parameter P -Type String')['p'].Keys) | Should -Be @('type', 'metadata')
    }

    It 'emits a null default' {
        $parameter = (Get-EpacParameter -Declaration 'Parameter P -Type String -Default $null')['p']
        $parameter.Contains('defaultValue') | Should -BeTrue
        $parameter['defaultValue'] | Should -BeNullOrEmpty
    }

    It 'takes displayName and description from the hashtable Metadata, then the other keys in order' {
        $declaration = "Parameter @{ Name = 'P'; Type = 'String'; Metadata = @{ strongType = 'location'; description = 'From metadata'; displayName = 'Place'; assignPermissions = `$true } }"
        $metadata = (Get-EpacParameter -Declaration $declaration)['p']['metadata']
        @($metadata.Keys) | Should -Be @('displayName', 'description', 'assignPermissions', 'strongType')
        $metadata['displayName'] | Should -Be 'Place'
        $metadata['description'] | Should -Be 'From metadata'
    }

    It 'uses JsonName for the parameter key and reference' {
        $document = (Invoke-EpacTest @{ Requirements = "Require 'r' { Field publicNetworkAccess | Must -Be (Param Access) }"; Extra = "Parameter @{ Name = 'Access'; Default = 'Disabled'; JsonName = 'publicAccess' }" }).Document
        $document['properties']['parameters'].Contains('publicAccess') | Should -BeTrue
        $document['properties']['policyRule']['if']['allOf'][1]['notEquals'] | Should -Be "[parameters('publicAccess')]"
    }

    It 'writes a DateTime default as an ISO 8601 string' {
        $parameters = Get-EpacParameter -Declaration "Parameter P -Type DateTime -Default ([datetime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc))" -Requirement 'Field publicNetworkAccess | Must -BeLessThan (Param P)'
        $parameters['p']['defaultValue'] | Should -BeExactly '2026-01-02T03:04:05.0000000Z'
    }
}

Describe 'EPAC schema validation' {
    It 'passes the pinned EPAC schema for <Case>' -ForEach @(
        @{ Case = 'a literal effect'; Policy = @{} }
        @{ Case = 'a parameterised effect'; Policy = @{ Extra = 'Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit'; Effect = '(Param Effect)' } }
        @{ Case = 'array, object, boolean, integer and float parameters'; Policy = @{
                Requirements = "Require 'r' { Field location | Must -BeIn (Param Locations); Field publicNetworkAccess | Must -BeLessThan (Param Count) }"
                Extra        = "Parameter Locations -Default @('uksouth'); Parameter Tags -Default @{ env = 'x' }; Parameter Flag -Default `$true; Parameter Count -Default 5; Parameter Ratio -Default 0.5"
            }
        }
        @{ Case = 'all metadata keys'; Policy = @{ Properties = "$script:EpacProperties; Description = 'd'; Mode = 'Indexed'; Preview = `$true; Deprecated = `$false; Metadata = @{ source = 'x' }" } }
        @{ Case = 'Resource *'; Policy = @{ Type = '*'; Requirements = "Require 'r' { Field location | Must -Be 'uksouth' }" } }
    ) {
        $emitted = Invoke-EpacTest -Policy $Policy
        Test-EpacSchema $emitted.Text | Should -BeTrue
    }

    It 'fails the pinned schema when a required key is removed (the check is real)' {
        $document = (Invoke-EpacTest).Document
        $document['properties']['metadata'].Remove('category')
        $json = InModuleScope Bylaw -Parameters @{ Document = $document } { param($Document) ConvertTo-BylawJson -InputObject $Document }
        Test-EpacSchema $json | Should -BeFalse
    }
}

Describe 'EPAC diagnostics' {
    It 'reports <Code> for <Case>' -ForEach @(
        @{ Code = 'BYL4001'; Case = 'no Category'; Properties = "DisplayName = 'x'; Version = '1.0.0'"; Policy = @{} }
        @{ Code = 'BYL4002'; Case = 'no Version'; Properties = "DisplayName = 'x'; Category = 'Storage'"; Policy = @{} }
        @{ Code = 'BYL4003'; Case = 'an effect parameter not named effect'; Properties = $EpacProperties; Policy = @{ Extra = 'Parameter Mode -AllowedValues Audit, Deny -Default Audit'; Effect = '(Param Mode)' } }
        @{ Code = 'BYL4004'; Case = 'an effect parameter with no default'; Properties = $EpacProperties; Policy = @{ Extra = 'Parameter Effect -AllowedValues Audit, Deny'; Effect = '(Param Effect)' } }
        @{ Code = 'BYL4005'; Case = 'an effect parameter with one allowed value'; Properties = $EpacProperties; Policy = @{ Extra = 'Parameter Effect -AllowedValues Audit -Default Audit'; Effect = '(Param Effect)' } }
        @{ Code = 'BYL4005'; Case = 'an effect parameter with duplicate allowed values'; Properties = $EpacProperties; Policy = @{ Extra = 'Parameter Effect -AllowedValues Audit, audit -Default Audit'; Effect = '(Param Effect)' } }
        @{ Code = 'BYL4006'; Case = 'an effect parameter with another display name'; Properties = $EpacProperties; Policy = @{ Extra = "Parameter Effect -AllowedValues Audit, Deny -Default Audit -DisplayName 'Policy effect'"; Effect = '(Param Effect)' } }
        @{ Code = 'BYL4007'; Case = 'a literal effect with an effect parameter declared'; Properties = $EpacProperties; Policy = @{ Extra = 'Parameter Effect -AllowedValues Audit, Deny -Default Audit' } }
        @{ Code = 'BYL4008'; Case = 'an Arm effect'; Properties = $EpacProperties; Policy = @{ Effect = "(Arm `"[if(true(), 'Deny', 'Audit')]`")" } }
    ) {
        $Policy['Properties'] = $Properties
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy @Policy)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $errors = @($result.Emitted.Diagnostics | Where-Object { $_.Severity.ToString() -eq 'Error' } | ForEach-Object Code)
        $errors | Should -Contain $Code
        $result.Emitted.Document | Should -BeNullOrEmpty
        $result.Emitted.Text | Should -BeNullOrEmpty
    }

    It 'warns but emits for a DateTime parameter (BYL4009)' {
        $policy = @{
            Properties   = $script:EpacProperties
            Requirements = "Require 'r' { Field publicNetworkAccess | Must -BeLessThan (Param Cutoff) }"
            Extra        = "Parameter Cutoff -Type DateTime -Default '2026-01-01T00:00:00Z'"
        }
        $emitted = (Invoke-BylawTestCompile -Script (Format-BylawTestPolicy @policy)).Emitted
        @($emitted.Diagnostics.Code) | Should -Be @('BYL4009')
        $emitted.Text | Should -Not -BeNullOrEmpty
    }
}

Describe 'Emitter registry' {
    It 'finds a format ignoring case' {
        InModuleScope Bylaw { (Get-BylawEmitter -Format 'epac').Name } | Should -Be 'Epac'
    }

    It 'rejects an unknown format and lists the valid ones' {
        { InModuleScope Bylaw { Get-BylawEmitter -Format 'Bicep' } } | Should -Throw "*Unknown output format 'Bicep'*Valid formats: Epac*"
    }

    It 'refuses a policy that has not been compiled' {
        { InModuleScope Bylaw { ConvertTo-BylawEpacDocument -Policy ([BylawPolicy]::new('not-compiled')) } } | Should -Throw '*has not been compiled*'
    }
}

Describe 'Get-BylawGeneratedDisplayName' {
    It "turns '<Name>' into '<Expected>'" -ForEach @(
        @{ Name = 'Effect'; Expected = 'Effect' }
        @{ Name = 'AllowedLocations'; Expected = 'Allowed locations' }
        @{ Name = 'allowedLocations'; Expected = 'Allowed locations' }
        @{ Name = 'TLSVersion'; Expected = 'TLS version' }
        @{ Name = 'MinimumTLSVersion'; Expected = 'Minimum TLS version' }
        @{ Name = 'max_count'; Expected = 'Max count' }
        @{ Name = 'Sku2Name'; Expected = 'Sku2 name' }
    ) {
        InModuleScope Bylaw -Parameters @{ Name = $Name } { param($Name) Get-BylawGeneratedDisplayName -Name $Name } | Should -BeExactly $Expected
    }
}
