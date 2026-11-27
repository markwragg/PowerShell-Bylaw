# Storage policies from this folder's neighbours, assigned together. The initiative's Effect is
# passed to the policies that take one, so an assignment sets it once for all of them. Members
# from the build are checked against those policies when the build runs (ADR-0034).

Initiative 'storage-baseline' {

    Properties @{
        DisplayName = 'Storage account baseline'
        Description = 'Storage accounts are private, use TLS 1.2 or later, and require secure transfer.'
        Category    = 'Storage'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter AllowedTlsVersions @{
        Type          = 'Array'
        AllowedValues = 'TLS1_2', 'TLS1_3'
        Default       = 'TLS1_2', 'TLS1_3'
        DisplayName   = 'Allowed TLS versions'
    }

    PolicyDefinition 'storage-deny-public-network-access' -Parameters @{
        effect = Param Effect
    }

    PolicyDefinition 'storage-require-secure-transfer' -Parameters ([ordered]@{
            effect             = Param Effect
            allowedTlsVersions = Param AllowedTlsVersions
        })

    # Its effect is a literal Append, so EPAC output gives it an effect parameter with a default:
    # nothing needs to be passed.
    PolicyDefinition 'storage-append-secure-transfer'
}
