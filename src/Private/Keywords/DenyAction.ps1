# DenyAction and Manual (ADR-0028). Each takes the place of Effect, with parameters for the details.

$script:BylawDenyActionNames = @('delete')
$script:BylawCascadeBehaviors = @('deny', 'allow')
# -DefaultState as written -> as emitted, in the spellings Learn uses.
$script:BylawManualDefaultStates = [ordered]@{
    Unknown      = 'Unknown'
    Compliant    = 'Compliant'
    NonCompliant = 'Non-compliant'
}

function DenyAction {
    <#
    .SYNOPSIS
        The denyAction effect: blocks an action on matching resources. Use it instead of Effect.

    .EXAMPLE
        DenyAction Delete -CascadeBehavior Deny
    #>
    [CmdletBinding()]
    param(
        # The action to block. Delete is the only action Azure supports.
        [Parameter(Position = 0)]
        [string] $Action,

        # Whether deleting the resource group is blocked too: Deny (Azure's default) or Allow.
        # Needs Mode = 'Indexed'.
        [string] $CascadeBehavior,

        # The effect as a parameter, (Param Effect). Without it, the effect is DenyAction.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'DenyAction')
    $frame = Test-BylawParent -Keyword 'DenyAction' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawEffectKeyword -Frame $frame -Keyword 'DenyAction' -Location $location)) {
        return
    }

    $effectValue = Get-BylawKeywordEffectValue -Keyword 'DenyAction' -Bound $PSBoundParameters -Location $location
    $valid = $null -ne $effectValue

    $actionName = $script:BylawDenyActionNames | Where-Object { $_ -eq $Action } | Select-Object -First 1
    if (-not $actionName) {
        $written = if ($Action) { "'$Action' is not an action DenyAction can block" } else { 'DenyAction needs the action to block' }
        Add-BylawDiagnostic -Severity Error -Code 'BYL1033' -Location $location -Message (
            "$written. Delete is the only action Azure supports: DenyAction Delete."
        )
        $valid = $false
    }
    $cascade = $null
    if ($PSBoundParameters.ContainsKey('CascadeBehavior')) {
        $cascade = $script:BylawCascadeBehaviors | Where-Object { $_ -eq $CascadeBehavior } | Select-Object -First 1
        if (-not $cascade) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1034' -Location $location -Message (
                "-CascadeBehavior '$CascadeBehavior' is not valid. Use Deny or Allow."
            )
            $valid = $false
        }
    }
    if (-not $valid) {
        return
    }

    $node = [BylawDenyAction]::new($effectValue)
    $node.Location = $location
    $node.ActionNames = [string[]] @($actionName)
    $node.CascadeBehavior = $cascade
    $frame.Node.Effect = $node
}

function Manual {
    <#
    .SYNOPSIS
        The manual effect: resource owners attest compliance. Use it instead of Effect.

    .EXAMPLE
        Manual -DefaultState Unknown
    #>
    [CmdletBinding()]
    param(
        # The compliance state before anyone attests: Unknown (Azure's default), Compliant or
        # NonCompliant.
        [string] $DefaultState,

        # The effect as a parameter, (Param Effect). Without it, the effect is Manual.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Manual')
    $frame = Test-BylawParent -Keyword 'Manual' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawEffectKeyword -Frame $frame -Keyword 'Manual' -Location $location)) {
        return
    }

    $effectValue = Get-BylawKeywordEffectValue -Keyword 'Manual' -Bound $PSBoundParameters -Location $location
    $valid = $null -ne $effectValue

    $state = $null
    if ($PSBoundParameters.ContainsKey('DefaultState')) {
        $key = $script:BylawManualDefaultStates.Keys | Where-Object { $_ -eq $DefaultState } | Select-Object -First 1
        if ($key) {
            $state = $script:BylawManualDefaultStates[$key]
        }
        else {
            $hint = if ($DefaultState -eq 'Non-compliant') { " Write NonCompliant; it's emitted as 'Non-compliant'." } else { '' }
            Add-BylawDiagnostic -Severity Error -Code 'BYL1035' -Location $location -Message (
                "-DefaultState '$DefaultState' is not valid. Use Unknown, Compliant or NonCompliant.$hint"
            )
            $valid = $false
        }
    }
    if (-not $valid) {
        return
    }

    $node = [BylawManual]::new($effectValue)
    $node.Location = $location
    $node.DefaultState = $state
    $frame.Node.Effect = $node
}

function Get-BylawKeywordEffectValue {
    # The effect of a keyword in place of Effect: its own name, or the -Effect parameter or
    # expression. Records BYL1030 and returns $null for a literal -Effect.
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Bound,
        [BylawSourceLocation] $Location
    )

    if (-not $Bound.ContainsKey('Effect')) {
        $literal = [BylawLiteral]::new($Keyword)
        $literal.Location = $Location
        return $literal
    }
    $value = $Bound['Effect']
    if ($value -is [BylawParamRef] -or $value -is [BylawExpr]) {
        return $value
    }
    Add-BylawDiagnostic -Severity Error -Code 'BYL1030' -Location $Location -Message (
        "$Keyword -Effect takes a parameter, e.g. -Effect (Param Effect). Without -Effect, the effect is $Keyword."
    )
    $null
}
