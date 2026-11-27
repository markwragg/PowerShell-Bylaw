# Count and Current (ADR-0032): the count patterns of the Azure Landing Zones Library.

# An empty-array check: a storage account with a firewall must have at least one IP rule. The
# count is inverted in Require (greater 0 becomes lessOrEquals 0) and never guarded.
Policy 'golden-count-empty-array' {

    Properties @{
        DisplayName = 'Golden: storage firewalls have at least one IP rule'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        When {
            Field networkAcls.defaultAction | Must -Be 'Deny'
        }
        Require 'At least one IP rule' {
            Count networkAcls.ipRules[*] | Must -BeGreaterThan 0
        }
    }

    Effect Audit
}

# A value count over a parameter, with the member as a value: the name matches one of the patterns.
Policy 'golden-count-name-patterns' {

    Properties @{
        DisplayName = 'Golden: resource names match an allowed pattern'
        Category    = 'General'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter NamePatterns -Type Array -Default @('rg-*', 'st*')

    Resource * {
        Require 'The name matches an allowed pattern' {
            Count -Value (Param NamePatterns) -Name pattern -Where {
                Field name | Must -BeLike (Current pattern)
            } | Must -BeGreaterThan 0
        }
    }

    Effect Deny
}

# A value count compared with the length of its list (ADR-0020): the name matches every pattern.
Policy 'golden-count-every-pattern' {

    Properties @{
        DisplayName = 'Golden: resource names match every required pattern'
        Category    = 'General'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter NamePatterns -Type Array -Default @('*-prod-*', '*-uks-*')

    Resource * {
        Require 'The name matches every pattern' {
            Count -Value (Param NamePatterns) -Name pattern -Where {
                Field name | Must -BeLike (Current pattern)
            } | Must -Be (Param NamePatterns -Length)
        }
    }

    Effect Deny
}

# A nested count: no security rule allows inbound traffic from the internet on a management port.
# The -Where blocks select what to count and are emitted as written; field names are relative to
# each element, and Element is a member of a primitive array.
Policy 'golden-count-nested' {

    Properties @{
        DisplayName = 'Golden: no rule opens management ports to the internet'
        Category    = 'Network'
        Version     = '1.0.0'
    }

    Parameter ManagementPorts -Type Array -Default @('22', '3389')

    Resource 'Microsoft.Network/networkSecurityGroups' {
        Require 'No inbound rule opens a management port to the internet' {
            Count securityRules[*] -Where {
                Field direction | Must -Be 'Inbound'
                Field access | Must -Be 'Allow'
                Field sourceAddressPrefix | Must -BeIn '*', 'Internet'
                AnyOf {
                    Field destinationPortRange | Must -BeIn (Param ManagementPorts)
                    Count destinationPortRanges[*] -Where {
                        Element | Must -BeIn (Param ManagementPorts)
                    } | Must -BeGreaterThan 0
                }
            } | Must -Be 0
        }
    }

    Effect Deny
}
