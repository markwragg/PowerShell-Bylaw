function Arm {
    <#
    .SYNOPSIS
        A raw ARM template expression, emitted verbatim, e.g. Arm "[field('location')]".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Text
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Arm')
    if ($null -eq (Get-BylawCurrentFrame)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $location -Message (
            "'Arm' can only be used inside a Policy block."
        )
        return
    }
    $expression = [BylawExpr]::new($Text)
    $expression.Location = $location
    $expression
}
