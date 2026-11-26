# Append block (ADR-0029). Append takes the place of Effect; its Add operations take the field from
# the pipeline, as in Modify.

function Append {
    <#
    .SYNOPSIS
        The append effect: fields to add to a create or update request. Use it instead of Effect.

    .EXAMPLE
        Append {
            Field supportsHttpsTrafficOnly | Add $true
            Field 'networkAcls.ipRules[*]' | Add @{ value = '40.40.40.40'; action = 'Allow' }
        }
    #>
    [CmdletBinding()]
    param(
        # The Add operations.
        [Parameter(Position = 0)]
        [scriptblock] $Body,

        # The effect as a parameter, (Param Effect). Without it, the effect is Append.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Append')
    $frame = Test-BylawParent -Keyword 'Append' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawEffectKeyword -Frame $frame -Keyword 'Append' -Location $location)) {
        return
    }

    $effectValue = Get-BylawKeywordEffectValue -Keyword 'Append' -Bound $PSBoundParameters -Location $location
    $valid = $null -ne $effectValue
    if ($null -eq $Body) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $location -Message (
            'Append needs a block of Add operations, e.g. Append { Field supportsHttpsTrafficOnly | Add $true }.'
        )
        return
    }

    $node = [BylawAppend]::new($effectValue)
    $node.Location = $location

    $diagnosticsBefore = $script:BylawDiagnostics.Count
    $appendFrame = Enter-BylawFrame -Keyword 'Append' -Node $node
    try {
        Invoke-BylawBlock -Body $Body
    }
    finally {
        Exit-BylawFrame -Frame $appendFrame
    }
    $innerErrors = @($script:BylawDiagnostics | Select-Object -Skip $diagnosticsBefore | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count
    if ($node.Operations.Count -eq 0 -and $innerErrors -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $location -Message (
            "'Append' block is empty. Add at least one operation, e.g. Field supportsHttpsTrafficOnly | Add `$true."
        )
    }
    if ($valid) {
        $frame.Node.Effect = $node
    }
}
