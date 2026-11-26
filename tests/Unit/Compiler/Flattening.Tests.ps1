BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    # Test helpers defined inside the module scope, so they can use the IR classes:
    #   New-TestLeaf 'a'          -> an exists condition on field 'a'
    #   New-TestGroup AllOf a, b  -> a group (strings become leaves)
    #   Format-TestTree $tree     -> 'AllOf(a,AnyOf(b,c))'
    InModuleScope Bylaw {
        function script:New-TestLeaf([string] $Name) {
            [BylawFieldCondition]::new([BylawFieldRef]::new($Name), 'exists', [BylawLiteral]::new($true))
        }
        function script:New-TestGroup([BylawGroupKind] $Kind, [object[]] $Children = @()) {
            $nodes = foreach ($child in $Children) {
                if ($child -is [string]) { New-TestLeaf $child } else { $child }
            }
            [BylawGroup]::new($Kind, [BylawCondition[]] @($nodes))
        }
        function script:Format-TestTree($Condition) {
            if ($Condition -is [BylawGroup]) {
                return "$($Condition.Kind)(" + (($Condition.Children | ForEach-Object { Format-TestTree $_ }) -join ',') + ')'
            }
            if ($Condition -is [BylawCountCondition]) {
                return 'Count(' + (Format-TestTree $Condition.Where) + ')'
            }
            if ($Condition -is [BylawNot]) {
                return 'Not(' + (Format-TestTree $Condition.Child) + ')'
            }
            $Condition.Field.Name
        }
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Optimize-BylawCondition' {
    It 'merges a nested group of the same kind' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AllOf @('a', (New-TestGroup AllOf @('b', 'c')))
            Format-TestTree (Optimize-BylawCondition -Condition $tree) | Should -Be 'AllOf(a,b,c)'
        }
    }

    It 'keeps a nested group of the other kind' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AllOf @('a', (New-TestGroup AnyOf @('b', 'c')))
            Format-TestTree (Optimize-BylawCondition -Condition $tree) | Should -Be 'AllOf(a,AnyOf(b,c))'
        }
    }

    It 'unwraps a single-child group' {
        InModuleScope Bylaw {
            Format-TestTree (Optimize-BylawCondition -Condition (New-TestGroup AnyOf @('a'))) | Should -Be 'a'
        }
    }

    It 'unwraps, then merges into the parent' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AnyOf @((New-TestGroup AllOf @((New-TestGroup AnyOf @('a', 'b')))), 'c')
            Format-TestTree (Optimize-BylawCondition -Condition $tree) | Should -Be 'AnyOf(a,b,c)'
        }
    }

    It 'drops empty groups' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AllOf @('a', (New-TestGroup AnyOf))
            Format-TestTree (Optimize-BylawCondition -Condition $tree) | Should -Be 'a'
        }
    }

    It 'returns null for an empty group' {
        InModuleScope Bylaw {
            Optimize-BylawCondition -Condition (New-TestGroup AllOf) | Should -BeNullOrEmpty
        }
    }

    It 'flattens inside count where' {
        InModuleScope Bylaw {
            $count = [BylawCountCondition]::new([BylawFieldRef]::new('x[*]'), (New-TestGroup AnyOf @('a')), 'greater', [BylawLiteral]::new(0))
            $optimized = Optimize-BylawCondition -Condition $count
            Format-TestTree $optimized | Should -Be 'Count(a)'
            $optimized.Operator | Should -Be 'greater'
            $optimized.Field.Name | Should -Be 'x[*]'
        }
    }

    It 'flattens inside not' {
        InModuleScope Bylaw {
            $not = [BylawNot]::new((New-TestGroup AllOf @((New-TestGroup AllOf @('a', 'b')))))
            Format-TestTree (Optimize-BylawCondition -Condition $not) | Should -Be 'Not(AllOf(a,b))'
        }
    }

    It 'keeps child order' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AnyOf @('a', (New-TestGroup AnyOf @('b', 'c')), 'd')
            (Optimize-BylawCondition -Condition $tree).Children.Field.Name | Should -Be @('a', 'b', 'c', 'd')
        }
    }

    It 'does not change the input tree' {
        InModuleScope Bylaw {
            $inner = New-TestGroup AllOf @('a')
            $outer = New-TestGroup AllOf @($inner)
            $null = Optimize-BylawCondition -Condition $outer
            $outer.Children[0] | Should -Be $inner
            $inner.Children.Count | Should -Be 1
        }
    }
}
