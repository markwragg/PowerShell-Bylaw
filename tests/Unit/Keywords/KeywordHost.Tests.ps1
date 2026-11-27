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

    It 'exports Policy and Initiative but none of the inner keywords' {
        $exported = @((Get-Module Bylaw).ExportedCommands.Keys)
        $exported | Should -Contain 'Policy'
        $exported | Should -Contain 'Initiative'
        foreach ($keyword in 'Properties', 'Parameter', 'Resource', 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Field', 'Element', 'Tag', 'ResourceGroupTag', 'Must', 'Effect', 'Param', 'Arm', 'Modify', 'AddOrReplace', 'Add', 'Remove', 'DenyAction', 'Manual', 'Append', 'AuditIfNotExists', 'DeployIfNotExists', 'Deployment', 'Count', 'Current', 'PolicyDefinition', 'DefinitionGroup') {
            $exported | Should -Not -Contain $keyword
        }
    }

    It 'does not define inner keywords outside a Policy' {
        # A leak would be a function from Bylaw (or from no module) visible to the caller. Other
        # modules may legitimately export the same names, e.g. psake's Properties.
        foreach ($keyword in 'Properties', 'Parameter', 'Resource', 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Field', 'Element', 'Tag', 'ResourceGroupTag', 'Must', 'Effect', 'Param', 'Arm', 'Modify', 'AddOrReplace', 'Add', 'Remove', 'DenyAction', 'Manual', 'Append', 'AuditIfNotExists', 'DeployIfNotExists', 'Deployment', 'Count', 'Current', 'PolicyDefinition', 'DefinitionGroup') {
            Get-BylawLeakedKeyword -Name $keyword | Should -BeNullOrEmpty -Because "$keyword must not leak"
        }
    }

    It 'removes the keywords after the Policy, including after an error' {
        $result = Invoke-BylawTestScript -Script @'
Policy 'a' { Effect Deny; throw 'boom' }
$script:afterError = [bool](Get-Command Field -ErrorAction SilentlyContinue)
'@
        $result.Codes | Should -Contain 'BYL1014'
        Get-BylawLeakedKeyword -Name 'Field' | Should -BeNullOrEmpty
        Get-BylawLeakedKeyword -Name 'Effect' | Should -BeNullOrEmpty
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

    # Outside a Policy, a keyword name that another installed module exports (e.g. psake's Properties)
    # resolves to that command before the handler runs. That's a documented limitation (ADR-0005);
    # inside a Policy the keyword always wins.
    It 'gives a clear error for <Keyword> outside a Policy' -ForEach @(
        foreach ($keyword in 'Properties', 'Parameter', 'Resource', 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Field', 'Element', 'Tag', 'ResourceGroupTag', 'Must', 'Effect', 'Param', 'Arm', 'Modify', 'AddOrReplace', 'Add', 'Remove', 'DenyAction', 'Manual', 'Append', 'AuditIfNotExists', 'DeployIfNotExists', 'Deployment', 'Count', 'Current', 'PolicyDefinition', 'DefinitionGroup') {
            $existing = Get-Command -Name $keyword, "Get-$keyword" -ErrorAction SilentlyContinue | Where-Object { $_.ModuleName -ne 'Bylaw' }
            @{ Keyword = $keyword; Skip = [bool] $existing }
        }
    ) {
        if ($Skip) {
            Set-ItResult -Skipped -Because "'$Keyword' resolves to an existing command on this machine"
            return
        }
        { & $Keyword 'x' } | Should -Throw "*BYL1001: '$Keyword' is a Bylaw keyword and can only be used inside a Policy block.*"
    }

    It 'runs the keyword inside a Policy even when another module exports the same name' {
        New-Module -Name BylawClashTest -ScriptBlock { function Properties { 'not-bylaw' } } | Import-Module
        try {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy)
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Policies[0].Properties.DisplayName | Should -Be 'Test policy'
        }
        finally {
            Remove-Module -Name BylawClashTest
        }
    }

    It 'leaves the CommandNotFoundAction for other commands alone' {
        { Invoke-NoSuchBylawCommand } | Should -Throw -ErrorId 'CommandNotFoundException'
    }

    # A scriptblock handler belongs to the importing runspace, so a lookup from another thread, as
    # during tab completion, waited for that runspace and hung the terminal.
    It 'handles unknown commands with compiled code, not a scriptblock' {
        $handler = $ExecutionContext.InvokeCommand.CommandNotFoundAction
        $handler.Target | Should -BeOfType ([Bylaw.KeywordLookup])
        $handler.Method.Name | Should -Be 'OnCommandNotFound'
    }

    It 'imports without the handler when Add-Type fails, as in Constrained Language Mode' {
        InModuleScope Bylaw {
            $saved = $ExecutionContext.InvokeCommand.CommandNotFoundAction
            $savedLookup = $script:BylawKeywordLookup
            Mock Add-Type { throw 'Cannot add type. Definition of new types is not supported in this language mode.' }
            try {
                Register-BylawKeywordLookup -TypeName 'Bylaw.NoSuchKeywordLookup' | Should -BeFalse
                Should -Invoke Add-Type -Times 1 -Exactly
                $ExecutionContext.InvokeCommand.CommandNotFoundAction | Should -Be $saved
                $script:BylawKeywordLookup | Should -Be $savedLookup
            }
            finally {
                $ExecutionContext.InvokeCommand.CommandNotFoundAction = $saved
            }
        }
    }

    It 'passes other names to the handler that was registered before' {
        $saved = $ExecutionContext.InvokeCommand.CommandNotFoundAction
        $previous = [System.EventHandler[System.Management.Automation.CommandLookupEventArgs]] {
            param($source, $lookup)
            $null = $source
            $lookup.CommandScriptBlock = { 'from the previous handler' }
            $lookup.StopSearch = $true
        }
        try {
            $lookup = [Bylaw.KeywordLookup]::new([string[]] @('Zzkeyword'), $previous)
            $ExecutionContext.InvokeCommand.CommandNotFoundAction = [System.EventHandler[System.Management.Automation.CommandLookupEventArgs]] $lookup.OnCommandNotFound
            Invoke-NoSuchBylawCommand | Should -Be 'from the previous handler'
            { Zzkeyword } | Should -Throw "*BYL1001: 'Zzkeyword' is a Bylaw keyword*"
            $lookup.Previous | Should -Be $previous
        }
        finally {
            $ExecutionContext.InvokeCommand.CommandNotFoundAction = $saved
        }
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
