# A literal effect: Bylaw generates the effect parameter (Audit, Deny, Disabled; default Audit).
Policy 'key-vault-require-recovery' {

    Properties @{
        DisplayName = 'Key vaults should be recoverable'
        Description = 'Audits key vaults without purge protection, or that keep deleted vaults for less than the minimum number of days.'
        Category    = 'Key Vault'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter MinimumRetentionDays -Type Integer -Default 90 -DisplayName 'Minimum retention in days'

    Resource 'Microsoft.KeyVault/vaults' {

        Require 'Purge protection is enabled' {
            Field enablePurgeProtection | Must -Be $true
        }

        # Not set means the default of 90 days.
        Require 'Deleted vaults are kept long enough' {
            Field softDeleteRetentionInDays | Must -BeGreaterOrEqual (Param MinimumRetentionDays) -IfPresent
        }
    }

    Effect Audit
}
