BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Invoke-PlainJsonCompile {
        # Compiles a script and emits its policy as plain JSON and as EPAC. Returns both texts,
        # the plain JSON document and the plain JSON diagnostics.
        param([Parameter(Mandatory)] [string] $Script)
        $result = Invoke-BylawTestCompile -Script $Script
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $plain = InModuleScope Bylaw -Parameters @{ Policy = $result.Policy } {
            param($Policy)
            Invoke-BylawEmitter -Policy $Policy -Format PlainJson
        }
        [pscustomobject]@{
            Plain       = $plain.Text
            Epac        = $result.Emitted.Text
            Document    = $plain.Text | ConvertFrom-Json -AsHashtable
            FileName    = $plain.FileName
            Diagnostics = $plain.Diagnostics
        }
    }

    function Get-TopLevelKey {
        param([Parameter(Mandatory)] [string] $Json)
        $parsed = [System.Text.Json.JsonDocument]::Parse($Json)
        try {
            @($parsed.RootElement.EnumerateObject() | ForEach-Object Name)
        }
        finally {
            $parsed.Dispose()
        }
    }

    function Get-PolicyRuleJson {
        # The policyRule of an emitted definition, as compact JSON.
        param([Parameter(Mandatory)] [string] $Json)
        ($Json | ConvertFrom-Json -AsHashtable)['properties']['policyRule'] | ConvertTo-Json -Depth 50 -Compress
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Plain JSON emitter (ADR-0027)' {
    It 'is found in the emitter registry, ignoring case' {
        InModuleScope Bylaw { (Get-BylawEmitter -Format 'plainjson').Name } | Should -Be 'PlainJson'
    }

    It 'writes { name, properties } with no $schema, named after the policy' {
        $result = Invoke-PlainJsonCompile -Script (Format-BylawTestPolicy)
        Get-TopLevelKey -Json $result.Plain | Should -Be @('name', 'properties')
        $result.Document['name'] | Should -Be 'test-policy'
        $result.FileName | Should -Be 'test-policy.json'
        $result.Plain.Contains('$schema') | Should -BeFalse
    }

    It 'keeps a literal effect literal, with no generated parameter' {
        $result = Invoke-PlainJsonCompile -Script (Format-BylawTestPolicy)
        $result.Document['properties']['policyRule']['then']['effect'] | Should -Be 'Deny'
        $result.Document['properties'].Contains('parameters') | Should -BeFalse
    }

    It 'omits empty description and metadata, and needs no Category or Version' {
        $result = Invoke-PlainJsonCompile -Script (Format-BylawTestPolicy)
        $result.Diagnostics | Should -BeNullOrEmpty
        $properties = $result.Document['properties']
        $properties.Contains('description') | Should -BeFalse
        $properties.Contains('metadata') | Should -BeFalse
        $properties['policyType'] | Should -Be 'Custom'
        $properties['mode'] | Should -Be 'All'
    }

    It 'orders properties as EPAC does' {
        $script = Format-BylawTestPolicy -Properties "DisplayName = 'Test policy'; Description = 'd'; Category = 'Storage'; Version = '1.0.0'" -Extra 'Parameter Effect -AllowedValues Audit, Deny -Default Audit' -Effect '(Param Effect)'
        $result = Invoke-PlainJsonCompile -Script $script
        $parsed = [System.Text.Json.JsonDocument]::Parse($result.Plain)
        try {
            $keys = @($parsed.RootElement.GetProperty('properties').EnumerateObject() | ForEach-Object Name)
        }
        finally {
            $parsed.Dispose()
        }
        $keys | Should -Be @('displayName', 'policyType', 'mode', 'description', 'metadata', 'parameters', 'policyRule')
    }

    It 'emits only the parameter display names that were written' {
        $extra = "Parameter AllowedValues -Type Array -Default @('Disabled'); Parameter @{ Name = 'Named'; Type = 'String'; DisplayName = 'A name'; Default = 'x' }"
        $requirements = "Require 'r' { Field publicNetworkAccess | Must -BeIn (Param AllowedValues); Field name | Must -Not -Be (Param Named) }"
        $result = Invoke-PlainJsonCompile -Script (Format-BylawTestPolicy -Extra $extra -Requirements $requirements)
        $parameters = $result.Document['properties']['parameters']
        $parameters['allowedValues'].Contains('metadata') | Should -BeFalse
        $parameters['named']['metadata']['displayName'] | Should -Be 'A name'
    }

    It 'gives an effect parameter no generated display name or description' {
        $script = Format-BylawTestPolicy -Extra 'Parameter Effect -AllowedValues Audit, Deny -Default Audit' -Effect '(Param Effect)'
        $effect = (Invoke-PlainJsonCompile -Script $script).Document['properties']['parameters']['effect']
        $effect.Contains('metadata') | Should -BeFalse
    }

    It 'emits the same policyRule as EPAC when the effect is a parameter, for <Case>' -ForEach @(
        # The Effect script is built in the test: the helpers aren't loaded during discovery.
        @{ Case = 'Effect'; Script = '' }
        @{
            Case   = 'Modify'
            Script = @'
Policy 'test-policy' {
    Properties @{ DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Tags'; Version = '1.0.0' }
    Parameter Effect -AllowedValues Modify, Disabled -Default Modify
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' { Tag Environment | Must -Be 'Production' }
    }
    Modify -Role 'Tag Contributor' -Effect (Param Effect) { Tag Environment | AddOrReplace 'Production' }
}
'@
        }
    ) {
        if (-not $Script) {
            # EPAC needs Category and Version.
            $Script = Format-BylawTestPolicy -Properties "DisplayName = 'Test policy'; Category = 'Storage'; Version = '1.0.0'" -Extra 'Parameter Effect -AllowedValues Audit, Deny -Default Audit' -Effect '(Param Effect)'
        }
        $result = Invoke-PlainJsonCompile -Script $Script
        $result.Epac | Should -Not -BeNullOrEmpty -Because 'the policy should also be valid for EPAC'
        Get-PolicyRuleJson -Json $result.Plain | Should -BeExactly (Get-PolicyRuleJson -Json $result.Epac)
    }

    It 'keeps the Modify effect literal, with its details block' {
        $script = @'
Policy 'test-policy' {
    Properties @{ DisplayName = 'Test policy'; Mode = 'Indexed' }
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' { Tag Environment | Must -Be 'Production' }
    }
    Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }
}
'@
        $then = (Invoke-PlainJsonCompile -Script $script).Document['properties']['policyRule']['then']
        $then['effect'] | Should -Be 'Modify'
        @($then['details']['operations']).Count | Should -Be 1
    }

    It 'accepts an Arm effect, which EPAC refuses' {
        $result = Invoke-PlainJsonCompile -Script (Format-BylawTestPolicy -Effect "(Arm `"[if(true(), 'Deny', 'Audit')]`")")
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Document['properties']['policyRule']['then']['effect'] | Should -Be "[if(true(), 'Deny', 'Audit')]"
    }
}

Describe 'Build-Bylaw -Format PlainJson' {
    It 'writes plain JSON files, and still applies language validation' {
        $source = Join-Path $TestDrive 'plain-src'
        $null = New-Item -ItemType Directory -Force -Path $source
        Set-Content -LiteralPath (Join-Path $source 'p.bylaw.ps1') -Value (Format-BylawTestPolicy) -Encoding utf8NoBOM
        $out = Join-Path $TestDrive 'plain-out'
        $result = Build-Bylaw -Path $source -OutputPath $out -Format PlainJson -PassThru
        $result.Name | Should -Be 'test-policy'
        Get-TopLevelKey -Json ([System.IO.File]::ReadAllText((Join-Path $out 'test-policy.json'))) | Should -Be @('name', 'properties')

        Set-Content -LiteralPath (Join-Path $source 'p.bylaw.ps1') -Value ((Format-BylawTestPolicy).Replace("Policy 'test-policy'", "Policy 'Bad:Name'")) -Encoding utf8NoBOM
        { Build-Bylaw -Path $source -Format PlainJson -PassThru -ErrorAction Stop } | Should -Throw '*BYL3001*'
    }
}
