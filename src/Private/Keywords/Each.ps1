function Each {
    <#
    .SYNOPSIS
        Every element of an array must satisfy the block. Compiles to count/where (ADR-0002).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Each')
    $parent = Test-BylawParent -Keyword 'Each' -Allowed 'Require', 'Each' -Location $location
    if ($null -eq $parent) {
        return
    }
    if (-not $Path.EndsWith('[*]')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1016' -Location $location -Message (
            "Each needs an array path ending in [*], e.g. Each networkAcls.ipRules[*] { ... } (got '$Path')."
        )
        return
    }

    $field = [BylawFieldRef]::new($Path)
    $field.Location = $location
    $node = [BylawEach]::new($field)
    $node.Location = $location
    Invoke-BylawContainer -Keyword 'Each' -Node $node -Body $Body -Location $location
    $parent.Node.Children.Add($node)
}
