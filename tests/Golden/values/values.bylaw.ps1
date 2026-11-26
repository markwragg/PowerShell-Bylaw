# Values: parameters, ARM expressions, booleans and numbers; Properties with only the required keys.

Policy 'golden-values' {
    Properties @{ DisplayName = 'Golden: values'; Category = 'Golden'; Version = '2.1.0-preview'; Preview = $true }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter NamePattern -Type String -Default 'kv-*' -DisplayName 'Name pattern' -Description 'A like pattern for vault names.'
    Parameter RetentionDays -Type Integer -AllowedValues 7, 30, 90 -Default 90
    Parameter RequireRbac -Type Boolean -Default $true -DisplayName 'Require RBAC'

    Resource 'Microsoft.KeyVault/vaults' {
        Require 'Values from parameters' {
            Field name | Must -BeLike (Param NamePattern)
            Field softDeleteRetentionInDays | Must -BeGreaterOrEqual (Param RetentionDays)
            Field enableRbacAuthorization | Must -Be (Param RequireRbac)
        }

        Require 'Values from ARM expressions' {
            Field name | Must -BeLike (Arm "[concat(resourceGroup().name, '-*')]")
            Field sku.name | Must -Be (Arm "[toLower('Premium')]")
        }

        Require 'Literal values' {
            Field enablePurgeProtection | Must -Be $true
            Field enableSoftDelete | Must -Not -Be $false
            Field softDeleteRetentionInDays | Must -BeLessOrEqual 90
        }
    }

    Effect (Param Effect)
}
