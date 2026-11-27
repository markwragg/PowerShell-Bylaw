BeforeDiscovery {
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Nsg = 'Microsoft.Network/networkSecurityGroups'
    $script:Rules = "$Nsg/securityRules[*]"

    function Invoke-NsgCompile {
        # A network security group policy with the given Require statements, When and extra lines.
        param([string] $Requirements = '', [string] $Extra = '', [string] $Effect = 'Deny')
        Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type $Nsg -Requirements $Requirements -Extra $Extra -Effect $Effect)
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

Describe 'Count (ADR-0032)' {
    Context 'field counts' {
        It 'inverts a count in Require, with no guard' {
            $violation = Get-Violation (Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must -BeGreaterThan 0 }")
            $violation.Keys | Should -Be @('count', 'lessOrEquals')
            $violation['count'].Keys | Should -Be @('field')
            $violation['count']['field'] | Should -BeExactly $Rules
            $violation['lessOrEquals'] | Should -Be 0
        }

        It 'emits <Operator> in Require as <Expected>' -ForEach @(
            @{ Operator = '-Be 0'; Expected = 'notEquals' }
            @{ Operator = '-Not -Be 0'; Expected = 'equals' }
            @{ Operator = '-BeIn 1, 2'; Expected = 'notIn' }
            @{ Operator = '-BeGreaterOrEqual 1'; Expected = 'less' }
            @{ Operator = '-BeLessThan 5'; Expected = 'greaterOrEquals' }
            @{ Operator = '-BeLessOrEqual 5'; Expected = 'greater' }
        ) {
            $violation = Get-Violation (Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must $Operator }")
            @($violation.Keys)[1] | Should -BeExactly $Expected
        }

        It 'emits a count in When as written' {
            $result = Invoke-NsgCompile -Requirements "When { Count securityRules[*] | Must -BeGreaterThan 0 }; Require 'r' { Field securityRules | Must -Exist }"
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $when = $result.RuleObject['if']['allOf'][1]
            $when['count']['field'] | Should -BeExactly $Rules
            $when['greater'] | Should -Be 0
        }

        It 'emits -Where as written, with fields relative to the element and no guards' {
            $requirements = "Require 'r' { Count securityRules[*] -Where { Field direction | Must -Be 'Inbound'; Field access | Must -Not -Be 'Deny' } | Must -BeLessOrEqual 2 }"
            $violation = Get-Violation (Invoke-NsgCompile -Requirements $requirements)
            Format-BylawTestCondition -Condition $violation['count']['where'] | Should -Be 'allOf[equals, notEquals]'
            $violation['count']['where']['allOf'][0]['field'] | Should -BeExactly "$Rules.direction"
            $violation['greater'] | Should -Be 2
        }

        It 'keeps AnyOf in -Where' {
            $requirements = "Require 'r' { Count securityRules[*] -Where { AnyOf { Field sourceAddressPrefix | Must -Be '*'; Field sourceAddressPrefix | Must -Be 'Internet' } } | Must -Be 0 }"
            Format-BylawTestCondition -Condition (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where'] | Should -Be 'anyOf[equals, equals]'
        }

        It 'reports BYL2005 for a count path with [*] at two levels, pointing to a nested count' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*].destinationPortRanges[*] | Must -Be 0 }"
            Get-Message $result 'BYL2005' | Should -BeLike '*Nest one Each (or Count -Where) per array level instead.'
        }

        It 'uses Element for the element of a primitive array' {
            $requirements = "Require 'r' { Each securityRules[*] { Count destinationPortRanges[*] -Where { Element | Must -Be '22' } | Must -Be 0 } }"
            $where = (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where']
            $where['count']['where']['field'] | Should -BeExactly "$Rules.destinationPortRanges[*]"
            $where['count']['where']['equals'] | Should -BeExactly '22'
        }

        It 'uses Current for the element of a field count, as current() of the array alias' {
            $requirements = "Require 'r' { Count securityRules[*] -Where { Current | Must -Not -Be '' } | Must -BeGreaterThan 0 }"
            $where = (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where']
            $where['value'] | Should -BeExactly "[current('$Rules')]"
            $where['notEquals'] | Should -BeExactly ''
        }

        It 'resolves a nested field count relative to the element, with Element in its -Where' {
            $requirements = "Require 'r' { Count securityRules[*] -Where { Count destinationPortRanges[*] -Where { Element | Must -Be '*' } | Must -BeGreaterThan 0 } | Must -Be 0 }"
            $inner = (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where']
            $inner['count']['field'] | Should -BeExactly "$Rules.destinationPortRanges[*]"
            $inner['count']['where']['field'] | Should -BeExactly "$Rules.destinationPortRanges[*]"
            $inner['count']['where']['equals'] | Should -BeExactly '*'
            $inner['greater'] | Should -Be 0
        }

        It 'resolves a count inside Each relative to the element' {
            $requirements = "Require 'r' { Each securityRules[*] { Count destinationPortRanges[*] | Must -BeLessOrEqual 3 } }"
            $where = (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where']
            $where['count']['field'] | Should -BeExactly "$Rules.destinationPortRanges[*]"
            $where['greater'] | Should -Be 3
        }

        It 'counts in an existence condition, as written' {
            $effect = "AuditIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' { Require 'r' { Count logs[*] -Where { Field enabled | Must -Be `$true } | Must -BeGreaterThan 0 } }"
            $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type 'Microsoft.KeyVault/vaults' -Requirements '' -Effect 'Audit').Replace('Effect Audit', $effect)
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $condition = $result.RuleObject['then']['details']['existenceCondition']
            $condition['count']['field'] | Should -BeExactly 'Microsoft.Insights/diagnosticSettings/logs[*]'
            $condition['greater'] | Should -Be 0
        }
    }

    Context 'value counts' {
        It 'counts the members of a parameter, with Current name as a value' {
            $requirements = "Require 'The name matches a pattern' { Count -Value (Param NamePatterns) -Name pattern -Where { Field name | Must -BeLike (Current pattern) } | Must -BeGreaterThan 0 }"
            $result = Invoke-NsgCompile -Requirements $requirements -Extra 'Parameter NamePatterns -Type Array -Default @(''nsg-*'')'
            $violation = Get-Violation $result
            $violation['count'].Keys | Should -Be @('value', 'name', 'where')
            $violation['count']['value'] | Should -BeExactly "[parameters('namePatterns')]"
            $violation['count']['name'] | Should -BeExactly 'pattern'
            $violation['count']['where']['field'] | Should -BeExactly 'name'
            $violation['count']['where']['like'] | Should -BeExactly "[current('pattern')]"
            $violation['lessOrEquals'] | Should -Be 0
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'counts a literal list, with Current as current()' {
            $requirements = "Require 'r' { Count -Value @('Inbound', 'Outbound') -Where { Current | Must -Be 'Inbound' } | Must -Be 1 }"
            $violation = Get-Violation (Invoke-NsgCompile -Requirements $requirements)
            , $violation['count']['value'] | Should -BeOfType [object[]]
            $violation['count']['where']['value'] | Should -BeExactly '[current()]'
        }

        It 'uses ResourceGroupTag (Current name)' {
            $requirements = "Require 'r' { Count -Value (Param TagNames) -Name tagName -Where { ResourceGroupTag (Current tagName) | Must -Be 'yes' } | Must -Be (Arm `"[length(parameters('tagNames'))]`") }"
            $where = (Get-Violation (Invoke-NsgCompile -Requirements $requirements -Extra 'Parameter TagNames -Type Array -Default @(''a'')'))['count']['where']
            $where['value'] | Should -BeExactly "[resourceGroup().tags[current('tagName')]]"
            $where['equals'] | Should -BeExactly 'yes'
        }

        It 'refers to an outer value count by name from a nested count' {
            $requirements = "Require 'r' { Count -Value @('a', 'b') -Name outer -Where { Count -Value @('x') -Name inner -Where { Current outer | Must -Be (Current inner) } | Must -BeGreaterThan 0 } | Must -Be 2 }"
            $inner = (Get-Violation (Invoke-NsgCompile -Requirements $requirements))['count']['where']
            $inner['count']['where']['value'] | Should -BeExactly "[current('outer')]"
            $inner['count']['where']['equals'] | Should -BeExactly "[current('inner')]"
        }
    }

    Context 'front-end errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1047'; Case = 'neither a path nor -Value'; Statements = 'Count | Must -Be 0' }
            @{ Code = 'BYL1047'; Case = 'a path and -Value'; Statements = "Count securityRules[*] -Value @('a') | Must -Be 0" }
            @{ Code = 'BYL1047'; Case = 'a path without [*]'; Statements = 'Count securityRules | Must -Be 0' }
            @{ Code = 'BYL1047'; Case = 'a -Value that is not a list'; Statements = "Count -Value 'a' | Must -Be 0" }
            @{ Code = 'BYL1048'; Case = '-Name on a field count'; Statements = 'Count securityRules[*] -Name rule | Must -Be 0' }
            @{ Code = 'BYL1048'; Case = 'a -Name with a hyphen'; Statements = "Count -Value @('a') -Name tag-name | Must -Be 0" }
            @{ Code = 'BYL1049'; Case = 'a nested value count without -Name'; Statements = "Count securityRules[*] -Where { Count -Value @('a') | Must -Be 0 } | Must -Be 0" }
            @{ Code = 'BYL1049'; Case = 'a value count in Each without -Name'; Statements = "Each securityRules[*] { Count -Value @('a') | Must -Be 0 }" }
            @{ Code = 'BYL1050'; Case = 'Current outside -Where'; Statements = "Current | Must -Be 'a'" }
            @{ Code = 'BYL1050'; Case = 'Current with an unknown name'; Statements = "Count -Value @('a') -Name tagName -Where { Current other | Must -Be 'a' } | Must -Be 0" }
            @{ Code = 'BYL1050'; Case = 'Current without a name in a nested value count'; Statements = "Count securityRules[*] -Where { Count -Value @('a') -Name x -Where { Current | Must -Be 'a' } | Must -Be 0 } | Must -Be 0" }
            @{ Code = 'BYL1051'; Case = '-BeLike on a count'; Statements = "Count securityRules[*] | Must -BeLike '1*'" }
            @{ Code = 'BYL1051'; Case = '-Exist on a count'; Statements = 'Count securityRules[*] | Must -Exist' }
            @{ Code = 'BYL1051'; Case = '-IfPresent on a count'; Statements = 'Count securityRules[*] | Must -Be 0 -IfPresent' }
            @{ Code = 'BYL1010'; Case = '-IfPresent in -Where'; Statements = "Count securityRules[*] -Where { Field access | Must -Be 'Allow' -IfPresent } | Must -Be 0" }
            @{ Code = 'BYL1052'; Case = 'a count used as a value'; Statements = 'Field securityRules | Must -Be (Count securityRules[*])' }
            @{ Code = 'BYL1007'; Case = 'a count not piped to Must'; Statements = "Count securityRules[*]; Field access | Must -Be 'a'" }
            @{ Code = 'BYL1002'; Case = 'Each in -Where'; Statements = "Count securityRules[*] -Where { Each destinationPortRanges[*] { Element | Must -Be '1' } } | Must -Be 0" }
            @{ Code = 'BYL1002'; Case = 'Element in a value count'; Statements = "Count -Value @('a') -Where { Element | Must -Be 'a' } | Must -Be 0" }
            @{ Code = 'BYL1013'; Case = 'an empty -Where'; Statements = 'Count securityRules[*] -Where { } | Must -Be 0' }
            @{ Code = 'BYL1023'; Case = 'ResourceGroupTag (Current) in a field count'; Statements = "Count securityRules[*] -Where { ResourceGroupTag (Current) | Must -Be 'a' } | Must -Be 0" }
            @{ Code = 'BYL1059'; Case = 'Tag (Current name) in a value count'; Statements = "Count -Value @('a') -Name tagName -Where { Tag (Current tagName) | Must -Exist } | Must -Be 0" }
            @{ Code = 'BYL1059'; Case = 'Tag (Current) in a field count'; Statements = 'Count securityRules[*] -Where { Tag (Current) | Must -Exist } | Must -Be 0' }
        ) {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type 'Microsoft.Network/networkSecurityGroups' -Requirements "Require 'r' { $Statements }")
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'explains the operators a count takes' {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type $Nsg -Requirements "Require 'r' { Count securityRules[*] | Must -BeLike '1*' }")
            Get-Message $result 'BYL1051' | Should -BeLike 'A count is a number, so it is tested with -Be, -BeIn, *not -BeLike.'
        }

        It 'says how to pipe a count that is not piped to Must' {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type $Nsg -Requirements "Require 'r' { Count securityRules[*]; Field access | Must -Be 'a' }")
            Get-Message $result 'BYL1007' | Should -BeLike '''Count securityRules`[`*`]'' is not piped to Must.*'
        }
    }

    Context 'validation' {
        It 'reports BYL3100 for <Case>' -ForEach @(
            @{ Case = 'a string'; Must = "-Be 'none'"; Extra = '' }
            @{ Case = 'a fraction'; Must = '-BeGreaterThan 1.5'; Extra = '' }
            @{ Case = 'a negative number'; Must = '-BeGreaterThan -1'; Extra = '' }
            @{ Case = 'a list with a string'; Must = "-BeIn 1, 'two'"; Extra = '' }
            @{ Case = 'a String parameter'; Must = '-Be (Param Limit)'; Extra = 'Parameter Limit -Default ''2''' }
        ) {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must $Must }" -Extra $Extra
            $result.Errors | Should -Contain 'BYL3100'
        }

        It 'accepts an Integer parameter' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] | Must -BeLessOrEqual (Param Limit) }" -Extra 'Parameter Limit -Default 2'
            $result.Errors | Should -BeNullOrEmpty
        }

        It 'reports BYL3101 for a -Value parameter that is not an Array' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count -Value (Param Tags) | Must -Be 0 }" -Extra 'Parameter Tags -Default x'
            Get-Message $result 'BYL3101' | Should -BeLike '*needs an Array parameter*'
        }

        It 'reports an undeclared -Value parameter' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count -Value (Param Missing) | Must -Be 0 }"
            Get-Message $result 'BYL3020' | Should -BeLike "*'Missing' is counted but not declared*"
        }

        It 'checks the statements in -Where' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] -Where { Field access | Must -BeLike '*a*' } | Must -Be 0 }"
            $result.Errors | Should -Contain 'BYL3011'
        }

        It 'reports BYL3052 for more than 10 value counts in a rule' {
            $statements = (1..11 | ForEach-Object { "Count -Value @('a') | Must -Be $_" }) -join '; '
            $result = Invoke-NsgCompile -Requirements "Require 'r' { $statements }"
            Get-Message $result 'BYL3052' | Should -BeLike '*11 value counts*at most 10*'
        }

        It 'reports BYL3053 for <Case>' -ForEach @(
            @{ Case = 'a literal list over 100'; Statements = "Count -Value @(1..101) | Must -Be 0" }
            @{ Case = 'nested lists over 100 together'; Statements = "Count -Value @(1..11) -Name a -Where { Count -Value @(1..10) -Name b | Must -Be 1 } | Must -Be 0" }
        ) {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { $Statements }"
            $result.Errors | Should -Contain 'BYL3053'
        }

        It 'accepts nested lists of exactly 100 iterations' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Count -Value @(1..10) -Name a -Where { Count -Value @(1..10) -Name b | Must -Be 1 } | Must -Be 0 }"
            $result.Errors | Should -Not -Contain 'BYL3053'
        }

        It 'counts Count towards the 5 field counts per array (BYL3050)' {
            $statements = (1..6 | ForEach-Object { "Count securityRules[*] | Must -Not -Be $_" }) -join '; '
            $result = Invoke-NsgCompile -Requirements "Require 'r' { $statements }"
            $result.Errors | Should -Contain 'BYL3050'
        }

        It 'suggests Count for a [*] field outside Each (BYL2005)' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Field 'securityRules[*].access' | Must -Be 'Deny' }"
            Get-Message $result 'BYL2005' | Should -BeLike '*or count the elements: Count securityRules`[`*`] -Where { Field access | Must ... } | Must -BeGreaterThan 0*'
        }
    }
}
