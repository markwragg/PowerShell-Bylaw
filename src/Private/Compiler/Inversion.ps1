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
# AnyOf { P; Q } holds when either holds; its violation is allOf[ violation(P), violation(Q) ].
# AllOf { P; Q } holds when both hold; its violation is anyOf[ violation(P), violation(Q) ]
# (ADR-0026). Each statement inside keeps its own missing-field handling.
#
# A value condition (ResourceGroupTag, Param or Arm piped into Must) is inverted like a field
# condition, but never guarded: an expression has no missing state (ADR-0025).
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

    if ($Policy.Effect -is [BylawIfNotExists]) {
        $Policy.Effect.ExistenceCondition = ConvertTo-BylawExistenceCondition -Effect $Policy.Effect
    }

    $if = [BylawGroup]::new([BylawGroupKind]::AllOf, $conditions.ToArray())
    $if.Location = $scope.Location
    $rule = [BylawPolicyRule]::new((Optimize-BylawCondition -Condition $if), $Policy.Effect)
    $rule.Location = $Policy.Location
    $rule
}

function ConvertTo-BylawExistenceCondition {
    # The existence condition of AuditIfNotExists or DeployIfNotExists: the Require blocks in their
    # compliant form, combined with AND (ADR-0030). $null when there are none.
    param([Parameter(Mandatory)] [BylawIfNotExists] $Effect)

    $compliant = [System.Collections.Generic.List[object]]::new()
    foreach ($requirement in $Effect.Requirements) {
        $children = foreach ($child in $requirement.Children) {
            ConvertTo-BylawCompliance -Node $child
        }
        $group = [BylawGroup]::new([BylawGroupKind]::AllOf, [object[]] @($children))
        $group.Location = $requirement.Location
        $group.Origin = $requirement
        $compliant.Add($group)
    }
    if ($compliant.Count -eq 0) {
        return $null
    }
    $all = [BylawGroup]::new([BylawGroupKind]::AllOf, $compliant.ToArray())
    $all.Location = $Effect.Location
    Optimize-BylawCondition -Condition $all
}

function ConvertTo-BylawCompliance {
    # The compliant form of a Require child, for an existence condition (ADR-0030). The same
    # missing-field rules as the violation form (ADR-0004), applied to the compliant condition:
    #
    #   strict  (default):  allOf[ exists:true,  P ]  if P is true on a missing field
    #   lenient (-IfPresent): anyOf[ exists:false, P ]  if P is false on a missing field
    #
    # Each path[*] { P } holds when no element violates P: count(where: violation(P)) equals 0.
    param([Parameter(Mandatory)] [BylawNode] $Node)

    if ($Node -is [BylawConditionGroup]) {
        $children = foreach ($child in $Node.Children) {
            ConvertTo-BylawCompliance -Node $child
        }
        $group = [BylawGroup]::new($Node.Kind, [object[]] @($children))
        $group.Location = $Node.Location
        $group.Origin = $Node
        return $group
    }

    if ($Node -is [BylawEach]) {
        $elementViolations = foreach ($child in $Node.Children) {
            ConvertTo-BylawViolation -Node $child -InEach $true
        }
        $where = [BylawGroup]::new([BylawGroupKind]::AnyOf, [object[]] @($elementViolations))
        $where.Location = $Node.Location
        $count = [BylawCountCondition]::new($Node.Field, $where, 'equals', [BylawLiteral]::new(0))
        $count.Location = $Node.Location
        $count.Origin = $Node
        return $count
    }

    $assertion = [BylawAssertion] $Node
    $operator, $value = Get-BylawAssertedOperator -Assertion $assertion -Invert $false
    $condition = New-BylawAssertionCondition -Assertion $assertion -Operator $operator -Value $value

    # As for the violation form: expressions, exists conditions and Element need no guard.
    if ($null -ne $assertion.Subject -or $operator -eq 'exists' -or $assertion.Field.Kind -eq [BylawFieldKind]::Element) {
        return $condition
    }

    $strict = $assertion.MissingMode -ne [BylawMissingMode]::IfPresent
    $falseOnMissing = Test-BylawFalseOnMissing -Operator $operator -Value $value

    if ($strict -and -not $falseOnMissing) {
        return New-BylawGuardedCondition -Kind AllOf -Exists $true -Condition $condition
    }
    if (-not $strict -and $falseOnMissing) {
        return New-BylawGuardedCondition -Kind AnyOf -Exists $false -Condition $condition
    }
    $condition
}

function ConvertTo-BylawApplicabilityCondition {
    # A When assertion or group, emitted as written: the compliant operator, no guards.
    param(
        [Parameter(Mandatory)] [BylawNode] $Node
    )

    if ($Node -is [BylawConditionGroup]) {
        $children = foreach ($child in $Node.Children) {
            ConvertTo-BylawApplicabilityCondition -Node $child
        }
        $group = [BylawGroup]::new($Node.Kind, [object[]] @($children))
        $group.Location = $Node.Location
        $group.Origin = $Node
        return $group
    }

    $operator, $value = Get-BylawAssertedOperator -Assertion $Node -Invert $false
    New-BylawAssertionCondition -Assertion $Node -Operator $operator -Value $value
}

function New-BylawAssertionCondition {
    # The condition for an assertion with the given operator: a field condition, or a value
    # condition when the assertion tests an expression (ADR-0025).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory IR node only.')]
    param(
        [Parameter(Mandatory)] [BylawAssertion] $Assertion,
        [Parameter(Mandatory)] [string] $Operator,
        [AllowNull()] [BylawValue] $Value
    )

    $condition = if ($null -ne $Assertion.Subject) {
        [BylawValueCondition]::new($Assertion.Subject, $Operator, $Value)
    }
    else {
        [BylawFieldCondition]::new($Assertion.Field, $Operator, $Value)
    }
    $condition.Location = $Assertion.Location
    $condition.Origin = $Assertion
    $condition
}

function ConvertTo-BylawViolation {
    # The violation (negation) of a Require child: an assertion, an Each block or a group.
    param(
        [Parameter(Mandatory)] [BylawNode] $Node,
        [Parameter(Mandatory)] [bool] $InEach
    )

    if ($Node -is [BylawConditionGroup]) {
        # De Morgan: the violation of AnyOf is allOf of the violations, and the reverse for AllOf.
        $children = foreach ($child in $Node.Children) {
            ConvertTo-BylawViolation -Node $child -InEach $InEach
        }
        $kind = if ($Node.Kind -eq [BylawGroupKind]::AnyOf) { [BylawGroupKind]::AllOf } else { [BylawGroupKind]::AnyOf }
        $group = [BylawGroup]::new($kind, [object[]] @($children))
        $group.Location = $Node.Location
        $group.Origin = $Node
        return $group
    }

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
    $inverted = New-BylawAssertionCondition -Assertion $assertion -Operator $operator -Value $value

    # An expression has no missing state (ADR-0025), exists conditions need no guard, and Element
    # (the array element itself) is never missing.
    if ($null -ne $assertion.Subject -or $operator -eq 'exists' -or $assertion.Field.Kind -eq [BylawFieldKind]::Element) {
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
