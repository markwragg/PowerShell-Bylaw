# allOf/anyOf flattening pass (ADR-0002).
#
# Returns an equivalent condition tree where:
#   - a group nested in a group of the same kind is merged into its parent (allOf[a, allOf[b]] = allOf[a, b])
#   - a group with one child is replaced by that child
#   - empty groups are removed from their parent
#   - a condition that repeats an earlier sibling exactly is removed (ADR-0004): a field or value
#     condition, or a group made only of those. A repeated condition never changes the result of
#     an allOf or an anyOf. This mostly removes the repeated exists guards from several negated
#     checks on the same field.
# Order is preserved, and the first of any repeated conditions is kept. Count 'where' clauses and
# Not children are flattened too. New group nodes are created; leaf conditions are reused.

function Optimize-BylawCondition {
    [CmdletBinding()]
    [OutputType([BylawCondition])]
    param([Parameter(Mandatory)] [AllowNull()] [BylawCondition] $Condition)

    if ($null -eq $Condition) {
        return $null
    }

    if ($Condition -is [BylawGroup]) {
        $merged = [System.Collections.Generic.List[object]]::new()
        foreach ($child in $Condition.Children) {
            $optimized = Optimize-BylawCondition -Condition $child
            if ($null -eq $optimized) {
                continue
            }
            if ($optimized -is [BylawGroup] -and $optimized.Kind -eq $Condition.Kind) {
                foreach ($grandchild in $optimized.Children) {
                    $merged.Add($grandchild)
                }
            }
            else {
                $merged.Add($optimized)
            }
        }
        $children = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($child in $merged) {
            $key = Get-BylawConditionKey -Condition $child
            if ($null -ne $key -and -not $seen.Add($key)) {
                continue
            }
            $children.Add($child)
        }
        if ($children.Count -eq 0) {
            return $null
        }
        if ($children.Count -eq 1) {
            return $children[0]
        }
        $group = [BylawGroup]::new($Condition.Kind, $children.ToArray())
        $group.Location = $Condition.Location
        $group.Origin = $Condition.Origin
        return $group
    }

    if ($Condition -is [BylawCountCondition] -and $null -ne $Condition.Where) {
        $where = Optimize-BylawCondition -Condition $Condition.Where
        if ([object]::ReferenceEquals($where, $Condition.Where)) {
            return $Condition
        }
        $count = [BylawCountCondition]::new($Condition.Field, $where, $Condition.Operator, $Condition.Value)
        $count.ValueSource = $Condition.ValueSource
        $count.Name = $Condition.Name
        $count.Location = $Condition.Location
        $count.Origin = $Condition.Origin
        return $count
    }

    if ($Condition -is [BylawNot]) {
        $child = Optimize-BylawCondition -Condition $Condition.Child
        # not(not x) is x, e.g. a Condition -Compliant whose raw condition is itself a not (ADR-0040).
        if ($child -is [BylawNot]) {
            return $child.Child
        }
        if ([object]::ReferenceEquals($child, $Condition.Child)) {
            return $Condition
        }
        $not = [BylawNot]::new($child)
        $not.Location = $Condition.Location
        $not.Origin = $Condition.Origin
        return $not
    }

    $Condition
}

function Get-BylawConditionKey {
    # A key that is equal for two conditions exactly when they emit the same JSON, or $null for a
    # condition that has no key (counts and Not). Siblings are in the same scope, so a field name
    # means the same field in both, even before alias resolution.
    [OutputType([string])]
    param([Parameter(Mandatory)] [BylawCondition] $Condition)

    if ($Condition -is [BylawFieldCondition]) {
        $field = if ($Condition.Field.Kind -eq [BylawFieldKind]::Element) { '@element' } elseif ($Condition.Field.Resolved) { $Condition.Field.Resolved } else { $Condition.Field.Name }
        return 'field|{0}|{1}|{2}' -f $field, $Condition.Operator, (Get-BylawValueKey -Value $Condition.Value)
    }
    if ($Condition -is [BylawValueCondition]) {
        return 'value|{0}|{1}|{2}' -f (Get-BylawValueKey -Value $Condition.Subject), $Condition.Operator, (Get-BylawValueKey -Value $Condition.Value)
    }
    if ($Condition -is [BylawGroup]) {
        # A group of keyed conditions, in order. Counts and Not have no key, so a group that holds
        # one is never treated as a repeat.
        $childKeys = [System.Collections.Generic.List[string]]::new()
        foreach ($child in $Condition.Children) {
            $childKey = Get-BylawConditionKey -Condition $child
            if ($null -eq $childKey) {
                return $null
            }
            $childKeys.Add($childKey)
        }
        return '{0}({1})' -f $Condition.Kind, ($childKeys -join ',')
    }
    $null
}

function Get-BylawValueKey {
    [OutputType([string])]
    param([AllowNull()] [BylawValue] $Value)

    if ($null -eq $Value) {
        return 'none'
    }
    if ($Value -is [BylawParamRef]) {
        return 'param:' + $Value.Name
    }
    if ($Value -is [BylawParamLength]) {
        return 'length:' + $Value.Parameter.Name
    }
    if ($Value -is [BylawExpr]) {
        return 'arm:' + $Value.Text
    }
    if ($Value -is [BylawResourceGroupTag]) {
        return 'rgtag:' + (Get-BylawValueKey -Value $Value.TagName)
    }
    if ($Value -is [BylawCurrent]) {
        # The emitted expression: Currents of different counts can name the same member (ADR-0032).
        return 'current:' + (Get-BylawCurrentExpression -Current $Value)
    }
    # Literals: JSON text tells true from 'true' and 5 from '5'.
    'literal:' + (ConvertTo-Json -InputObject $Value.Value -Compress -Depth 20)
}
