# Operator facts used by the inversion pass (ADR-0002, ADR-0004, ADR-0015).

# Every operator pair is an exact complement, on present values and on missing fields alike
# (measured in the ADR-0004 sandbox run). 'exists' is its own inverse with the value flipped.
$script:BylawInverseOperators = @{
    equals                = 'notEquals'
    notEquals             = 'equals'
    in                    = 'notIn'
    notIn                 = 'in'
    like                  = 'notLike'
    notLike               = 'like'
    match                 = 'notMatch'
    notMatch              = 'match'
    matchInsensitively    = 'notMatchInsensitively'
    notMatchInsensitively = 'matchInsensitively'
    contains              = 'notContains'
    notContains           = 'contains'
    containsKey           = 'notContainsKey'
    notContainsKey        = 'containsKey'
    greater               = 'lessOrEquals'
    lessOrEquals          = 'greater'
    less                  = 'greaterOrEquals'
    greaterOrEquals       = 'less'
}

# Operators that evaluate to false on a missing field (ADR-0004). Their complements are true.
# greaterOrEquals and lessOrEquals are *true* on a missing field: they behave as "not less" and
# "not greater".
$script:BylawFalseOnMissingOperators = @(
    'equals', 'in', 'like', 'match', 'matchInsensitively', 'contains', 'containsKey', 'greater', 'less'
)

function Get-BylawInverseOperator {
    param([Parameter(Mandatory)] [string] $Operator)

    $inverse = $script:BylawInverseOperators[$Operator]
    if (-not $inverse) {
        throw [System.ArgumentException]::new("Operator '$Operator' has no inverse.")
    }
    $inverse
}

function Test-BylawFalseOnMissing {
    # True when the condition evaluates to false on a resource that lacks the field.
    param(
        [Parameter(Mandatory)] [string] $Operator,
        [AllowNull()] [BylawValue] $Value
    )

    if ($Operator -eq 'exists') {
        # exists: true is false on a missing field; exists: false is true.
        return ($Value -is [BylawLiteral] -and $Value.Value -eq $true)
    }
    $script:BylawFalseOnMissingOperators -contains $Operator
}
