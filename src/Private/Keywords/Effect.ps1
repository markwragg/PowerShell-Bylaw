function Effect {
    <#
    .SYNOPSIS
        The policy effect: a literal such as Deny, or (Param Effect).

    .DESCRIPTION
        Effect is for the effects without details: Audit, Deny and Disabled. The others have their
        own keywords: Modify, Append, DenyAction, Manual, AuditIfNotExists and DeployIfNotExists.
        With a literal effect, EPAC output gets an effect parameter with that default, so an
        assignment can still change it.

    .EXAMPLE
        Effect Deny

    .EXAMPLE
        Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
        Effect (Param Effect)
    #>
    [CmdletBinding()]
    param(
        # Audit, Deny or Disabled, or (Param Name) for a parameter that holds the effect.
        [Parameter(Mandatory, Position = 0)]
        [object] $Value
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Effect')
    $frame = Test-BylawParent -Keyword 'Effect' -Allowed 'Policy' -Location $location
    if ($null -eq $frame) {
        return
    }
    if (-not (Test-BylawEffectKeyword -Frame $frame -Keyword 'Effect' -Location $location)) {
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
