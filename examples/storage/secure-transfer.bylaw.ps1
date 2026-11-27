# Several Require blocks, several Must statements in one block, an array parameter in the hashtable
# form and -IfPresent.
Policy 'storage-require-secure-transfer' {

    Properties @{
        DisplayName = 'Storage accounts should use secure transfer'
        Description = 'Audits storage accounts that allow HTTP, use an old TLS version or allow anonymous blob access.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    # A parameter with several options reads better as a hashtable, one option per line.
    Parameter AllowedTlsVersions @{
        Type          = 'Array'
        AllowedValues = 'TLS1_2', 'TLS1_3'
        Default       = 'TLS1_2', 'TLS1_3'
        DisplayName   = 'Allowed TLS versions'
    }

    Resource 'Microsoft.Storage/storageAccounts' {

        Require 'Only HTTPS traffic with a current TLS version' {
            Field supportsHttpsTrafficOnly | Must -Be $true
            Field minimumTlsVersion | Must -BeIn (Param AllowedTlsVersions)
        }

        # Not set means anonymous access is off on current API versions.
        Require 'No anonymous blob access' {
            Field allowBlobPublicAccess | Must -Not -Be $true -IfPresent
        }
    }

    Effect (Param Effect)
}
