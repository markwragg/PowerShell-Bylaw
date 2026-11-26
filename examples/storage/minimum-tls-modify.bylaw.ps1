# Set the minimum TLS version of storage accounts instead of denying them. The field is an alias,
# not a tag, so the conflict effect is Audit: a request made with an API version where the property
# can't be modified is audited rather than denied, as Azure recommends.
Policy 'storage-set-minimum-tls' {

    Properties @{
        DisplayName = 'Storage accounts should use TLS 1.2'
        Description = 'Sets the minimum TLS version of storage accounts to TLS 1.2.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Modify, Disabled -Default Modify

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'TLS 1.2 or later' {
            Field minimumTlsVersion | Must -Be 'TLS1_2'
        }
    }

    Modify -Role 'Storage Account Contributor' -ConflictEffect Audit -Effect (Param Effect) {
        # minimumTlsVersion can only be set from API version 2019-04-01.
        Field minimumTlsVersion | AddOrReplace 'TLS1_2' -Condition (Arm "[greaterOrEquals(requestContext().apiVersion, '2019-04-01')]")
    }
}
