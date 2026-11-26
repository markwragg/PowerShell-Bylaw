# Tag, ResourceGroupTag (ADR-0020) and value conditions (ADR-0025).
Policy 'golden-tags' {

    Properties @{
        DisplayName = 'Golden: tags and value conditions'
        Category    = 'Tags'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter TagName -Type String
    Parameter Enforce -Type Boolean -Default $true

    Resource 'Microsoft.Storage/storageAccounts' {

        When {
            Param Enforce | Must -Be $true
            ResourceGroupTag (Param TagName) | Must -Not -Be ''
        }

        Require 'The tag matches the resource group' {
            Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName))
        }

        Require 'Cost center is set, and is not a placeholder' {
            Tag CostCenter | Must -Not -BeIn 'none', 'tbc'
            Tag CostCenter | Must -Not -Be ''
        }

        Require 'The environment tag is inherited, or the resource group has none' {
            AnyOf {
                ResourceGroupTag Environment | Must -Be ''
                Tag Environment | Must -Be (ResourceGroupTag Environment)
            }
        }

        Require 'At most ten tags' {
            Arm "[length(field('tags'))]" | Must -BeLessOrEqual 10
        }
    }

    Effect Audit
}
