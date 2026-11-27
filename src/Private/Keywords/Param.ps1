function Param {
    <#
    .SYNOPSIS
        References a policy parameter by its DSL name; emits [parameters('<jsonName>')]. With
        -Length, its length: [length(parameters('<jsonName>'))].

    .EXAMPLE
        Field location | Must -BeIn (Param AllowedLocations)

    .EXAMPLE
        Count -Value (Param MandatoryTags) -Name tagName -Where {
            Tag (Current tagName) | Must -Exist
        } | Must -Be (Param MandatoryTags -Length)
    #>
    # 'param' is a language keyword only at the start of a scriptblock; as a command it parses
    # normally (verified with the parser). The name is part of the DSL spec.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidReservedWordsAsFunctionNames', '', Justification = 'DSL keyword required by the spec (ADR-0005).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        # The number of members of an Array parameter (or characters of a String one), as
        # Azure's length() function returns it (ADR-0020).
        [switch] $Length
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
    if ($Length) {
        $lengthValue = [BylawParamLength]::new($reference)
        $lengthValue.Location = $location
        return $lengthValue
    }
    $reference
}
