# AnyOf and AllOf: a rule is acceptable if any one of the alternatives holds.
# Rules can also be created as separate Microsoft.Network/networkSecurityGroups/securityRules
# resources. A complete policy needs a second Policy for that type.
Policy 'network-deny-inbound-from-internet' {

    Properties @{
        DisplayName = 'Network security groups should not allow inbound traffic from the internet'
        Description = 'Denies network security groups with a rule that allows inbound traffic from any address or the Internet service tag.'
        Category    = 'Network'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.Network/networkSecurityGroups' {

        Require 'No rule allows inbound traffic from the internet' {
            Each securityRules[*] {
                AnyOf {
                    Field direction | Must -Not -Be 'Inbound'
                    Field access | Must -Not -Be 'Allow'
                    AllOf {
                        Field sourceAddressPrefix | Must -Not -BeIn '*', 'Internet'
                        Each sourceAddressPrefixes[*] {
                            Element | Must -Not -BeIn '*', 'Internet'
                        }
                    }
                }
            }
        }
    }

    Effect (Param Effect)
}
