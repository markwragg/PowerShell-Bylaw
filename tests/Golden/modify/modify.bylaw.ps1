# Modify (ADR-0024): every operation, roles in each form, -ConflictEffect, -Condition, a declared
# effect parameter, and identity.type.

# All three operations, in the order written, with roles given by name, GUID and full ID, and the
# generated effect parameter.
Policy 'golden-modify-operations' {

    Properties @{ DisplayName = 'Golden: Modify operations'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'Environment is Production' {
            Tag Environment | Must -Be 'Production'
        }
        Require 'Owner is set' {
            Tag Owner | Must -Exist
        }
        Require 'No temporary tag' {
            Tag Temporary | Must -Not -Exist
        }
    }

    Modify -Role 'tag contributor', 'b24988ac-6180-42a0-ab88-20f7382dd24c', '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' {
        Tag Environment | AddOrReplace 'Production'
        Tag Owner | Add 'unassigned'
        Tag Temporary | Remove
    }
}

# A declared effect parameter, a tag name parameter, a parameter value, and a condition on an
# operation. -ConflictEffect is emitted in lower case.
Policy 'golden-modify-parameters' {

    Properties @{ DisplayName = 'Golden: Modify with parameters'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Parameter Effect -AllowedValues Modify, Disabled -Default Disabled
    Parameter TagName -Type String
    Parameter TagValue -Type String
    Parameter Enforce -Type Boolean -Default $true

    Resource 'Microsoft.KeyVault/vaults' {
        Require 'The tag has the required value' {
            Tag (Param TagName) | Must -Be (Param TagValue)
        }
    }

    Modify -Role 'Tag Contributor' -ConflictEffect Disabled -Effect (Param Effect) {
        Tag (Param TagName) | AddOrReplace (Param TagValue) -Condition (Arm "[parameters('enforce')]")
    }
}

# identity.type can be modified on virtual machines. It isn't an alias, so no conflict effect is
# needed.
Policy 'golden-modify-identity' {

    Properties @{ DisplayName = 'Golden: Modify identity.type'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Resource 'Microsoft.Compute/virtualMachines' {
        Require 'The virtual machine has a system-assigned identity' {
            Field identity.type | Must -ContainText 'SystemAssigned'
        }
    }

    Modify -Role 'Virtual Machine Contributor' {
        Field identity.type | AddOrReplace 'SystemAssigned'
    }
}
