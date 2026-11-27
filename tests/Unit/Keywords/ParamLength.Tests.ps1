BeforeDiscovery {
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Nsg = 'Microsoft.Network/networkSecurityGroups'
    $script:Patterns = "Parameter NamePatterns -Type Array -Default @('nsg-*')"

    function Invoke-NsgCompile {
        param([string] $Requirements, [string] $Extra = $script:Patterns)
        Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type $Nsg -Requirements $Requirements -Extra $Extra)
    }

    function Get-Violation {
        # The violation of the policy's one Require block, after the type condition.
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['if']['allOf'][1]
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Param -Length (ADR-0020)' {
    Context 'emitted' {
        It 'compares a value count with the length of its list' {
            $requirements = "Require 'r' { Count -Value (Param NamePatterns) -Name pattern -Where { Field name | Must -BeLike (Current pattern) } | Must -Be (Param NamePatterns -Length) }"
            $result = Invoke-NsgCompile -Requirements $requirements
            $violation = Get-Violation $result
            $violation['notEquals'] | Should -BeExactly "[length(parameters('namePatterns'))]"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'uses the parameter''s JSON name' {
            $extra = "Parameter @{ Name = 'NamePatterns'; Type = 'Array'; Default = @('nsg-*'); JsonName = 'patternList' }"
            $requirements = "Require 'r' { Count -Value (Param NamePatterns) -Name p -Where { Field name | Must -BeLike (Current p) } | Must -BeGreaterOrEqual (Param NamePatterns -Length) }"
            (Get-Violation (Invoke-NsgCompile -Requirements $requirements -Extra $extra))['less'] | Should -BeExactly "[length(parameters('patternList'))]"
        }

        It 'is the subject of a value condition' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Param NamePatterns -Length | Must -BeGreaterThan 0 }"
            $violation = Get-Violation $result
            $violation['value'] | Should -BeExactly "[length(parameters('namePatterns'))]"
            $violation['lessOrEquals'] | Should -Be 0
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'takes a parameter of type <Type>' -ForEach @(
            @{ Type = 'String'; Extra = "Parameter Prefix -Type String -Default 'nsg'" }
            @{ Type = 'Object'; Extra = 'Parameter Settings -Type Object -Default @{ a = 1 }' }
        ) {
            $name = if ($Type -eq 'String') { 'Prefix' } else { 'Settings' }
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Param $name -Length | Must -BeLessOrEqual 10 }" -Extra $Extra
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        }
    }

    Context 'errors' {
        It 'reports BYL3020 for an undeclared parameter' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must -Be (Param Missing -Length) }"
            Get-Message $result 'BYL3020' | Should -BeLike "*'Missing' is used but not declared*"
        }

        It 'reports BYL3130 for a parameter length() does not take' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must -Be (Param Limit -Length) }" -Extra 'Parameter Limit -Default 2'
            Get-Message $result 'BYL3130' | Should -BeLike "Param Limit -Length needs an Array, String or Object parameter*is Integer*"
        }

        It 'reports BYL3130 for <Case>' -ForEach @(
            @{ Case = '-BeIn with a length as the value'; Statements = 'Count securityRules[*] | Must -BeIn (Param NamePatterns -Length)' }
            @{ Case = '-BeLike with a length as the value'; Statements = 'Field name | Must -BeLike (Param NamePatterns -Length)' }
            @{ Case = '-BeLike on a length'; Statements = "Param NamePatterns -Length | Must -BeLike '1*'" }
        ) {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { $Statements }"
            Get-Message $result 'BYL3130' | Should -BeLike '*is a whole number*'
        }

        It 'accepts -BeIn on a length' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Param NamePatterns -Length | Must -BeIn 1, 2 }"
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        }

        It 'reports BYL1047 for a length as the list of a value count' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count -Value (Param NamePatterns -Length) | Must -Be 0 }"
            $result.Codes | Should -Contain 'BYL1047'
        }
    }
}
