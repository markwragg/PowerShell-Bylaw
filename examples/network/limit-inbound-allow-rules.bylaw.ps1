# A network security group has at most a few rules that allow inbound traffic. A field count with
# -Where counts the rules that match; the -Where block is a selection, so it is emitted as written.

Policy 'network-limit-inbound-allow-rules' {

    Properties @{
        DisplayName = 'Network security groups have few inbound allow rules'
        Category    = 'Network'
        Version     = '1.0.0'
    }

    Parameter MaxInboundAllowRules -Type Integer -Default 5 -Description 'The most inbound allow rules a network security group may have.'

    Resource 'Microsoft.Network/networkSecurityGroups' {
        Require 'Few rules allow inbound traffic' {
            Count securityRules[*] -Where {
                Field direction | Must -Be 'Inbound'
                Field access | Must -Be 'Allow'
            } | Must -BeLessOrEqual (Param MaxInboundAllowRules)
        }
    }

    Effect Audit
}
