BeforeDiscovery {
    # The -ForEach test data below is built with Format-BylawTestPolicy during discovery.
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Validation pass' {
    It 'accepts a valid policy without diagnostics' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy)
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policy.Rule | Should -Not -BeNullOrEmpty
    }

    It 'reports <Code> for <Case>' -ForEach @(
        @{ Code = 'BYL3001'; Case = 'an invalid name'; Script = (Format-BylawTestPolicy).Replace("Policy 'test-policy'", "Policy 'Test_Policy'") }
        @{ Code = 'BYL3001'; Case = 'a name over 64 characters'; Script = (Format-BylawTestPolicy).Replace("Policy 'test-policy'", "Policy '$('a' * 65)'") }
        @{ Code = 'BYL3002'; Case = 'no Properties'; Script = (Format-BylawTestPolicy).Replace("Properties @{ DisplayName = 'Test policy' }", '') }
        @{ Code = 'BYL3002'; Case = 'a DisplayName over 128 characters'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = '$('d' * 129)'") }
        @{ Code = 'BYL3003'; Case = 'a Description over 512 characters'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Description = '$('d' * 513)'") }
        @{ Code = 'BYL3004'; Case = 'a resource provider mode'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Mode = 'Microsoft.Kubernetes.Data'") }
        @{ Code = 'BYL3005'; Case = 'a version that is not SemVer'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Version = '1.0'") }
        @{ Code = 'BYL3006'; Case = 'a generated metadata key'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Metadata = @{ category = 'x' }") }
        @{ Code = 'BYL3006'; Case = 'metadata deployedBy'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Metadata = @{ deployedBy = 'me' }") }
        @{ Code = 'BYL3007'; Case = 'a metadata value over 1024 characters'; Script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Metadata = @{ notes = '$('n' * 1030)' }") }
        @{ Code = 'BYL3010'; Case = '-Be with an array'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -Be @('a', 'b') }") }
        @{ Code = 'BYL3011'; Case = '-BeLike with two wildcards'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -BeLike '*a*' }") }
        @{ Code = 'BYL3012'; Case = '-ContainText with a wildcard'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -ContainText 'a*' }") }
        @{ Code = 'BYL3014'; Case = '-BeLike with a number'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -BeLike 5 }") }
        @{ Code = 'BYL3016'; Case = '-BeGreaterThan with a boolean'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -BeGreaterThan `$true }") }
        @{ Code = 'BYL3020'; Case = 'an undeclared parameter'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeIn (Param Locations) }") }
        @{ Code = 'BYL3020'; Case = 'an undeclared effect parameter'; Script = (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect (Param Effect)') }
        @{ Code = 'BYL3021'; Case = 'a default outside the allowed values'; Script = (Format-BylawTestPolicy -Extra 'Parameter Tier -AllowedValues Hot, Cool -Default Archive') }
        @{ Code = 'BYL3022'; Case = 'two parameters with the same JSON name'; Script = (Format-BylawTestPolicy -Extra "Parameter Sku -Default x; Parameter @{ Name = 'Other'; Default = 'y'; JsonName = 'sku' }") }
        @{ Code = 'BYL3021'; Case = 'an array default element outside the allowed values'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeIn (Param Locations) }" -Extra "Parameter Locations -Type Array -AllowedValues uksouth, ukwest -Default @('uksouth', 'eastus')") }
        @{ Code = 'BYL3023'; Case = 'an Array parameter with -Be'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -Be (Param Locations) }" -Extra "Parameter Locations -Default @('uksouth')") }
        @{ Code = 'BYL3023'; Case = 'an Array parameter with -BeLike'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeLike (Param Locations) }" -Extra "Parameter Locations -Default @('uk*')") }
        @{ Code = 'BYL3024'; Case = 'a String parameter with -BeIn'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeIn (Param Location) }" -Extra 'Parameter Location -Default uksouth') }
        @{ Code = 'BYL3025'; Case = 'a Boolean parameter with -Match'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -Match (Param Flag) }" -Extra 'Parameter Flag -Default $true') }
        @{ Code = 'BYL3025'; Case = 'an Object parameter with -ContainText'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -ContainText (Param Thing) }" -Extra 'Parameter Thing -Default @{ a = 1 }') }
        @{ Code = 'BYL3026'; Case = 'a Boolean parameter with -BeGreaterThan'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeGreaterThan (Param Flag) }" -Extra 'Parameter Flag -Default $true') }
        @{ Code = 'BYL3027'; Case = 'a default that does not match the type'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -Be (Param Location) }" -Extra 'Parameter Location -Type String -Default 5') }
        @{ Code = 'BYL3027'; Case = 'a DateTime default that is not a date'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeLessThan (Param Cutoff) }" -Extra 'Parameter Cutoff -Type DateTime -Default soon') }
        @{ Code = 'BYL3028'; Case = 'allowed values that do not match the type'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field location | Must -BeGreaterThan (Param Size) }" -Extra 'Parameter Size -Type Integer -AllowedValues 1, two -Default 1') }
        @{ Code = 'BYL3030'; Case = 'an unsupported literal effect'; Script = (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect Modify') }
        @{ Code = 'BYL3031'; Case = 'an effect parameter that is not a string'; Script = (Format-BylawTestPolicy -Extra 'Parameter Effect -Type Array -AllowedValues Audit').Replace('Effect Deny', 'Effect (Param Effect)') }
        @{ Code = 'BYL3032'; Case = 'an effect parameter without allowed values'; Script = (Format-BylawTestPolicy -Extra 'Parameter Effect -Default Deny').Replace('Effect Deny', 'Effect (Param Effect)') }
        @{ Code = 'BYL3033'; Case = 'an unsupported allowed effect'; Script = (Format-BylawTestPolicy -Extra 'Parameter Effect -AllowedValues Audit, Append -Default Audit').Replace('Effect Deny', 'Effect (Param Effect)') }
        @{ Code = 'BYL3042'; Case = 'Resource * with no conditions'; Script = "Policy 'nothing' { Properties @{ DisplayName = 'x' }; Resource * { }; Effect Audit }" }
    ) {
        $result = Invoke-BylawTestCompile -Script $Script
        $result.Errors | Should -Contain $Code -Because ($result.Diagnostics -join '; ')
        $result.Policy.Rule | Should -BeNullOrEmpty -Because 'a policy with errors is not compiled'
    }

    It 'warns but compiles for <Code> (<Case>)' -ForEach @(
        @{ Code = 'BYL3013'; Case = 'a regex-looking -Match pattern'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAccess | Must -Match '^Dis.*$' }") }
        @{ Code = 'BYL3040'; Case = 'Mode All with a tag check'; Script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field `"tags['env']`" | Must -Exist }") }
        @{ Code = 'BYL3029'; Case = 'a parameter that is never used'; Script = (Format-BylawTestPolicy -Extra 'Parameter Unused -Default x') }
        @{ Code = 'BYL3041'; Case = 'no Require block'; Script = (Format-BylawTestPolicy -Requirements "When { Field kind | Must -Be 'Storage' }") }
    ) {
        $result = Invoke-BylawTestCompile -Script $Script
        $result.Codes | Should -Contain $Code
        $result.Errors | Should -BeNullOrEmpty
        $result.Policy.Rule | Should -Not -BeNullOrEmpty
    }

    It 'does not warn about Mode for tags when Mode is Indexed' {
        $script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field `"tags['env']`" | Must -Exist }").Replace("DisplayName = 'Test policy'", "DisplayName = 'x'; Mode = 'Indexed'")
        $result = Invoke-BylawTestCompile -Script $script
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'accepts parameters used with matching operators' -ForEach @(
        @{ Case = 'Array with -BeIn'; Requirement = 'Field publicNetworkAccess | Must -BeIn (Param P)'; Parameter = "Parameter P -Default @('uksouth')" }
        @{ Case = 'String with -Be'; Requirement = 'Field publicNetworkAccess | Must -Be (Param P)'; Parameter = 'Parameter P -Default uksouth' }
        @{ Case = 'Integer with -BeGreaterThan'; Requirement = 'Field publicNetworkAccess | Must -BeGreaterThan (Param P)'; Parameter = 'Parameter P -Default 5' }
        @{ Case = 'Float with an integer default'; Requirement = 'Field publicNetworkAccess | Must -BeLessThan (Param P)'; Parameter = 'Parameter P -Type Float -Default 5' }
        @{ Case = 'DateTime with an ISO string'; Requirement = 'Field publicNetworkAccess | Must -BeLessThan (Param P)'; Parameter = "Parameter P -Type DateTime -Default '2026-01-01T00:00:00Z'" }
        @{ Case = 'Array allowed values per element'; Requirement = 'Field publicNetworkAccess | Must -BeIn (Param P)'; Parameter = "Parameter P -Type Array -AllowedValues uksouth, ukwest -Default @('ukwest')" }
        @{ Case = 'a parameter used only in Arm'; Requirement = "Field publicNetworkAccess | Must -Be (Arm `"[first(parameters('p'))]`")"; Parameter = "Parameter P -Default @('uksouth')" }
    ) {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements "Require 'r' { $Requirement }" -Extra $Parameter)
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'explains when an effect arrives in a later milestone' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect DeployIfNotExists')
        ($result.Diagnostics | Where-Object Code -EQ 'BYL3030').Message | Should -BeLike '*planned for a later milestone*'
    }

    It 'points Effect Modify to the Modify block' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect Modify')
        ($result.Diagnostics | Where-Object Code -EQ 'BYL3030').Message | Should -BeLike '*Modify has its own block*'
    }

    It 'reports alias and validation errors from one run together' {
        $script = (Format-BylawTestPolicy -Requirements "Require 'r' { Field publicNetworkAcess | Must -BeLike '*a*' }").Replace("Policy 'test-policy'", "Policy 'Bad Name'")
        $result = Invoke-BylawTestCompile -Script $script
        $result.Errors | Should -Contain 'BYL2001'
        $result.Errors | Should -Contain 'BYL3001'
        $result.Errors | Should -Contain 'BYL3011'
    }
}

Describe 'Azure rule limits' {
    It 'reports more than 5 field count expressions on one array' {
        $each = (1..6 | ForEach-Object { "Each networkAcls.ipRules[*] { Field value | Must -Not -Be '$_' }" }) -join '; '
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements "Require 'r' { $each }")
        $result.Errors | Should -Be @('BYL3050')
    }

    It 'allows 5 field count expressions on one array' {
        $each = (1..5 | ForEach-Object { "Each networkAcls.ipRules[*] { Field value | Must -Not -Be '$_' }" }) -join '; '
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements "Require 'r' { $each }")
        $result.Errors | Should -BeNullOrEmpty
    }
}
