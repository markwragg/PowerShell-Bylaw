# A control that can't be checked automatically: someone reviews each subscription's privileged
# access and records the result as an attestation. Until they do, the subscription is non-compliant.

Policy 'general-attest-access-review' {

    Properties @{
        DisplayName = 'Privileged access to subscriptions is reviewed every quarter'
        Description = 'Owners attest that the quarterly review of privileged role assignments has been done.'
        Category    = 'General'
        Version     = '1.0.0'
    }

    Resource * {
        When {
            Field type | Must -Be 'Microsoft.Resources/subscriptions'
        }
    }

    Manual -DefaultState NonCompliant
}
