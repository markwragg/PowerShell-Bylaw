BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Get-FirstAssertion($Result) {
        $Result.Policies[0].Resource.Requirements[0].Children[0]
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Resource' {
    It 'records the resource type' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy)
        $result.Policies[0].Resource.Type | Should -Be 'Microsoft.Storage/storageAccounts'
        $result.Policies[0].Resource.IsAnyType() | Should -BeFalse
    }

    It 'accepts Resource * as a bare word' {
        $result = Invoke-BylawTestScript -Script "Policy 'any' { Resource * { Require 'r' { Field location | Must -Exist } }; Effect Audit }"
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policies[0].Resource.IsAnyType() | Should -BeTrue
    }

    It 'accepts a child resource type' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type 'Microsoft.Storage/storageAccounts/blobServices')
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'rejects an invalid type' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type 'storageAccounts')
        $result.Codes | Should -Contain 'BYL1021'
    }
}

Describe 'When and Require' {
    It 'keeps When and Require blocks in order with their descriptions' {
        $requirements = @'
When { Field kind | Must -BeIn 'StorageV2', 'BlockBlobStorage' }
Require 'first' { Field publicNetworkAccess | Must -Be 'Disabled' }
Require 'second' {
    Field minimumTlsVersion | Must -Be 'TLS1_2'
    Field allowBlobPublicAccess | Must -Be $false
}
'@
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $resource = $result.Policies[0].Resource
        $resource.When.Count | Should -Be 1
        $resource.When[0].Children[0].Field.Name | Should -Be 'kind'
        $resource.Requirements.Description | Should -Be @('first', 'second')
        $resource.Requirements[1].Children.Count | Should -Be 2
        $resource.Requirements[1].Children[1].Value.Value | Should -BeFalse
    }

    It 'reports an empty <Keyword> block' -ForEach @(
        @{ Keyword = 'Require'; Requirements = "Require 'r' { }" }
        @{ Keyword = 'When'; Requirements = "When { }; Require 'r' { Field name | Must -Exist }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Be @('BYL1013')
    }

    It 'reports a Require without a description' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require '' { Field name | Must -Exist }")
        $result.Codes | Should -Be @('BYL1017')
    }
}

Describe 'Each and Item' {
    It 'records an Each block with element fields' {
        $requirements = "Require 'r' { Each networkAcls.ipRules[*] { Field value | Must -Not -Be '0.0.0.0/0' } }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $each = Get-FirstAssertion $result
        $each.Field.Name | Should -Be 'networkAcls.ipRules[*]'
        $each.Children[0].Field.Name | Should -Be 'value'
        $each.Children[0].Negated | Should -BeTrue
    }

    It 'supports nested Each and Item' {
        $requirements = "Require 'r' { Each networkAcls.virtualNetworkRules[*] { Each tags[*] { Item | Must -Not -Be 'x' } } }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $inner = (Get-FirstAssertion $result).Children[0]
        $inner.Children[0].Field.Kind.ToString() | Should -Be 'Item'
    }

    It 'requires a path ending in [*]' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Each networkAcls.ipRules { Field value | Must -Exist } }")
        $result.Codes | Should -Contain 'BYL1016'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'Each in When'; Requirements = "When { Each a[*] { Item | Must -Exist } }; Require 'r' { Field name | Must -Exist }" }
        @{ Case = 'Item outside Each'; Requirements = "Require 'r' { Item | Must -Exist }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Contain 'BYL1002'
    }
}

Describe 'Field and Must' {
    It 'maps -<DslOperator> to <Operator>' -ForEach @(
        @{ DslOperator = 'Be'; Argument = "'x'"; Operator = 'equals' }
        @{ DslOperator = 'BeIn'; Argument = "'a', 'b'"; Operator = 'in' }
        @{ DslOperator = 'BeLike'; Argument = "'a*'"; Operator = 'like' }
        @{ DslOperator = 'Match'; Argument = "'##'"; Operator = 'matchInsensitively' }
        @{ DslOperator = 'MatchCase'; Argument = "'##'"; Operator = 'match' }
        @{ DslOperator = 'ContainText'; Argument = "'x'"; Operator = 'contains' }
        @{ DslOperator = 'ContainKey'; Argument = "'k'"; Operator = 'containsKey' }
        @{ DslOperator = 'Exist'; Argument = ''; Operator = 'exists' }
        @{ DslOperator = 'BeGreaterThan'; Argument = '1'; Operator = 'greater' }
        @{ DslOperator = 'BeGreaterOrEqual'; Argument = '1'; Operator = 'greaterOrEquals' }
        @{ DslOperator = 'BeLessThan'; Argument = '1'; Operator = 'less' }
        @{ DslOperator = 'BeLessOrEqual'; Argument = '1'; Operator = 'lessOrEquals' }
    ) {
        $requirements = "Require 'r' { Field x | Must -$DslOperator $Argument }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $assertion = Get-FirstAssertion $result
        $assertion.DslOperator | Should -Be $DslOperator
        $assertion.Operator | Should -BeExactly $Operator
        $assertion.Negated | Should -BeFalse
        $assertion.MissingMode.ToString() | Should -Be 'Default'
        $assertion.Location.Keyword | Should -Be 'Must'
        $assertion.Field.Location.Keyword | Should -Be 'Field'
    }

    It 'records -Not and -IfPresent' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Field x | Must -Not -BeLike 'a*' -IfPresent }")
        $result.Diagnostics | Should -BeNullOrEmpty
        $assertion = Get-FirstAssertion $result
        $assertion.Negated | Should -BeTrue
        $assertion.MissingMode.ToString() | Should -Be 'IfPresent'
    }

    It 'records -Strict inside Each' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Each a[*] { Field b | Must -Be 'x' -Strict } }")
        $result.Diagnostics | Should -BeNullOrEmpty
        (Get-FirstAssertion $result).Children[0].MissingMode.ToString() | Should -Be 'Strict'
    }

    It 'keeps -BeIn with one value as an array' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Field x | Must -BeIn 'only' }")
        $value = (Get-FirstAssertion $result).Value.Value
        , $value | Should -BeOfType ([object[]])
        $value | Should -Be @('only')
    }

    It 'accepts a parameter as the -BeIn value' {
        $extra = 'Parameter Allowed -Type Array'
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra $extra -Requirements "Require 'r' { Field location | Must -BeIn (Param Allowed) }")
        $result.Diagnostics | Should -BeNullOrEmpty
        (Get-FirstAssertion $result).Value.Name | Should -Be 'Allowed'
    }

    It 'records -AllowUnknownAlias on the field' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Field newThing -AllowUnknownAlias | Must -Exist }")
        (Get-FirstAssertion $result).Field.AllowUnknownAlias | Should -BeTrue
    }

    It 'rejects <Case> with <Code>' -ForEach @(
        @{ Case = 'no operator'; Code = 'BYL1009'; Requirements = "Require 'r' { Field x | Must }" }
        @{ Case = 'two operators'; Code = 'BYL1009'; Requirements = "Require 'r' { Field x | Must -Be 'a' -BeLike 'a*' }" }
        @{ Case = 'no pipeline input'; Code = 'BYL1008'; Requirements = "Require 'r' { Field x | Out-Null; Must -Be 'a' }" }
        @{ Case = 'a non-field input'; Code = 'BYL1008'; Requirements = "Require 'r' { 'x' | Must -Be 'a' }" }
        @{ Case = 'Field without Must'; Code = 'BYL1007'; Requirements = "Require 'r' { Field x; Field y | Must -Exist }" }
        @{ Case = '-IfPresent in When'; Code = 'BYL1010'; Requirements = "When { Field x | Must -Be 'a' -IfPresent }; Require 'r' { Field y | Must -Exist }" }
        @{ Case = '-IfPresent inside Each'; Code = 'BYL1010'; Requirements = "Require 'r' { Each a[*] { Field b | Must -Be 'x' -IfPresent } }" }
        @{ Case = '-Strict outside Each'; Code = 'BYL1010'; Requirements = "Require 'r' { Field x | Must -Be 'a' -Strict }" }
        @{ Case = '-IfPresent with -Exist'; Code = 'BYL1010'; Requirements = "Require 'r' { Field x | Must -Exist -IfPresent }" }
        @{ Case = 'an array mixing Param and literals'; Code = 'BYL1020'; Requirements = "Require 'r' { Field x | Must -BeIn 'a', (Param P) }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements -Extra 'Parameter P -Default a')
        $result.Codes | Should -Contain $Code
    }

    It 'reports the line of the failing Must' {
        $script = @'
Policy 'lines' {
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' {
            Field a | Must -Be 'x'
            Field b | Must
        }
    }
    Effect Deny
}
'@
        $result = Invoke-BylawTestScript -Script $script
        $result.Diagnostics[0].Location.Line | Should -Be 5
        $result.Diagnostics[0].Location.Keyword | Should -Be 'Must'
        $result.Diagnostics[0].ToString() | Should -BeLike '*test.bylaw.ps1:5 `[Must`] BYL1009: *'
    }
}
