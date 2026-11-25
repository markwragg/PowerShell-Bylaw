function Effect {
    <#
    .SYNOPSIS
        The policy effect: a literal such as Deny, or (Param Effect).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $Value
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Effect')
    $frame = Test-BylawParent -Keyword 'Effect' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawSingleton -Frame $frame -Keyword 'Effect' -Location $location)) {
        return
    }

    if (-not ($Value -is [string] -or $Value -is [BylawParamRef] -or $Value -is [BylawExpr])) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1019' -Location $location -Message (
            'Effect takes an effect name (e.g. Effect Deny) or a parameter (e.g. Effect (Param Effect)).'
        )
        return
    }

    $effect = [BylawEffect]::new((ConvertTo-BylawValue -Value $Value -Location $location))
    $effect.Location = $location
    $frame.Node.Effect = $effect
}
