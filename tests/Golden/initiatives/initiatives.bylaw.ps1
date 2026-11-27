# Initiatives (ADR-0033, ADR-0035): members from this build by name, and built-in policies by ID.
# Members from the build are checked against the policies they name once every file has compiled
# (ADR-0034).

# The ALZ shape: initiative parameters passed straight through to members, a built-in member pinned
# to its major version, and a policy included twice with different reference IDs. In EPAC output,
# members from the build are referenced by policyDefinitionName, and groups keep only their name
# and additionalMetadataId.
Policy 'golden-initiative-public-network' {

    Properties @{
        DisplayName = 'Golden: storage accounts disable public network access'
        Category    = 'Storage'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }
    }

    Effect (Param Effect)
}

Initiative 'golden-initiative' {

    Properties @{
        DisplayName = 'Golden: storage and tagging baseline'
        Description = 'Storage accounts are private, and resources carry the mandatory tags.'
        Category    = 'General'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter MandatoryTags @{
        Type        = 'Array'
        Default     = 'CostCenter', 'Owner'
        Description = 'Tags every resource must have.'
    }

    DefinitionGroup 'Storage' -AdditionalMetadataId '/providers/Microsoft.PolicyInsights/policyMetadata/golden-storage'
    DefinitionGroup 'Tags'

    PolicyDefinition 'golden-initiative-public-network' -Group Storage -Parameters @{
        effect = Param Effect
    }

    # golden-count-mandatory-tags has a literal effect, so EPAC output gives it an effect parameter.
    PolicyDefinition 'golden-count-mandatory-tags' -Group Tags -Parameters ([ordered]@{
            mandatoryTags = Param MandatoryTags
            effect        = Param Effect
        })

    # The same policy again, with a fixed list.
    PolicyDefinition 'golden-count-mandatory-tags' -ReferenceId 'golden-count-environment-tag' -Group Tags -Parameters @{
        mandatoryTags = @('Environment')
    }

    PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' -ReferenceId 'InheritCostCenter' -Version '1.*.*' -Group Tags -Parameters @{
        tagName = 'CostCenter'
    }
}

# The minimum: one built-in member and nothing else.
Initiative 'golden-initiative-minimal' {

    Properties @{
        DisplayName = 'Golden: one built-in policy'
        Category    = 'Tags'
        Version     = '1.0.0'
    }

    PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' -ReferenceId 'InheritCostCenter' -Parameters @{
        tagName = 'CostCenter'
    }
}
