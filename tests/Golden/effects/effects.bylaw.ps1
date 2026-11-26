# DenyAction and Manual (ADR-0028): keywords that take the place of Effect.

# Resources tagged as protected can't be deleted, nor can their resource group. -CascadeBehavior
# needs Mode Indexed. A literal effect gets a generated effect parameter: DenyAction, Disabled.
Policy 'golden-denyaction-protected' {

    Properties @{
        DisplayName = 'Golden: protected storage accounts cannot be deleted'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Tag protected | Must -Be 'true'
        }
    }

    DenyAction Delete -CascadeBehavior Deny
}

# The effect as a parameter. Without -CascadeBehavior there is no cascadeBehaviors block.
Policy 'golden-denyaction-parameter' {

    Properties @{
        DisplayName = 'Golden: virtual machines cannot be deleted'
        Category    = 'Compute'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues DenyAction, Disabled -Default Disabled

    Resource 'Microsoft.Compute/virtualMachines' { }

    DenyAction Delete -Effect (Param Effect)
}

# Owners attest compliance. -DefaultState NonCompliant is emitted as Learn spells it.
Policy 'golden-manual' {

    Properties @{
        DisplayName = 'Golden: storage accounts are reviewed by hand'
        Category    = 'Storage'
        Version     = '1.0.0'
    }

    Resource 'Microsoft.Storage/storageAccounts' { }

    Manual -DefaultState NonCompliant
}

# Append (ADR-0029): a scalar field, and an object added to a [*] array. Each added field is
# checked by a Require. The details are an array, as Azure requires (BYL4010).
Policy 'golden-append' {

    Properties @{
        DisplayName = 'Golden: storage accounts use HTTPS and allow the office IP range'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'HTTPS only' {
            Field supportsHttpsTrafficOnly | Must -Be $true
        }
        Require 'The office IP range is allowed' {
            Each networkAcls.ipRules[*] {
                Field action | Must -Be 'Allow'
            }
        }
    }

    Append {
        Field supportsHttpsTrafficOnly | Add $true
        Field 'networkAcls.ipRules[*]' | Add ([ordered]@{ value = '40.40.40.0/24'; action = 'Allow' })
    }
}

# AuditIfNotExists (ADR-0030): the existence condition describes the related resource's compliant
# state and is emitted as written. The negated check gets an exists guard, so an extension without
# typeHandlerVersion doesn't count; -IfPresent makes autoUpgradeMinorVersion optional.
Policy 'golden-auditifnotexists' {

    Properties @{
        DisplayName = 'Golden: Windows virtual machines have the antimalware extension'
        Category    = 'Compute'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Compute/virtualMachines' {
        When {
            Field storageProfile.osDisk.osType | Must -Be 'Windows'
        }
    }

    AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' -EvaluationDelay AfterProvisioning {
        Require 'The antimalware extension is installed' {
            Field publisher | Must -Be 'Microsoft.Azure.Security'
            Field 'Microsoft.Compute/virtualMachines/extensions/type' | Must -Be 'IaaSAntimalware'
            Field typeHandlerVersion | Must -Not -BeLike '1.0*'
        }
        Require 'Minor versions upgrade automatically' {
            Field autoUpgradeMinorVersion | Must -Be $true -IfPresent
        }
    }
}

# A related resource outside the evaluated one: diagnostic settings, by name from a parameter.
Policy 'golden-auditifnotexists-diagnostics' {

    Properties @{
        DisplayName = 'Golden: key vaults send logs to a Log Analytics workspace'
        Category    = 'Monitoring'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues AuditIfNotExists, Disabled -Default AuditIfNotExists
    Parameter WorkspaceId -Type String -Description 'The Log Analytics workspace resource ID.'

    Resource 'Microsoft.KeyVault/vaults' { }

    AuditIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' -Effect (Param Effect) {
        Require 'Logs go to the workspace' {
            Field workspaceId | Must -Be (Param WorkspaceId)
            Each logs[*] {
                Field enabled | Must -Be $true -Strict
            }
        }
    }
}
