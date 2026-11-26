# Each: lenient element fields by default, -Strict, Element, nested Each, and When with several conditions.

Policy 'golden-each-strict' {
    Properties @{ DisplayName = 'Golden: Each, lenient and strict'; Category = 'Golden'; Version = '1.0.0'; Mode = 'All' }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Field kind | Must -Be 'StorageV2'
            Field networkAcls.defaultAction | Must -Be 'Deny'
        }

        Require 'IP rules allow a specific range' {
            Each networkAcls.ipRules[*] {
                Field action | Must -Be 'Allow'
                Field value | Must -Not -BeLike '*/0'
            }
        }

        Require 'Virtual network rules are complete' {
            Each networkAcls.virtualNetworkRules[*] {
                Field action | Must -Be 'Allow' -Strict
                Field id | Must -Not -ContainText '/subscriptions/00000000-0000-0000-0000-000000000000/' -Strict
            }
        }
    }

    Effect Deny
}

Policy 'golden-each-nested' {
    Properties @{ DisplayName = 'Golden: nested Each with plain values'; Category = 'Golden'; Version = '1.0.0'; Mode = 'All' }

    Parameter BlockedPorts -Type Array -Default '22', '3389', '*'

    Resource 'Microsoft.Network/networkSecurityGroups' {
        Require 'Rules use known protocols and no blocked ports' {
            Each securityRules[*] {
                Field protocol | Must -BeIn 'Tcp', 'Udp', 'Icmp'
                Field destinationPortRange | Must -Not -BeIn (Param BlockedPorts)
                Each destinationPortRanges[*] {
                    Element | Must -Not -BeIn (Param BlockedPorts)
                }
                Each sourceAddressPrefixes[*] {
                    Element | Must -Not -Be '*'
                }
            }
        }
    }

    Effect Audit
}
