# Add a tag from the resource group to resources that don't have it. A resource that already has
# the tag keeps its own value. The same rule as the built-in policy "Inherit a tag from the
# resource group if missing", with Add so that an existing value is never replaced.
Policy 'tags-inherit-if-missing' {

    Properties @{
        DisplayName = 'Inherit a tag from the resource group if missing'
        Description = 'Adds the tag with its value from the resource group when a resource is created or updated without it.'
        Category    = 'Tags'
        Version     = '1.0.0'
        # Azure recommends Indexed for Modify policies on tags.
        Mode        = 'Indexed'
    }

    Parameter TagName -Type String -DisplayName 'Tag name' -Description 'The tag to inherit, for example CostCenter.'

    Resource * {

        # Only where the resource group has a value to inherit. A missing resource group tag
        # compares like an empty one, so this also skips resource groups without the tag.
        When {
            ResourceGroupTag (Param TagName) | Must -Not -Be ''
        }

        Require 'The resource has the tag' {
            Tag (Param TagName) | Must -Exist
        }
    }

    Modify -Role 'Tag Contributor' {
        Tag (Param TagName) | Add (ResourceGroupTag (Param TagName))
    }
}
