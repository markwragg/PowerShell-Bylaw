# Storage accounts tagged as protected can't be deleted, and neither can the resource group that
# holds them. DenyAction blocks the delete request; resources that don't match When are unaffected.

Policy 'storage-protect-from-deletion' {

    Properties @{
        DisplayName = 'Protected storage accounts cannot be deleted'
        Description = 'Blocks deleting a storage account tagged protection=locked, and deleting its resource group.'
        Category    = 'Storage'
        Version     = '1.0.0'
        # -CascadeBehavior needs Mode Indexed.
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Tag protection | Must -Be 'locked'
        }
    }

    DenyAction Delete -CascadeBehavior Deny
}
