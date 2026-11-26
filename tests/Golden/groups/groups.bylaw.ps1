# AnyOf and AllOf outside Each (ADR-0026): in When, emitted as written; at the top level of
# Require, inverted with De Morgan, with each statement keeping its own missing-field handling.
Policy 'golden-groups' {

    Properties @{
        DisplayName = 'Golden: AnyOf and AllOf'
        Category    = 'Storage'
        Version     = '1.0.0'
    }

    Resource 'Microsoft.Storage/storageAccounts' {

        When {
            AnyOf {
                Field kind | Must -Be 'StorageV2'
                AllOf {
                    Field kind | Must -Be 'BlockBlobStorage'
                    Field sku.name | Must -Not -BeLike 'Standard_*'
                }
            }
        }

        Require 'Public access is closed, or limited to trusted services' {
            AnyOf {
                Field publicNetworkAccess | Must -Be 'Disabled'
                AllOf {
                    Field networkAcls.defaultAction | Must -Be 'Deny'
                    Field networkAcls.bypass | Must -ContainText 'AzureServices' -IfPresent
                }
            }
        }

        Require 'TLS is current' {
            AnyOf {
                Field minimumTlsVersion | Must -Be 'TLS1_2'
                Field minimumTlsVersion | Must -Be 'TLS1_3'
            }
        }
    }

    Effect Audit
}
