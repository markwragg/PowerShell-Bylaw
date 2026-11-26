# When narrows the policy to Linux VMs; -BeLike checks a name pattern.
Policy 'compute-linux-vm-standards' {

    Properties @{
        DisplayName = 'Linux virtual machines should follow the platform standards'
        Description = 'Audits Linux virtual machines that use password sign-in, an unapproved image publisher or a VM size outside the D series.'
        Category    = 'Compute'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter ApprovedPublishers -Type Array -Default Canonical, RedHat -DisplayName 'Approved image publishers'

    Resource 'Microsoft.Compute/virtualMachines' {

        When {
            Field storageProfile.osDisk.osType | Must -Be 'Linux'
        }

        Require 'Sign-in uses SSH keys only' {
            Field osProfile.linuxConfiguration.disablePasswordAuthentication | Must -Be $true
        }

        Require 'The image comes from an approved publisher' {
            Field imagePublisher | Must -BeIn (Param ApprovedPublishers)
        }

        Require 'The VM size is a D-series size' {
            Field hardwareProfile.vmSize | Must -BeLike 'Standard_D*'
        }
    }

    Effect (Param Effect)
}
