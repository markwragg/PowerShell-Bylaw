# Every resource has every tag in a list that the assignment chooses. A value count goes through
# the list: the policy is met when the number of tags present equals the length of the list.

Policy 'tags-require-mandatory-tags' {

    Properties @{
        DisplayName = 'Resources have every mandatory tag'
        Category    = 'Tags'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter MandatoryTags -Type Array -Default @('CostCenter', 'Owner') -Description 'Tags every resource must have.'

    Resource * {
        Require 'Every mandatory tag is set' {
            Count -Value (Param MandatoryTags) -Name tagName -Where {
                Tag (Current tagName) | Must -Exist
            } | Must -Be (Arm "[length(parameters('mandatoryTags'))]")
        }
    }

    Effect Audit
}
