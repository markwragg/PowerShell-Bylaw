function Param {
    <#
    .SYNOPSIS
        References a policy parameter by its DSL name; emits [parameters('<jsonName>')].
    #>
    # 'param' is a language keyword only at the start of a scriptblock; as a command it parses
    # normally (verified with the parser). The name is part of the DSL spec.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidReservedWordsAsFunctionNames', '', Justification = 'DSL keyword required by the spec (ADR-0005).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Param')
    if ($null -eq (Get-BylawCurrentFrame)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $location -Message (
            "'Param' can only be used inside a Policy block."
        )
        return
    }
    $reference = [BylawParamRef]::new($Name)
    $reference.Location = $location
    $reference
}
