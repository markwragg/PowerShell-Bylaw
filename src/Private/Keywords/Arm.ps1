function Expr {
    <#
    .SYNOPSIS
        A raw ARM template expression, emitted verbatim, e.g. Expr "[field('location')]".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Text
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Expr')
    if ($null -eq (Get-BylawCurrentFrame)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $location -Message (
            "'Expr' can only be used inside a Policy block."
        )
        return
    }
    $expression = [BylawExpr]::new($Text)
    $expression.Location = $location
    $expression
}
