# allOf/anyOf flattening pass (ADR-0002).
#
# Returns an equivalent condition tree where:
#   - a group nested in a group of the same kind is merged into its parent (allOf[a, allOf[b]] = allOf[a, b])
#   - a group with one child is replaced by that child
#   - empty groups are removed from their parent
# Order is preserved. Count 'where' clauses and Not children are flattened too. New group nodes are
# created; leaf conditions are reused.

function Optimize-BylawCondition {
    [CmdletBinding()]
    [OutputType([BylawCondition])]
    param([Parameter(Mandatory)] [AllowNull()] [BylawCondition] $Condition)

    if ($null -eq $Condition) {
        return $null
    }

    if ($Condition -is [BylawGroup]) {
        $children = [System.Collections.Generic.List[object]]::new()
        foreach ($child in $Condition.Children) {
            $optimized = Optimize-BylawCondition -Condition $child
            if ($null -eq $optimized) {
                continue
            }
            if ($optimized -is [BylawGroup] -and $optimized.Kind -eq $Condition.Kind) {
                foreach ($grandchild in $optimized.Children) {
                    $children.Add($grandchild)
                }
            }
            else {
                $children.Add($optimized)
            }
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
