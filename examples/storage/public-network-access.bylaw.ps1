Policy 'storage-deny-public-network-access' {

    Properties @{
        DisplayName = 'Storage accounts should disable public network access'
        Description = 'Denies storage accounts that allow public network access or allow-all IP rules.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'All'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.Storage/storageAccounts' {

        When {
            Field kind | Must -BeIn 'StorageV2', 'BlockBlobStorage'
        }

        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }

        Require 'No allow-all IP rules' {
            Each networkAcls.ipRules[*] {
                Field value | Must -Not -Be '0.0.0.0/0'
            }
        }
    }

    Effect (Param Effect)
}
