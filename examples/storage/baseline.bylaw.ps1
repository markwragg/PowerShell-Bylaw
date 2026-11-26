# A PowerShell loop that generates one Require block per setting.
# The settings are an array, so the requirements, and the output, always come out in the same order.
$baseline = @(
    @{ Description = 'TLS 1.2 is the minimum version'; Field = 'minimumTlsVersion'; Value = 'TLS1_2' }
    @{ Description = 'Only HTTPS traffic is allowed'; Field = 'supportsHttpsTrafficOnly'; Value = $true }
    @{ Description = 'Blobs cannot be made public'; Field = 'allowBlobPublicAccess'; Value = $false }
)

Policy 'storage-require-baseline' {

    Properties @{
        DisplayName = 'Storage accounts should meet the security baseline'
        Description = 'Denies storage accounts that allow TLS versions before 1.2, HTTP traffic or public blob access.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        foreach ($setting in $baseline) {
            Require $setting.Description {
                Field $setting.Field | Must -Be $setting.Value
            }
        }
    }

    Effect Deny
}
