# Key vaults send their audit logs to a Log Analytics workspace. If a vault has no diagnostic
# setting that does, a remediation task deploys one from the template next to this file. The
# effect parameter also allows AuditIfNotExists, to report without deploying.

Policy 'key-vault-deploy-diagnostics' {

    Properties @{
        DisplayName = 'Key vaults send audit logs to a Log Analytics workspace'
        Category    = 'Key Vault'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues DeployIfNotExists, AuditIfNotExists, Disabled -Default DeployIfNotExists
    Parameter WorkspaceId -Type String -Description 'Resource ID of the Log Analytics workspace.'

    Resource 'Microsoft.KeyVault/vaults' { }

    # Log Analytics Contributor and Monitoring Contributor, by ID: the bundled role map doesn't
    # have them. Update-BylawRoleCache adds every built-in role, so names would work too.
    $roles = '92aaf0da-9dab-42b6-94a3-d43ce8d16293', '749f88d5-cbae-40b8-bcfc-e573ddc772fa'

    DeployIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' -Role $roles -Effect (Param Effect) {
        Require 'A diagnostic setting sends logs to the workspace' {
            Field workspaceId | Must -Be (Param WorkspaceId)
            Field logs.enabled | Must -Be $true
        }

        Deployment -TemplateFile ./templates/diagnostic-settings.json -Parameters ([ordered]@{
                vaultName   = Arm "[field('name')]"
                workspaceId = Param WorkspaceId
            })
    }
}
