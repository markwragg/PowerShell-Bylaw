# Keep a tag in step with the resource group: a resource whose value differs, or that has none,
# gets the resource group's value. The same rule as the built-in policy "Inherit a tag from the
# resource group".
Policy 'tags-inherit-from-resource-group' {

    Properties @{
        DisplayName = 'Inherit a tag from the resource group'
        Description = 'Sets the tag to its value on the resource group when a resource is created or updated.'
        Category    = 'Tags'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter TagName -Type String -DisplayName 'Tag name' -Description 'The tag to inherit, for example CostCenter.'

    Resource * {

        When {
            ResourceGroupTag (Param TagName) | Must -Not -Be ''
        }

        Require 'The tag matches the resource group' {
            Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName))
        }
    }

    Modify -Role 'Tag Contributor' {
        Tag (Param TagName) | AddOrReplace (ResourceGroupTag (Param TagName))
    }
}
