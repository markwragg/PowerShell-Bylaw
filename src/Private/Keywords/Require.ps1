function Require {
    <#
    .SYNOPSIS
        A named compliance requirement. Describes the compliant state; the compiler inverts it.

    .DESCRIPTION
        The statements in a Require all have to hold for a resource to be compliant. Bylaw
        inverts them into the policy's if condition, which finds the resources that break any of
        them, and adds the missing-field checks Azure needs (ADR-0004). A resource breaks the
        policy when it breaks any Require. In AuditIfNotExists and DeployIfNotExists, Require
        describes the related resource instead, and is emitted as the existence condition.

    .EXAMPLE
        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }

    .EXAMPLE
        Require 'Secure transfer and TLS 1.2' {
            Field supportsHttpsTrafficOnly | Must -Be $true
            Field minimumTlsVersion | Must -Be 'TLS1_2'
        }
    #>
    [CmdletBinding()]
    param(
        # What the requirement is, in words. It is kept in the source for readers and in error
        # messages, and isn't emitted.
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Description,

        # The statements that describe a compliant resource: Must, Each, Count, AnyOf and AllOf.
        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Require')
    $parent = Test-BylawParent -Keyword 'Require' -Allowed 'Resource', 'AuditIfNotExists', 'DeployIfNotExists' -Location $location
    if ($null -eq $parent) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Description)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1017' -Location $location -Message (
            "Require needs a description of the requirement, e.g. Require 'Public network access is disabled' { ... }."
        )
    }

    $node = [BylawRequirement]::new($Description)
    $node.Location = $location
    Invoke-BylawContainer -Keyword 'Require' -Node $node -Body $Body -Location $location
    $parent.Node.Requirements.Add($node)
}
