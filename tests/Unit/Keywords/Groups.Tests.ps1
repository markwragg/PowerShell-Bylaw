BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Get-RuleText {
        # The compiled 'if' after the type condition, in ADR-0004 notation.
        param([Parameter(Mandatory)] [string] $Requirements)

        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $rest = @($result.RuleObject['if']['allOf'] | Select-Object -Skip 1)
        $rule = if ($rest.Count -eq 1) { $rest[0] } else { [ordered]@{ allOf = $rest } }
        Format-BylawTestCondition -Condition $rule
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'AnyOf and AllOf keywords (ADR-0026)' {
    It 'records an AnyOf group with its children in order' {
        $requirements = @'
Require 'r' {
    AnyOf {
        Field publicNetworkAccess | Must -Be 'Disabled'
        AllOf {
            Field networkAcls.defaultAction | Must -Be 'Deny'
            Field networkAcls.bypass | Must -Be 'AzureServices'
        }
    }
}
'@
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $group = $result.Policies[0].Resource.Requirements[0].Children[0]
        $group.Kind.ToString() | Should -Be 'AnyOf'
        $group.Children[0].Field.Name | Should -Be 'publicNetworkAccess'
        $group.Children[1].Kind.ToString() | Should -Be 'AllOf'
        $group.Children[1].Children.Field.Name | Should -Be @('networkAcls.defaultAction', 'networkAcls.bypass')
        $group.Location.Keyword | Should -Be 'AnyOf'
    }

    It 'allows AnyOf in <Where>' -ForEach @(
        @{ Where = 'When'; Requirements = "When { AnyOf { Field kind | Must -Be 'StorageV2' } }; Require 'r' { Field name | Must -Exist }" }
        @{ Where = 'Require'; Requirements = "Require 'r' { AnyOf { Field name | Must -Exist } }" }
        @{ Where = 'Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { AnyOf { Field value | Must -Be 'x' } } }" }
        @{ Where = 'AnyOf'; Requirements = "Require 'r' { AnyOf { AnyOf { Field name | Must -Exist } } }" }
        @{ Where = 'AllOf'; Requirements = "Require 'r' { AnyOf { AllOf { AnyOf { Field name | Must -Exist } } } }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'allows Each and Element inside a group in Each' {
        $requirements = "Require 'r' { Each accessPolicies[*] { AnyOf { Each permissions.keys[*] { Element | Must -Not -Be 'purge' } } } }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type 'Microsoft.KeyVault/vaults' -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'rejects AllOf directly inside <Where>, where statements already combine with AND' -ForEach @(
        @{ Where = 'When'; Requirements = "When { AllOf { Field kind | Must -Be 'StorageV2' } }; Require 'r' { Field name | Must -Exist }" }
        @{ Where = 'Require'; Requirements = "Require 'r' { AllOf { Field name | Must -Exist } }" }
        @{ Where = 'Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { AllOf { Field value | Must -Be 'x' } } }" }
        @{ Where = 'AllOf'; Requirements = "Require 'r' { AnyOf { AllOf { AllOf { Field name | Must -Exist } } } }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Be @('BYL1022')
        $result.Diagnostics[0].Message | Should -BeLike "*Statements in '$Where' already combine with AND*"
    }

    It 'rejects <Keyword> outside When, Require and Each' -ForEach @(
        @{ Keyword = 'AnyOf' }
        @{ Keyword = 'AllOf' }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra "$Keyword { Field name | Must -Exist }")
        $result.Codes | Should -Be @('BYL1002')
    }

    It 'reports an empty <Keyword> group' -ForEach @(
        @{ Keyword = 'AnyOf'; Requirements = "Require 'r' { AnyOf { } }" }
        @{ Keyword = 'AllOf'; Requirements = "Require 'r' { AnyOf { Field name | Must -Exist; AllOf { } } }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Be @('BYL1013')
        $result.Diagnostics[0].Message | Should -BeLike "'$Keyword' block is empty*"
    }

    It 'does not also report a block left empty by errors inside it' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { AnyOf { Field name | Must } }")
        $result.Codes | Should -Be @('BYL1009')
    }

    It 'applies the rules of the enclosing block to -IfPresent and -Strict: <Case>' -ForEach @(
        @{ Case = '-IfPresent in AnyOf in Require'; Requirements = "Require 'r' { AnyOf { Field name | Must -Be 'x' -IfPresent } }"; Codes = @() }
        @{ Case = '-Strict in AnyOf in Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { AnyOf { Field value | Must -Be 'x' -Strict } } }"; Codes = @() }
        @{ Case = '-Strict in AnyOf in Require'; Requirements = "Require 'r' { AnyOf { Field name | Must -Be 'x' -Strict } }"; Codes = @('BYL1010') }
        @{ Case = '-IfPresent in AnyOf in Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { AnyOf { Field value | Must -Be 'x' -IfPresent } } }"; Codes = @('BYL1010') }
        @{ Case = '-IfPresent in AnyOf in When'; Requirements = "When { AnyOf { Field kind | Must -Be 'x' -IfPresent } }; Require 'r' { Field name | Must -Exist }"; Codes = @('BYL1010') }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Be $Codes
    }

    It 'rejects <Keyword> in a group outside its block' -ForEach @(
        @{ Keyword = 'Element'; Requirements = "Require 'r' { AnyOf { Element | Must -Be 'x' } }" }
        @{ Keyword = 'Each'; Requirements = "When { AnyOf { Each networkAcls.ipRules[*] { Field value | Must -Be 'x' } } }; Require 'r' { Field name | Must -Exist }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Contain 'BYL1002'
        ($result.Diagnostics | Where-Object Code -EQ 'BYL1002').Message | Should -BeLike "'$Keyword' cannot be used inside*even inside AnyOf or AllOf*"
    }

    It 'reports a Field in a group that is not piped to Must' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { AnyOf { Field name; Field kind | Must -Exist } }")
        $result.Codes | Should -Be @('BYL1007')
    }
}

Describe 'AnyOf and AllOf compilation (ADR-0026)' {
    It 'inverts AnyOf into allOf of the violations' {
        Get-RuleText "Require 'r' { AnyOf { Field publicNetworkAccess | Must -Be 'Disabled'; Field minimumTlsVersion | Must -Be 'TLS1_2' } }" |
            Should -Be 'allOf[notEquals, notEquals]'
    }

    It 'inverts AllOf inside AnyOf into anyOf of the violations' {
        $requirements = @'
Require 'r' {
    AnyOf {
        Field publicNetworkAccess | Must -Be 'Disabled'
        AllOf {
            Field networkAcls.defaultAction | Must -Be 'Deny'
            Field minimumTlsVersion | Must -Be 'TLS1_2'
        }
    }
}
'@
        Get-RuleText $requirements | Should -Be 'allOf[notEquals, anyOf[notEquals, notEquals]]'
    }

    It 'keeps each statement''s missing-field handling inside a group' {
        # Strict -Not -Be needs an exists:false guard; -IfPresent -Be needs an exists:true guard.
        $requirements = "Require 'r' { AnyOf { Field publicNetworkAccess | Must -Not -Be 'Enabled'; Field minimumTlsVersion | Must -Be 'TLS1_2' -IfPresent } }"
        Get-RuleText $requirements | Should -Be 'allOf[anyOf[exists:false, equals], exists:true, notEquals]'
    }

    It 'compiles the network security group example to one count with allOf in where' {
        $requirements = @'
Require 'No inbound rule allows traffic from the internet' {
    Each securityRules[*] {
        AnyOf {
            Field direction | Must -Not -Be 'Inbound'
            Field access | Must -Not -Be 'Allow'
            Field sourceAddressPrefix | Must -Not -BeIn '*', 'Internet'
        }
    }
}
'@
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type 'Microsoft.Network/networkSecurityGroups' -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $count = $result.RuleObject['if']['allOf'][1]
        $count['count']['field'] | Should -Be 'Microsoft.Network/networkSecurityGroups/securityRules[*]'
        Format-BylawTestCondition -Condition $count['count']['where'] | Should -Be 'allOf[equals, equals, in]'
        $count['count']['where']['allOf'][2]['field'] | Should -Be 'Microsoft.Network/networkSecurityGroups/securityRules[*].sourceAddressPrefix'
    }

    It 'emits a group in When as written' {
        $requirements = "When { AnyOf { Field kind | Must -Be 'StorageV2'; Field kind | Must -Not -Be 'BlobStorage' } }; Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }"
        Get-RuleText $requirements | Should -Be 'allOf[anyOf[equals, notEquals], notEquals]'
    }

    It 'resolves fields inside a group in Each relative to the array' {
        $requirements = "Require 'r' { Each networkAcls.ipRules[*] { AnyOf { Field value | Must -Be 'x'; Field action | Must -Be 'Allow' } } }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $where = $result.RuleObject['if']['allOf'][1]['count']['where']
        # Element fields are lenient, so each check has an exists:true guard on the same field.
        Format-BylawTestCondition -Condition $where | Should -Be 'allOf[exists:true, notEquals, exists:true, notEquals]'
        @($where['allOf'].field | Select-Object -Unique) | Should -Be @(
            'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value'
            'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].action'
        )
    }

    It 'validates assertions inside a group' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements "Require 'r' { AnyOf { Field notAnAlias | Must -Be 'x' } }")
        $result.Errors | Should -Contain 'BYL2001'
    }

    It 'flattens a group with one statement' {
        Get-RuleText "Require 'r' { AnyOf { Field publicNetworkAccess | Must -Be 'Disabled' } }" | Should -Be 'notEquals'
    }
}
