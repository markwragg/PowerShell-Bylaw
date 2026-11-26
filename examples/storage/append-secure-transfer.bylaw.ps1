# Instead of denying a storage account that allows HTTP, Append turns on secure transfer in the
# create or update request. Existing accounts that allow HTTP are reported as non-compliant.
# Azure recommends Modify over Append; Append is here for policies that already use it.

Policy 'storage-append-secure-transfer' {

    Properties @{
        DisplayName = 'Storage accounts are created with secure transfer'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'Secure transfer is required' {
            Field supportsHttpsTrafficOnly | Must -Be $true
        }
    }

    Append {
        Field supportsHttpsTrafficOnly | Add $true
    }
}
