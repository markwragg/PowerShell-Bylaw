# A tagging baseline: resources have a required tag, and inherit two tags from their resource
# group. The inherit policy is included twice, once per tag, with a reference ID for each. A
# built-in policy is included by ID, pinned to its major version.

Initiative 'tagging-baseline' {

    Properties @{
        DisplayName = 'Tagging baseline'
        Category    = 'Tags'
        Version     = '1.0.0'
    }

    Parameter RequiredTag @{
        Default     = 'CostCenter'
        Description = 'The tag every resource must have.'
    }

    PolicyDefinition 'general-require-tag' -Parameters @{
        tagName = Param RequiredTag
    }

    PolicyDefinition 'tags-inherit-from-resource-group' -ReferenceId 'inherit-cost-center' -Parameters @{
        tagName = 'CostCenter'
    }

    PolicyDefinition 'tags-inherit-from-resource-group' -ReferenceId 'inherit-owner' -Parameters @{
        tagName = 'Owner'
    }

    # Built-in: "Require a tag on resource groups".
    PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025' -ReferenceId 'require-environment-on-resource-groups' -Version '1.*.*' -Parameters @{
        tagName = 'Environment'
    }
}
