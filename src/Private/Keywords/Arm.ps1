function Arm {
    <#
    .SYNOPSIS
        A raw ARM template expression, emitted verbatim, e.g. Arm "[field('location')]".

    .DESCRIPTION
        Use Arm where Bylaw has no keyword for an expression: as a value to compare with, a value to
        set in Modify, a list to count, or the subject of a value condition. The text is emitted
        exactly as written, so it must be a complete expression in square brackets.

    .EXAMPLE
        Field location | Must -Be (Arm '[resourceGroup().location]')

    .EXAMPLE
        Count -Value (Param TagNames) -Name tagName | Must -Be (Arm "[length(parameters('tagNames'))]")
    #>
    [CmdletBinding()]
    param(
        # The expression, including its square brackets.
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
