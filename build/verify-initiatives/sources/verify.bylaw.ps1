# Policies and initiatives for Invoke-InitiativeVerification.ps1. Every name starts with
# bylaw-verify so the script can remove what it deployed. Built with -Format PlainJson and a
# subscription as the definition scope.

# A policy with an effect parameter and a required parameter.
Policy 'bylaw-verify-tier' {

    Properties @{
        DisplayName = 'Bylaw verify: storage access tier'
        Category    = 'Bylaw verification'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Disabled -Default Audit
    Parameter Tier -AllowedValues Hot, Cool

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'The access tier is the chosen one' {
            Field accessTier | Must -Be (Param Tier)
        }
    }

    Effect (Param Effect)
}

# A policy with a literal effect: in plain JSON it has no effect parameter.
Policy 'bylaw-verify-tags' {

    Properties @{
        DisplayName = 'Bylaw verify: mandatory tags'
        Category    = 'Bylaw verification'
        Version     = '1.2.0'
        Mode        = 'Indexed'
    }

    Parameter MandatoryTags -Type Array -Default @('CostCenter')

    Resource * {
        Require 'Every mandatory tag is set' {
            Count -Value (Param MandatoryTags) -Name tagName -Where {
                Tag (Current tagName) | Must -Exist
            } | Must -Be (Arm "[length(parameters('mandatoryTags'))]")
        }
    }

    Effect Audit
}

# Members from the build with full IDs at the subscription, the same policy twice, a built-in
# pinned to its major version, groups with every property, and parameters passed through.
Initiative 'bylaw-verify-set' {

    Properties @{
        DisplayName = 'Bylaw verify: initiative'
        Description = 'Checks that Azure accepts a plain JSON initiative built by Bylaw.'
        Category    = 'Bylaw verification'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Disabled -Default Audit
    Parameter Tier -AllowedValues Hot, Cool -Default Hot

    DefinitionGroup 'Storage' -DisplayName 'Storage' -Category 'Bylaw verification' -Description 'Storage policies.'
    DefinitionGroup 'Tags' -DisplayName 'Tags' -Category 'Bylaw verification' -Description 'Tagging policies.'

    PolicyDefinition 'bylaw-verify-tier' -Group Storage -Parameters ([ordered]@{
            effect = Param Effect
            tier   = Param Tier
        })

    PolicyDefinition 'bylaw-verify-tags' -ReferenceId 'tags-default' -Group Tags

    PolicyDefinition 'bylaw-verify-tags' -ReferenceId 'tags-environment' -Group Tags -Parameters @{
        mandatoryTags = @('Environment')
    }

    PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' -ReferenceId 'inherit-cost-center' -Version '1.*.*' -Group Tags -Parameters @{
        tagName = 'CostCenter'
    }
}

# A member from the build pinned with -Version. Bylaw warns (BYL3129) because it emits Version only
# as metadata.version; this records what Azure does with the pin. It is a separate initiative, so
# if Azure rejects it the other one is still deployed.
Initiative 'bylaw-verify-set-pinned' {

    Properties @{
        DisplayName = 'Bylaw verify: member from the build with definitionVersion'
        Category    = 'Bylaw verification'
        Version     = '1.0.0'
    }

    PolicyDefinition 'bylaw-verify-tags' -Version '1.*.*'
}
