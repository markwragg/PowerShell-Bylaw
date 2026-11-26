# Nested Each, and Element for arrays of plain values.
Policy 'key-vault-deny-purge-permission' {

    Properties @{
        DisplayName = 'Key vault access policies should not grant purge'
        Description = 'Denies key vaults with an access policy that grants the purge permission on keys, secrets or certificates.'
        Category    = 'Key Vault'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.KeyVault/vaults' {

        Require 'No access policy grants purge' {
            Each accessPolicies[*] {
                Each permissions.keys[*] {
                    Element | Must -Not -Be 'purge'
                }
                Each permissions.secrets[*] {
                    Element | Must -Not -Be 'purge'
                }
                Each permissions.certificates[*] {
                    Element | Must -Not -Be 'purge'
                }
            }
        }
    }

    Effect (Param Effect)
}
