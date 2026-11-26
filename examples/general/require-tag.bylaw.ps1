# -ContainKey with a parameter value, on every resource type.
Policy 'general-require-tag' {

    Properties @{
        DisplayName = 'Resources should have a required tag'
        Description = 'Audits resources that do not have the required tag.'
        Category    = 'Tags'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter TagName -Type String -Default costCenter -DisplayName 'Tag name'

    Resource * {

        Require 'The tag is present' {
            Field tags | Must -ContainKey (Param TagName)
        }
    }

    Effect (Param Effect)
}
