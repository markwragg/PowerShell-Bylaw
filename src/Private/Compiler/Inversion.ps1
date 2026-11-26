# Inversion pass (ADR-0002, ADR-0003, ADR-0004).
#
# Builds the policy-layer rule from the DSL layer:
#
#   if   = allOf[ type condition (unless Resource *), When conditions (as written),
#                 anyOf[ violation(R1), violation(R2), ... ] ]
#   then = effect
#
# A violation is NOT(compliant), pushed inward with De Morgan and operator inversion. Missing-field
# guards are added only where the inverted operator wouldn't already give the required result:
#
#   strict  (default in Require; -Strict in Each):     anyOf[ exists:false, inv(P) ]  if inv(P) is false on missing
#   lenient (-IfPresent; default for Each elements):    allOf[ exists:true,  inv(P) ]  if inv(P) is true on missing
#
# Each path[*] { P } means every element satisfies P; its violation is
#   count(field: path[*], where: violation(P)) greater 0.
#
# Run the alias resolution pass first: conditions use FieldRef.Resolved.

function ConvertTo-BylawPolicyRule {
    [CmdletBinding()]
    [OutputType([BylawPolicyRule])]
    param([Parameter(Mandatory)] [BylawPolicy] $Policy)

    $scope = $Policy.Resource
    $conditions = [System.Collections.Generic.List[object]]::new()

    if (-not $scope.IsAnyType()) {
        $typeField = [BylawFieldRef]::new('type')
        $typeField.Resolved = 'type'
        $typeField.Location = $scope.Location
        $typeValue = if ($scope.ResolvedType) { $scope.ResolvedType } else { $scope.Type }
        $typeCondition = [BylawFieldCondition]::new($typeField, 'equals', [BylawLiteral]::new($typeValue))
        $typeCondition.Location = $scope.Location
        $typeCondition.Origin = $scope
        $conditions.Add($typeCondition)
    }

    foreach ($applicability in $scope.When) {
        foreach ($child in $applicability.Children) {
            $conditions.Add((ConvertTo-BylawApplicabilityCondition -Node $child))
        }
    }

    $violations = [System.Collections.Generic.List[object]]::new()
    foreach ($requirement in $scope.Requirements) {
        $requirementViolations = foreach ($child in $requirement.Children) {
            ConvertTo-BylawViolation -Node $child -InEach $false
        }
        $group = [BylawGroup]::new([BylawGroupKind]::AnyOf, [object[]] @($requirementViolations))
        $group.Location = $requirement.Location
        $group.Origin = $requirement
        $violations.Add($group)
    }
    if ($violations.Count -gt 0) {
        $anyViolation = [BylawGroup]::new([BylawGroupKind]::AnyOf, $violations.ToArray())
        $anyViolation.Location = $scope.Location
        $conditions.Add($anyViolation)
    }

    $if = [BylawGroup]::new([BylawGroupKind]::AllOf, $conditions.ToArray())
    $if.Location = $scope.Location
    $rule = [BylawPolicyRule]::new((Optimize-BylawCondition -Condition $if), $Policy.Effect)
    $rule.Location = $Policy.Location
    $rule
}

function ConvertTo-BylawApplicabilityCondition {
    # A When assertion, emitted as written: the compliant operator, no guards.
    param(
        [Parameter(Mandatory)] [BylawAssertion] $Node
    )

    $operator, $value = Get-BylawAssertedOperator -Assertion $Node -Invert $false
    $condition = [BylawFieldCondition]::new($Node.Field, $operator, $value)
    $condition.Location = $Node.Location
    $condition.Origin = $Node
    $condition
}

function ConvertTo-BylawViolation {
    # The violation (negation) of a Require child: an assertion or an Each block.
    param(
        [Parameter(Mandatory)] [BylawNode] $Node,
        [Parameter(Mandatory)] [bool] $InEach
    )

    if ($Node -is [BylawEach]) {
        $elementViolations = foreach ($child in $Node.Children) {
            ConvertTo-BylawViolation -Node $child -InEach $true
        }
        $where = [BylawGroup]::new([BylawGroupKind]::AnyOf, [object[]] @($elementViolations))
        $where.Location = $Node.Location
        $count = [BylawCountCondition]::new($Node.Field, $where, 'greater', [BylawLiteral]::new(0))
        $count.Location = $Node.Location
        $count.Origin = $Node
        return $count
    }

    $assertion = [BylawAssertion] $Node
    $operator, $value = Get-BylawAssertedOperator -Assertion $assertion -Invert $true
    $inverted = [BylawFieldCondition]::new($assertion.Field, $operator, $value)
    $inverted.Location = $assertion.Location
    $inverted.Origin = $assertion

    # exists conditions need no guard, and Element (the array element itself) is never missing.
    if ($operator -eq 'exists' -or $assertion.Field.Kind -eq [BylawFieldKind]::Element) {
        return $inverted
    }

    $strict = switch ($assertion.MissingMode) {
        ([BylawMissingMode]::Strict) { $true }
        ([BylawMissingMode]::IfPresent) { $false }
        default { -not $InEach }
    }
    $falseOnMissing = Test-BylawFalseOnMissing -Operator $operator -Value $value

    if ($strict -and $falseOnMissing) {
        return New-BylawGuardedCondition -Kind AnyOf -Exists $false -Condition $inverted
    }
    if (-not $strict -and -not $falseOnMissing) {
        return New-BylawGuardedCondition -Kind AllOf -Exists $true -Condition $inverted
    }
    $inverted
}

function Get-BylawAssertedOperator {
    # The operator and value an assertion compiles to, before guards. With -Invert, the operator of
    # the violation. Returns @(operator, value).
    param(
        [Parameter(Mandatory)] [BylawAssertion] $Assertion,
        [Parameter(Mandatory)] [bool] $Invert
    )

    # Compliant form: the DSL operator, negated by -Not. Violation form: the opposite.
    $flip = $Assertion.Negated -xor $Invert
    if ($Assertion.Operator -eq 'exists') {
        $exists = [bool] $Assertion.Value.Value
        if ($flip) {
            $exists = -not $exists
        }
        $value = [BylawLiteral]::new($exists)
        $value.Location = $Assertion.Location
        return 'exists', $value
    }
    $operator = if ($flip) { Get-BylawInverseOperator -Operator $Assertion.Operator } else { $Assertion.Operator }
    $operator, $Assertion.Value
}

function New-BylawGuardedCondition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory IR node only.')]
    param(
        [Parameter(Mandatory)] [BylawGroupKind] $Kind,
        [Parameter(Mandatory)] [bool] $Exists,
        [Parameter(Mandatory)] [BylawFieldCondition] $Condition
    )

    $existsValue = [BylawLiteral]::new($Exists)
    $guard = [BylawFieldCondition]::new($Condition.Field, 'exists', $existsValue)
    $guard.Location = $Condition.Location
    $guard.Origin = $Condition.Origin
    $group = [BylawGroup]::new($Kind, [object[]] @($guard, $Condition))
    $group.Location = $Condition.Location
    $group.Origin = $Condition.Origin
    $group
}
