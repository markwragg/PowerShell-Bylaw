# Resource * applies to every resource type, so fields must be top-level ones such as location.
Policy 'general-allowed-locations' {

    Properties @{
        DisplayName = 'Resources should be deployed to allowed locations'
        Description = 'Denies resources outside the allowed locations. Global resources are not affected.'
        Category    = 'General'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny
    Parameter AllowedLocations -Type Array -Default uksouth, ukwest -DisplayName 'Allowed locations'

    Resource * {

        When {
            Field location | Must -Not -Be 'global'
        }

        Require 'The location is allowed' {
            Field location | Must -BeIn (Param AllowedLocations)
        }
    }

    Effect (Param Effect)
}
