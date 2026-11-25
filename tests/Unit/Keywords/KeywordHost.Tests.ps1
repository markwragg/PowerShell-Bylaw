BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Keyword scoping (ADR-0005)' {
    It 'relies on ScriptBlock.SessionStateInternal, which must exist' {
        # If this fails, a PowerShell release changed the internal API that keyword scoping uses.
        $property = [scriptblock].GetProperty('SessionStateInternal', [System.Reflection.BindingFlags] 'NonPublic, Instance')
        $property | Should -Not -BeNullOrEmpty
        $property.CanWrite | Should -BeTrue
    }

    It 'exports only Policy' {
        (Get-Module Bylaw).ExportedCommands.Keys | Should -Be @('Policy')
    }

    It 'does not define inner keywords outside a Policy' {
        foreach ($keyword in 'Properties', 'Parameter', 'Resource', 'When', 'Require', 'Each', 'Field', 'Must', 'Effect', 'Param', 'Expr') {
            Get-Command -Name $keyword -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty -Because "$keyword must not leak"
        }
    }

    It 'removes the keywords after the Policy, including after an error' {
        $result = Invoke-BylawTestScript -Script @'
Policy 'a' { Effect Deny; throw 'boom' }
$script:afterError = [bool](Get-Command Field -ErrorAction SilentlyContinue)
'@
        $result.Codes | Should -Contain 'BYL1014'
        Get-Command Field -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'makes file-level variables and helper functions visible inside Policy' {
        $result = Invoke-BylawTestScript -Script @'
$disabled = 'Disabled'
function Get-Requirement { Field publicNetworkAccess | Must -Be $disabled }
Policy 'helpers' {
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' { Get-Requirement }
    }
    Effect Deny
}
'@
        $result.Diagnostics | Should -BeNullOrEmpty
        $assertion = $result.Policies[0].Resource.Requirements[0].Children[0]
        $assertion.Value.Value | Should -Be 'Disabled'
    }

    It 'works when Policy is called from inside a function' {
        $result = Invoke-BylawTestScript -Script @'
function New-TestPolicy([string] $Value) {
    Policy 'from-function' {
        Resource 'Microsoft.Storage/storageAccounts' {
            Require 'r' { Field publicNetworkAccess | Must -Be $Value }
        }
        Effect Deny
    }
}
New-TestPolicy -Value 'Disabled'
'@
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policies[0].Resource.Requirements[0].Children[0].Value.Value | Should -Be 'Disabled'
    }

    It "shadows an author's function of the same name only inside Policy" {
        $result = Invoke-BylawTestScript -Script @'
function Field { 'user-field' }
Policy 'shadow' {
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }
    }
    Effect Deny
}
Set-Content -Path (Join-Path $TestDrive 'user-field.txt') -Value (Field)
'@
        $result.Diagnostics | Should -BeNullOrEmpty
        Get-Content -Path (Join-Path $TestDrive 'user-field.txt') | Should -Be 'user-field'
    }

    It 'gives a clear error for <Keyword> outside a Policy' -ForEach @(
        @{ Keyword = 'Properties' }, @{ Keyword = 'Parameter' }, @{ Keyword = 'Resource' }, @{ Keyword = 'When' },
        @{ Keyword = 'Require' }, @{ Keyword = 'Each' }, @{ Keyword = 'Field' }, @{ Keyword = 'Must' },
        @{ Keyword = 'Effect' }, @{ Keyword = 'Param' }, @{ Keyword = 'Expr' }
    ) {
        { & $Keyword 'x' } | Should -Throw "*BYL1001: '$Keyword' is a Bylaw keyword and can only be used inside a Policy block.*"
    }

    It 'leaves the CommandNotFoundAction for other commands alone' {
        { Invoke-NoSuchBylawCommand } | Should -Throw -ErrorId 'CommandNotFoundException'
    }
}

Describe 'Policy' {
    It 'collects a policy with its name and location' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy)
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policies.Count | Should -Be 1
        $result.Policies[0].Name | Should -Be 'test-policy'
        $result.Policies[0].Location.File | Should -Be $result.Path
        $result.Policies[0].Location.Line | Should -Be 1
    }

    It 'collects several policies from one file' {
        $result = Invoke-BylawTestScript -Script ((Format-BylawTestPolicy) + "`n" + (Format-BylawTestPolicy).Replace('test-policy', 'second'))
        $result.Policies.Name | Should -Be @('test-policy', 'second')
    }

    It 'reports a nested Policy' {
        $result = Invoke-BylawTestScript -Script "Policy 'outer' { Policy 'inner' { }; Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny }"
        $result.Codes | Should -Be @('BYL1003')
    }

    It 'reports a missing Resource and a missing Effect' {
        $result = Invoke-BylawTestScript -Script "Policy 'empty' { }"
        $result.Codes | Should -Be @('BYL1005', 'BYL1006')
    }

    It 'reports PowerShell errors in the body with their line' {
        $result = Invoke-BylawTestScript -Script @'
Policy 'bad-param' {
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' {
            Field publicNetworkAccess | Must -Bee 'Disabled'
        }
    }
    Effect Deny
}
'@
        $diagnostic = $result.Diagnostics | Where-Object Code -EQ 'BYL1014'
        $diagnostic | Should -Not -BeNullOrEmpty
        $diagnostic.Location.Line | Should -Be 4
        $diagnostic.Message | Should -BeLike "*parameter cannot be found*'Bee'*"
    }

    It 'reports <Keyword> used in the wrong block' -ForEach @(
        @{ Keyword = 'Field in Policy'; Script = "Policy 'p' { Field x | Must -Exist; Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny }" }
        @{ Keyword = 'Require in Policy'; Script = "Policy 'p' { Require 'r' { Field name | Must -Exist }; Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny }" }
        @{ Keyword = 'Properties in Resource'; Script = "Policy 'p' { Resource * { Properties @{ DisplayName = 'x' }; Require 'r' { Field name | Must -Exist } }; Effect Deny }" }
        @{ Keyword = 'Effect in Require'; Script = "Policy 'p' { Resource * { Require 'r' { Effect Deny; Field name | Must -Exist } }; Effect Deny }" }
    ) {
        $result = Invoke-BylawTestScript -Script $Script
        $result.Codes | Should -Contain 'BYL1002'
    }

    It 'reports <Keyword> used twice' -ForEach @(
        @{ Keyword = 'Properties'; Script = "Policy 'p' { Properties @{ DisplayName = 'a' }; Properties @{ DisplayName = 'b' }; Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny }" }
        @{ Keyword = 'Resource'; Script = "Policy 'p' { Resource * { Require 'r' { Field name | Must -Exist } }; Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny }" }
        @{ Keyword = 'Effect'; Script = "Policy 'p' { Resource * { Require 'r' { Field name | Must -Exist } }; Effect Deny; Effect Audit }" }
    ) {
        $result = Invoke-BylawTestScript -Script $Script
        $result.Codes | Should -Be @('BYL1004')
        $result.Diagnostics[0].Message | Should -BeLike "'$Keyword' can only appear once*"
    }
}
