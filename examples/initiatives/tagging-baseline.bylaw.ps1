# A tagging baseline: resources have the mandatory tags, and inherit two of them from their resource
# group. The inherit policy is included twice, once per tag, with a reference ID for each. A
# built-in policy is included by ID, pinned to its major version.

Initiative 'tagging-baseline' {

    Properties @{
        DisplayName = 'Tagging baseline'
        Category    = 'Tags'
        Version     = '1.0.0'
    }

    Parameter MandatoryTags @{
        Type        = 'Array'
        Default     = 'CostCenter', 'Owner'
        Description = 'Tags every resource must have.'
    }

    PolicyDefinition 'tags-require-mandatory-tags' -Parameters @{
        mandatoryTags = Param MandatoryTags
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
