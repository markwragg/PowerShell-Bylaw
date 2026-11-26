# Plain JSON output (ADR-0027): built with -Format PlainJson. The policy is emitted as written.

# The minimum: a literal effect stays literal, and empty description, metadata and parameters are
# left out. No Category or Version is needed.
Policy 'plain-literal-effect' {

    Properties @{ DisplayName = 'Plain: literal effect' }

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }
    }

    Effect Deny
}

# Parameters keep only the display names and descriptions that were written.
Policy 'plain-parameters' {

    Properties @{
        DisplayName = 'Plain: parameters'
        Description = 'Storage accounts use an allowed minimum TLS version.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
        Metadata    = @{ owner = 'platform-team' }
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter AllowedTlsVersions -Type Array -Default @('TLS1_2')
    Parameter @{
        Name        = 'ExemptTag'
        Type        = 'String'
        DisplayName = 'Exemption tag'
        Description = 'Resources with this tag are not evaluated.'
        Default     = 'tls-exempt'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Tag (Param ExemptTag) | Must -Not -Exist
        }
        Require 'TLS version is allowed' {
            Field minimumTlsVersion | Must -BeIn (Param AllowedTlsVersions)
        }
    }

    Effect (Param Effect)
}

# A Modify block keeps its literal effect too, with the same details block as EPAC.
Policy 'plain-modify' {

    Properties @{
        DisplayName = 'Plain: inherit the CostCenter tag'
        Mode        = 'Indexed'
    }

    Resource * {
        When {
            ResourceGroupTag CostCenter | Must -Not -Be ''
        }
        Require 'CostCenter matches the resource group' {
            Tag CostCenter | Must -Be (ResourceGroupTag CostCenter)
        }
    }

    Modify -Role 'Tag Contributor' {
        Tag CostCenter | AddOrReplace (ResourceGroupTag CostCenter)
    }
}

# DenyAction and Manual keep their literal effects.
Policy 'plain-denyaction' {

    Properties @{
        DisplayName = 'Plain: protected storage accounts cannot be deleted'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Tag protected | Must -Be 'true'
        }
    }

    DenyAction Delete -CascadeBehavior Allow
}

Policy 'plain-manual' {

    Properties @{ DisplayName = 'Plain: storage accounts are reviewed by hand' }

    Resource 'Microsoft.Storage/storageAccounts' { }

    Manual
}
