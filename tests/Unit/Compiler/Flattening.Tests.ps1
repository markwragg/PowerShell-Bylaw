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

Describe 'Optimize-BylawCondition repeated conditions' {
    BeforeAll {
        InModuleScope Bylaw {
            function script:New-TestCondition([string] $Field, [string] $Operator, $Value) {
                $valueNode = if ($Value -is [BylawValue]) { $Value } else { [BylawLiteral]::new($Value) }
                [BylawFieldCondition]::new([BylawFieldRef]::new($Field), $Operator, $valueNode)
            }
            function script:Format-TestCondition($Condition) {
                if ($Condition -is [BylawGroup]) {
                    return "$($Condition.Kind)(" + (($Condition.Children | ForEach-Object { Format-TestCondition $_ }) -join ',') + ')'
                }
                if ($Condition -is [BylawValueCondition]) {
                    return "value $($Condition.Subject) $($Condition.Operator) $($Condition.Value)"
                }
                if ($Condition -is [BylawCountCondition]) {
                    return 'Count'
                }
                "$($Condition.Field.Name) $($Condition.Operator) $($Condition.Value)"
            }
        }
    }

    It 'emits the guard shared by two negated checks on one field once' {
        InModuleScope Bylaw {
            # anyOf[anyOf[x exists false, x equals a], anyOf[x exists false, x equals b]]
            $first = New-TestGroup AnyOf @((New-TestCondition x exists $false), (New-TestCondition x equals 'a'))
            $second = New-TestGroup AnyOf @((New-TestCondition x exists $false), (New-TestCondition x equals 'b'))
            $tree = New-TestGroup AnyOf @($first, $second)
            Format-TestCondition (Optimize-BylawCondition -Condition $tree) | Should -Be 'AnyOf(x exists False,x equals a,x equals b)'
        }
    }

    It 'removes a repeated condition in <Kind>' -ForEach @(@{ Kind = 'AllOf' }, @{ Kind = 'AnyOf' }) {
        InModuleScope Bylaw -Parameters @{ Kind = $Kind } {
            param($Kind)
            $tree = New-TestGroup $Kind @((New-TestCondition x equals 'a'), (New-TestCondition y equals 'b'), (New-TestCondition x equals 'a'))
            Format-TestCondition (Optimize-BylawCondition -Condition $tree) | Should -Be "$Kind(x equals a,y equals b)"
        }
    }

    It 'unwraps a group left with one condition' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AnyOf @((New-TestCondition x equals 'a'), (New-TestCondition x equals 'a'))
            Format-TestCondition (Optimize-BylawCondition -Condition $tree) | Should -Be 'x equals a'
        }
    }

    It 'keeps conditions that differ in <Difference>' -ForEach @(
        @{ Difference = 'field'; Second = @('y', 'equals', 'a') }
        @{ Difference = 'operator'; Second = @('x', 'notEquals', 'a') }
        @{ Difference = 'value'; Second = @('x', 'equals', 'b') }
        @{ Difference = 'value type'; Second = @('x', 'equals', 5) }
    ) {
        InModuleScope Bylaw -Parameters @{ Second = $Second } {
            param($Second)
            # The first condition is x equals '5' when the second has the number 5.
            $firstValue = if ($Second[2] -is [int]) { '5' } else { 'a' }
            $tree = New-TestGroup AnyOf @((New-TestCondition x equals $firstValue), (New-TestCondition @Second))
            (Optimize-BylawCondition -Condition $tree).Children.Count | Should -Be 2
        }
    }

    It 'tells true from the string true' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AnyOf @((New-TestCondition x equals $true), (New-TestCondition x equals 'true'))
            (Optimize-BylawCondition -Condition $tree).Children.Count | Should -Be 2
        }
    }

    It 'compares parameter references and ARM expressions' {
        InModuleScope Bylaw {
            $tree = New-TestGroup AnyOf @(
                (New-TestCondition x in ([BylawParamRef]::new('Allowed')))
                (New-TestCondition x in ([BylawParamRef]::new('Allowed')))
                (New-TestCondition x in ([BylawParamRef]::new('Other')))
                (New-TestCondition x equals ([BylawExpr]::new("[field('y')]")))
                (New-TestCondition x equals ([BylawExpr]::new("[field('y')]")))
            )
            (Optimize-BylawCondition -Condition $tree).Children.Count | Should -Be 3
        }
    }

    It 'removes a repeated value condition' {
        InModuleScope Bylaw {
            $subject = [BylawExpr]::new("[resourceGroup().tags['a']]")
            $tree = New-TestGroup AllOf @(
                [BylawValueCondition]::new($subject, 'notEquals', [BylawLiteral]::new(''))
                (New-TestCondition x equals 'a')
                [BylawValueCondition]::new($subject, 'notEquals', [BylawLiteral]::new(''))
            )
            (Optimize-BylawCondition -Condition $tree).Children.Count | Should -Be 2
        }
    }

    It 'removes a repeated group of conditions' {
        InModuleScope Bylaw {
            $guarded = { New-TestGroup AllOf @((New-TestCondition x exists $true), (New-TestCondition x less 5)) }
            $tree = New-TestGroup AnyOf @((& $guarded), (New-TestCondition y equals 'a'), (& $guarded))
            Format-TestCondition (Optimize-BylawCondition -Condition $tree) | Should -Be 'AnyOf(AllOf(x exists True,x less 5),y equals a)'
        }
    }

    It 'keeps groups whose conditions are in a different order' {
        InModuleScope Bylaw {
            $first = New-TestGroup AllOf @((New-TestCondition x equals 'a'), (New-TestCondition y equals 'b'))
            $second = New-TestGroup AllOf @((New-TestCondition y equals 'b'), (New-TestCondition x equals 'a'))
            (Optimize-BylawCondition -Condition (New-TestGroup AnyOf @($first, $second))).Children.Count | Should -Be 2
        }
    }

    It 'never removes counts, or groups that contain one' {
        InModuleScope Bylaw {
            $newCount = { [BylawCountCondition]::new([BylawFieldRef]::new('x[*]'), (New-TestCondition 'x[*].y' equals 'a'), 'greater', [BylawLiteral]::new(0)) }
            $tree = New-TestGroup AnyOf @(
                (& $newCount)
                (& $newCount)
                (New-TestGroup AllOf @((New-TestCondition z equals 'a'), (& $newCount)))
                (New-TestGroup AllOf @((New-TestCondition z equals 'a'), (& $newCount)))
            )
            (Optimize-BylawCondition -Condition $tree).Children.Count | Should -Be 4
        }
    }
}
