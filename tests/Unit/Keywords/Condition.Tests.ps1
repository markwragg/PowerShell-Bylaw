BeforeDiscovery {
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Nsg = 'Microsoft.Network/networkSecurityGroups'
    $script:Rules = "$Nsg/securityRules[*]"

    function Invoke-NsgCompile {
        param([string] $Requirements = '', [string] $Extra = '', [string] $Effect = 'Deny')
        Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type $Nsg -Requirements $Requirements -Extra $Extra -Effect $Effect)
    }

    function Get-Rule {
        # The compiled if, after checking there were no errors.
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['if']
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Condition (ADR-0040)' {
    Context 'forms' {
        It 'emits a condition in When as written' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "When { Condition @{ value = '[requestContext().apiVersion]'; greaterOrEquals = '2020-01-01' } }; Require 'r' { Field name | Must -BeLike 'nsg-*' }")
            $if['allOf'][1].Keys | Should -Be @('value', 'greaterOrEquals')
            $if['allOf'][1]['value'] | Should -BeExactly '[requestContext().apiVersion]'
            $if['allOf'][1]['greaterOrEquals'] | Should -BeExactly '2020-01-01'
        }

        It 'emits -Violation in Require as the violation, as written' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Violation @{ field = 'name'; like = 'test-*' } }")
            $if['allOf'][1].Keys | Should -Be @('field', 'like')
            $if['allOf'][1]['like'] | Should -BeExactly 'test-*'
        }

        It 'emits -Compliant in Require as not(...), with no guard' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Compliant @{ field = 'name'; like = 'nsg-*' } }")
            $if['allOf'][1].Keys | Should -Be @('not')
            $if['allOf'][1]['not']['field'] | Should -BeExactly 'name'
            $if['allOf'][1]['not']['like'] | Should -BeExactly 'nsg-*'
        }

        It 'simplifies not(not(...)) for -Compliant on a not' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Compliant @{ not = @{ field = 'name'; like = 'test-*' } } }")
            $if['allOf'][1].Keys | Should -Be @('field', 'like')
        }

        It 'combines with the other statements of a Require' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Field name | Must -BeLike 'nsg-*'; Condition -Violation @{ field = 'location'; equals = 'westus' } }")
            $if['allOf'][1].Keys | Should -Be @('anyOf')
            $if['allOf'][1]['anyOf'][1]['equals'] | Should -BeExactly 'westus'
        }

        It 'reads JSON text, keeping the order of its lists' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Violation '{ ""field"": ""location"", ""in"": [""westus"", ""eastus"", ""centralus""] }' }")
            $if['allOf'][1]['in'] | Should -Be @('westus', 'eastus', 'centralus')
        }

        It 'emits -Compliant inside Each as not(...) in the count''s where, relative to the element' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Each securityRules[*] { Condition -Compliant @{ field = 'priority'; greater = 100 } } }")
            $where = $if['allOf'][1]['count']['where']
            $where.Keys | Should -Be @('not')
            $where['not']['field'] | Should -BeExactly "$Rules.priority"
        }

        It 'emits a condition in Count -Where as written' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Count securityRules[*] -Where { Condition @{ field = 'access'; equals = 'Allow' } } | Must -BeLessOrEqual 5 }")
            $where = $if['allOf'][1]['count']['where']
            $where['field'] | Should -BeExactly "$Rules.access"
            $where['equals'] | Should -BeExactly 'Allow'
        }

        It 'emits a raw count, with its where resolved against its array' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Violation @{ count = @{ field = 'securityRules[*]'; where = @{ field = 'direction'; equals = 'Inbound' } }; greater = 3 } }")
            $count = $if['allOf'][1]
            $count['count']['field'] | Should -BeExactly $Rules
            $count['count']['where']['field'] | Should -BeExactly "$Rules.direction"
            $count['greater'] | Should -Be 3
        }

        It 'emits a raw value count with its name' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Condition -Violation @{ count = @{ value = @('a', 'b'); name = 'item'; where = @{ value = `"[current('item')]`"; equals = 'a' } }; equals = 0 } }")
            $count = $if['allOf'][1]['count']
            $count['value'] | Should -Be @('a', 'b')
            $count['name'] | Should -BeExactly 'item'
            $count['where']['value'] | Should -BeExactly "[current('item')]"
        }
    }

    Context 'field names' {
        It 'resolves <Case>' -ForEach @(
            @{ Case = 'a short name against the type'; Field = 'securityRules'; Expected = 'Microsoft.Network/networkSecurityGroups/securityRules' }
            @{ Case = 'a full alias as written'; Field = 'Microsoft.Network/networkSecurityGroups/securityRules'; Expected = 'Microsoft.Network/networkSecurityGroups/securityRules' }
            @{ Case = 'a [*] field outside Each'; Field = 'securityRules[*].access'; Expected = 'Microsoft.Network/networkSecurityGroups/securityRules[*].access' }
            @{ Case = 'a reserved field'; Field = 'location'; Expected = 'location' }
            @{ Case = 'a tag'; Field = "tags['CostCenter']"; Expected = "tags['CostCenter']" }
            @{ Case = 'an ARM expression'; Field = "[concat('tags[', 'CostCenter', ']')]"; Expected = "[concat('tags[', 'CostCenter', ']')]" }
        ) {
            $requirements = "Require 'r' { Condition -Violation @{ field = `"$Field`"; exists = `$false } }"
            $if = Get-Rule (Invoke-NsgCompile -Requirements $requirements)
            $if['allOf'][1]['field'] | Should -BeExactly $Expected
        }

        It 'keeps a full alias absolute inside Each' {
            $if = Get-Rule (Invoke-NsgCompile -Requirements "Require 'r' { Each securityRules[*] { Condition -Compliant @{ field = '$Rules.access'; equals = 'Deny' } } }")
            $if['allOf'][1]['count']['where']['not']['field'] | Should -BeExactly "$Rules.access"
        }

        It 'reports an alias that is not in the snapshot (BYL2001)' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Condition -Violation @{ field = 'notAnAlias'; exists = `$true } }"
            $result.Codes | Should -Contain 'BYL2001'
        }
    }

    Context 'parameters' {
        It 'emits a Param as its expression, and counts it as used' {
            $result = Invoke-NsgCompile -Extra 'Parameter Allowed -Type Array -Default @(''westus'')' -Requirements "Require 'r' { Condition -Compliant @{ field = 'location'; in = (Param Allowed) } }"
            (Get-Rule $result)['allOf'][1]['not']['in'] | Should -BeExactly "[parameters('allowed')]"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'counts a parameter used in an ARM expression string as used' {
            $result = Invoke-NsgCompile -Extra 'Parameter Region -Default westus' -Requirements "Require 'r' { Condition -Compliant @{ field = 'location'; equals = `"[parameters('region')]`" } }"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'reports an undeclared Param (BYL3020)' {
            $result = Invoke-NsgCompile -Requirements "Require 'r' { Condition -Compliant @{ field = 'location'; equals = (Param Missing) } }"
            Get-Message $result 'BYL3020' | Should -BeLike "Parameter 'Missing' is used in a Condition but not declared*"
        }
    }

    Context 'existence conditions' {
        It 'emits <Form> in an existence condition <Expected>' -ForEach @(
            @{ Form = '-Compliant'; Expected = 'as written'; Keys = @('field', 'equals') }
            @{ Form = '-Violation'; Expected = 'as not(...)'; Keys = @('not') }
        ) {
            $effect = "AuditIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' { Require 'r' { Condition $Form @{ field = 'Microsoft.Insights/diagnosticSettings/workspaceId'; equals = 'x' } } }"
            $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type 'Microsoft.KeyVault/vaults' -Requirements '' -Effect 'Audit').Replace('Effect Audit', $effect)
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $result.RuleObject['then']['details']['existenceCondition'].Keys | Should -Be $Keys
        }
    }

    Context 'checks on other statements' {
        It 'counts the fields of a Condition as checked for Modify (no BYL3070)' {
            $script = @"
Policy 'test-policy' {
    Properties @{ DisplayName = 'Test policy'; Mode = 'Indexed' }
    Resource '$Nsg' {
        Require 'r' { Condition -Compliant @{ field = "tags['Environment']"; equals = 'Production' } }
    }
    Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }
}
"@
            $result = Invoke-BylawTestCompile -Script $script
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $result.Codes | Should -Not -Contain 'BYL3070'
        }
    }

    Context 'errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1061'; Case = 'no switch in Require'; Statements = "Require 'r' { Condition @{ field = 'name'; equals = 'x' } }" }
            @{ Code = 'BYL1061'; Case = 'no switch in Each'; Statements = "Require 'r' { Each securityRules[*] { Condition @{ field = 'access'; equals = 'x' } } }" }
            @{ Code = 'BYL1061'; Case = 'both switches'; Statements = "Require 'r' { Condition -Violation -Compliant @{ field = 'name'; equals = 'x' } }" }
            @{ Code = 'BYL1061'; Case = 'a switch in When'; Statements = "When { Condition -Violation @{ field = 'name'; equals = 'x' } }; Require 'r' { Field name | Must -Be 'x' }" }
            @{ Code = 'BYL1061'; Case = 'a switch in Count -Where'; Statements = "Require 'r' { Count securityRules[*] -Where { Condition -Compliant @{ field = 'access'; equals = 'x' } } | Must -Be 0 }" }
            @{ Code = 'BYL1060'; Case = 'invalid JSON'; Statements = "Require 'r' { Condition -Violation '{ ""field"": ' }" }
            @{ Code = 'BYL1060'; Case = 'a duplicate JSON key'; Statements = "Require 'r' { Condition -Violation '{ ""field"": ""name"", ""field"": ""location"", ""equals"": ""x"" }' }" }
            @{ Code = 'BYL1060'; Case = 'no condition kind'; Statements = "Require 'r' { Condition -Violation @{ equals = 'x' } }" }
            @{ Code = 'BYL1060'; Case = 'two condition kinds'; Statements = "Require 'r' { Condition -Violation @{ field = 'name'; value = 'x'; equals = 'x' } }" }
            @{ Code = 'BYL1060'; Case = 'an unknown operator'; Statements = "Require 'r' { Condition -Violation @{ field = 'name'; startsWith = 'x' } }" }
            @{ Code = 'BYL1060'; Case = 'two operators'; Statements = "Require 'r' { Condition -Violation @{ field = 'name'; equals = 'x'; notEquals = 'y' } }" }
            @{ Code = 'BYL1060'; Case = 'an empty allOf'; Statements = "Require 'r' { Condition -Violation @{ allOf = @() } }" }
            @{ Code = 'BYL1060'; Case = 'a count without field or value'; Statements = "Require 'r' { Condition -Violation @{ count = @{ name = 'x' }; equals = 0 } }" }
            @{ Code = 'BYL1060'; Case = 'a count field without [*]'; Statements = "Require 'r' { Condition -Violation @{ count = @{ field = 'securityRules' }; equals = 0 } }" }
            @{ Code = 'BYL1060'; Case = 'a name on a field count'; Statements = "Require 'r' { Condition -Violation @{ count = @{ field = 'securityRules[*]'; name = 'rule' }; equals = 0 } }" }
            @{ Code = 'BYL1060'; Case = 'a count compared with like'; Statements = "Require 'r' { Condition -Violation @{ count = @{ field = 'securityRules[*]' }; like = '1*' } }" }
            @{ Code = 'BYL1060'; Case = 'exists with a string'; Statements = "Require 'r' { Condition -Violation @{ field = 'name'; exists = 'yes' } }" }
            @{ Code = 'BYL1060'; Case = 'not a hashtable'; Statements = "Require 'r' { Condition -Violation 42 }" }
            @{ Code = 'BYL1020'; Case = 'Param inside a list'; Statements = "Require 'r' { Condition -Violation @{ field = 'location'; in = @('a', (Param P)) } }" }
        ) {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type 'Microsoft.Network/networkSecurityGroups' -Requirements $Statements -Extra 'Parameter P -Default x')
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'says where in the condition the problem is' {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type $Nsg -Requirements "Require 'r' { Condition -Violation @{ anyOf = @(@{ field = 'name'; equals = 'x' }, @{ field = 'name'; startsWith = 'y' }) } }")
            Get-Message $result 'BYL1060' | Should -BeLike '*condition.anyOf`[1`] has an unknown key: startsWith*'
        }

        It 'explains the switches in Require' {
            $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Type $Nsg -Requirements "Require 'r' { Condition @{ field = 'name'; equals = 'x' } }")
            Get-Message $result 'BYL1061' | Should -BeLike 'Condition in Require needs -Violation*or -Compliant*'
        }
    }
}
