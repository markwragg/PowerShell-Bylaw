BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'BylawSourceLocation' {
    It 'formats as file:line [Keyword]' {
        InModuleScope Bylaw {
            $location = [BylawSourceLocation]::new('/src/storage.bylaw.ps1', 12, 5, 'Must')
            $location.ToString() | Should -Be '/src/storage.bylaw.ps1:12 [Must]'
        }
    }

    It 'omits missing parts' {
        InModuleScope Bylaw {
            [BylawSourceLocation]::new($null, 0, 0, $null).ToString() | Should -Be '<unknown>'
            [BylawSourceLocation]::new('a.bylaw.ps1', 0, 0, 'Policy').ToString() | Should -Be 'a.bylaw.ps1 [Policy]'
        }
    }

    It 'is created from an InvocationInfo' {
        InModuleScope Bylaw {
            function Get-TestLocation {
                [BylawSourceLocation]::FromInvocation($MyInvocation, 'Field')
            }
            $location = Get-TestLocation
            $location.Keyword | Should -Be 'Field'
            $location.Line | Should -BeGreaterThan 0
            $location.File | Should -BeLike '*IR.Tests.ps1'
        }
    }

    It 'tolerates a null InvocationInfo' {
        InModuleScope Bylaw {
            $location = [BylawSourceLocation]::FromInvocation($null, 'Field')
            $location.Keyword | Should -Be 'Field'
            $location.Line | Should -Be 0
        }
    }
}

Describe 'BylawOperator' {
    It 'recognises every Azure Policy condition operator' {
        InModuleScope Bylaw {
            [BylawOperator]::All.Count | Should -Be 19
            foreach ($operator in [BylawOperator]::All) {
                [BylawOperator]::IsValid($operator) | Should -BeTrue
            }
        }
    }

    It 'returns canonical casing case-insensitively' {
        InModuleScope Bylaw {
            [BylawOperator]::Canonical('NOTEQUALS') | Should -BeExactly 'notEquals'
            [BylawOperator]::Canonical('matchinsensitively') | Should -BeExactly 'matchInsensitively'
        }
    }

    It 'rejects unknown operators' {
        InModuleScope Bylaw {
            [BylawOperator]::IsValid('regex') | Should -BeFalse
            [BylawOperator]::Canonical('') | Should -BeNullOrEmpty
        }
    }
}

Describe 'Policy-layer conditions' {
    It 'creates a field condition with the canonical operator' {
        InModuleScope Bylaw {
            $field = [BylawFieldRef]::new('kind')
            $condition = [BylawFieldCondition]::new($field, 'IN', [BylawLiteral]::new(@('StorageV2')))
            $condition.Operator | Should -BeExactly 'in'
            $condition.Field.Name | Should -Be 'kind'
            $condition.Value.Value | Should -Be @('StorageV2')
        }
    }

    It 'rejects an unknown operator on <Type>' -ForEach @(
        @{ Type = 'BylawFieldCondition' }
        @{ Type = 'BylawValueCondition' }
        @{ Type = 'BylawCountCondition' }
    ) {
        InModuleScope Bylaw -Parameters @{ Type = $Type } {
            param($Type)
            $create = switch ($Type) {
                'BylawFieldCondition' { { [BylawFieldCondition]::new([BylawFieldRef]::new('x'), 'bogus', [BylawLiteral]::new(1)) } }
                'BylawValueCondition' { { [BylawValueCondition]::new([BylawExpr]::new('[1]'), 'bogus', [BylawLiteral]::new(1)) } }
                'BylawCountCondition' { { [BylawCountCondition]::new([BylawFieldRef]::new('x[*]'), $null, 'bogus', [BylawLiteral]::new(0)) } }
            }
            $create | Should -Throw "*Unknown policy operator 'bogus'*"
        }
    }

    It 'builds a count condition with a where clause' {
        InModuleScope Bylaw {
            $where = [BylawFieldCondition]::new([BylawFieldRef]::new('value'), 'equals', [BylawLiteral]::new('0.0.0.0/0'))
            $count = [BylawCountCondition]::new([BylawFieldRef]::new('networkAcls.ipRules[*]'), $where, 'greater', [BylawLiteral]::new(0))
            $count.Where | Should -Be $where
            $count.Operator | Should -BeExactly 'greater'
            $count.Value.Value | Should -Be 0
        }
    }

    It 'groups children in order' {
        InModuleScope Bylaw {
            $a = [BylawFieldCondition]::new([BylawFieldRef]::new('a'), 'exists', [BylawLiteral]::new($true))
            $b = [BylawFieldCondition]::new([BylawFieldRef]::new('b'), 'exists', [BylawLiteral]::new($true))
            $group = [BylawGroup]::new([BylawGroupKind]::AnyOf, @($a, $b))
            $group.Kind | Should -Be ([BylawGroupKind]::AnyOf)
            $group.Children.Count | Should -Be 2
            $group.Children[0] | Should -Be $a
            $group.Children[1] | Should -Be $b
            $group.ToString() | Should -Be 'AnyOf[2]'
        }
    }

    It 'starts an empty group with an empty child list' {
        InModuleScope Bylaw {
            [BylawGroup]::new([BylawGroupKind]::AllOf).Children.Count | Should -Be 0
        }
    }

    It 'wraps a condition in Not' {
        InModuleScope Bylaw {
            $inner = [BylawFieldCondition]::new([BylawFieldRef]::new('a'), 'equals', [BylawLiteral]::new('x'))
            [BylawNot]::new($inner).Child | Should -Be $inner
        }
    }

    It 'keeps provenance to the DSL node it came from' {
        InModuleScope Bylaw {
            $assertion = [BylawAssertion]::new()
            $condition = [BylawFieldCondition]::new([BylawFieldRef]::new('a'), 'notEquals', [BylawLiteral]::new('x'))
            $condition.Origin = $assertion
            $condition.Origin | Should -Be $assertion
        }
    }
}

Describe 'Values and fields' {
    It 'renders values for diagnostics' {
        InModuleScope Bylaw {
            [BylawLiteral]::new('Disabled').ToString() | Should -Be 'Disabled'
            [BylawParamRef]::new('Effect').ToString() | Should -Be 'Param Effect'
            [BylawExpr]::new("[field('location')]").ToString() | Should -Be "[field('location')]"
        }
    }

    It 'shows the resolved alias once resolution has run' {
        InModuleScope Bylaw {
            $field = [BylawFieldRef]::new('publicNetworkAccess')
            $field.ToString() | Should -Be 'publicNetworkAccess'
            $field.Resolved = 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
            $field.ToString() | Should -Be 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
        }
    }

    It 'represents the current element of a primitive array' {
        InModuleScope Bylaw {
            $item = [BylawFieldRef]::new()
            $item.Kind = [BylawFieldKind]::Item
            $item.ToString() | Should -Be 'Item'
        }
    }
}

Describe 'DSL-layer nodes' {
    It 'renders an assertion as written' {
        InModuleScope Bylaw {
            $assertion = [BylawAssertion]::new()
            $assertion.Field = [BylawFieldRef]::new('value')
            $assertion.DslOperator = 'Be'
            $assertion.Operator = 'equals'
            $assertion.Value = [BylawLiteral]::new('0.0.0.0/0')
            $assertion.Negated = $true
            $assertion.ToString() | Should -Be 'value | Must -Not -Be 0.0.0.0/0'

            $assertion.MissingMode = [BylawMissingMode]::Strict
            $assertion.ToString() | Should -Be 'value | Must -Not -Be 0.0.0.0/0 -Strict'
        }
    }

    It 'defaults assertions to the Default missing mode' {
        InModuleScope Bylaw {
            [BylawAssertion]::new().MissingMode | Should -Be ([BylawMissingMode]::Default)
        }
    }

    It 'holds the storage example structure' {
        InModuleScope Bylaw {
            $policy = [BylawPolicy]::new('storage-deny-public-network-access')
            $policy.Parameters.Add([BylawParameter]::new('Effect'))
            $policy.Resource = [BylawResourceScope]::new('Microsoft.Storage/storageAccounts')

            $requirement = [BylawRequirement]::new('No allow-all IP rules')
            $each = [BylawEach]::new([BylawFieldRef]::new('networkAcls.ipRules[*]'))
            $each.Children.Add([BylawAssertion]::new())
            $requirement.Children.Add($each)
            $policy.Resource.Requirements.Add($requirement)
            $policy.Resource.When.Add([BylawApplicability]::new())
            $policy.Effect = [BylawEffect]::new([BylawParamRef]::new('Effect'))

            $policy.Resource.IsAnyType() | Should -BeFalse
            $policy.Resource.Requirements[0].Description | Should -Be 'No allow-all IP rules'
            $policy.Resource.Requirements[0].Children[0].Children.Count | Should -Be 1
            $policy.Effect.Value.Name | Should -Be 'Effect'
            $policy.Rule | Should -BeNullOrEmpty
        }
    }

    It 'recognises Resource *' {
        InModuleScope Bylaw {
            [BylawResourceScope]::new('*').IsAnyType() | Should -BeTrue
        }
    }

    It 'finds parameters case-insensitively' {
        InModuleScope Bylaw {
            $policy = [BylawPolicy]::new('p')
            $policy.Parameters.Add([BylawParameter]::new('Effect'))
            $policy.FindParameter('effect').Name | Should -Be 'Effect'
            $policy.FindParameter('missing') | Should -BeNullOrEmpty
        }
    }
}

Describe 'Diagnostics' {
    It 'formats as location, code and message' {
        InModuleScope Bylaw {
            $location = [BylawSourceLocation]::new('a.bylaw.ps1', 7, 9, 'Field')
            $diagnostic = [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL2001', "Unknown alias 'publicNetworkAcess'.", $location)
            $diagnostic.ToString() | Should -Be "a.bylaw.ps1:7 [Field] BYL2001: Unknown alias 'publicNetworkAcess'."
        }
    }

    It 'carries every diagnostic in a compile exception, one per line' {
        InModuleScope Bylaw {
            $first = [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL0001', 'First.', [BylawSourceLocation]::new('a.bylaw.ps1', 1, 1, 'Policy'))
            $second = [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL0002', 'Second.', [BylawSourceLocation]::new('a.bylaw.ps1', 2, 1, 'Field'))
            $exception = [BylawCompileException]::new(@($first, $second))
            $exception.Diagnostics.Count | Should -Be 2
            $exception.Message | Should -BeExactly "a.bylaw.ps1:1 [Policy] BYL0001: First.`na.bylaw.ps1:2 [Field] BYL0002: Second."
            $exception | Should -BeOfType ([System.Exception])
        }
    }
}
