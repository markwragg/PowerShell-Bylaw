# Every resource's name matches one of the patterns that the assignment chooses. A value count goes
# through the list: the policy is met when at least one pattern matches.

Policy 'general-name-matches-a-pattern' {

    Properties @{
        DisplayName = 'Resource names match an allowed pattern'
        Category    = 'General'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter NamePatterns -Type Array -Default @('rg-*', 'st*') -Description 'Patterns a resource name can match, each with at most one *.'

    Resource * {
        Require 'The name matches an allowed pattern' {
            Count -Value (Param NamePatterns) -Name pattern -Where {
                Field name | Must -BeLike (Current pattern)
            } | Must -BeGreaterThan 0
        }
    }

    Effect Audit
}
