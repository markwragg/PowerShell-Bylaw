# Condition (ADR-0040): raw policy conditions, for what the language can't express. Emitted as
# written in When and Count -Where; in Require and Each, -Violation is emitted as written and
# -Compliant as not(...), with no missing-field guards.

# A raw value condition in When, a raw count with -Violation, and a field condition with
# -Compliant beside a Must.
Policy 'golden-condition-forms' {

    Properties @{
        DisplayName = 'Golden: raw conditions in When and Require'
        Category    = 'Network'
        Version     = '1.0.0'
    }

    Parameter MaxRules -Type Integer -Default 50

    Resource 'Microsoft.Network/networkSecurityGroups' {
        When {
            Condition @{ value = '[requestContext().apiVersion]'; greaterOrEquals = '2020-01-01' }
        }
        Require 'No rule allows SSH from anywhere' {
            Condition -Violation ([ordered]@{
                    count   = [ordered]@{
                        field = 'securityRules[*]'
                        where = [ordered]@{
                            allOf = @(
                                [ordered]@{ field = 'securityRules[*].sourceAddressPrefix'; equals = '*' }
                                [ordered]@{ field = 'securityRules[*].destinationPortRange'; equals = '22' }
                            )
                        }
                    }
                    greater = 0
                })
        }
        Require 'The name and the rule count are within limits' {
            Field name | Must -BeLike 'nsg-*'
            Condition -Compliant ([ordered]@{ count = [ordered]@{ field = 'securityRules[*]' }; lessOrEquals = (Param MaxRules) })
        }
    }

    Effect Audit
}

# Raw conditions inside Each and Count -Where, one of them as JSON text.
Policy 'golden-condition-arrays' {

    Properties @{
        DisplayName = 'Golden: raw conditions on array elements'
        Category    = 'Network'
        Version     = '1.0.0'
    }

    Resource 'Microsoft.Network/networkSecurityGroups' {
        Require 'Every rule has a priority above 100' {
            Each securityRules[*] {
                Condition -Compliant '{ "field": "priority", "greater": 100 }'
            }
        }
        Require 'At most five rules allow traffic' {
            Count securityRules[*] -Where {
                Condition @{ field = 'access'; equals = 'Allow' }
            } | Must -BeLessOrEqual 5
        }
    }

    Effect Audit
}
