function Require {
    <#
    .SYNOPSIS
        A named compliance requirement. Describes the compliant state; the compiler inverts it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Description,

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
