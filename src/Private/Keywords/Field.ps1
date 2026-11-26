function Field {
    <#
    .SYNOPSIS
        A field reference, resolved to a full alias at compile time. Pipe it to Must.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        # Accept an alias that is not in the alias snapshot (ADR-0008).
        [switch] $AllowUnknownAlias
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Field')
    $frame = Test-BylawParent -Keyword 'Field' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf' -Location $location
    if ($null -eq $frame) {
        return
    }

    $field = [BylawFieldRef]::new($Name)
    $field.Location = $location
    $field.AllowUnknownAlias = $AllowUnknownAlias.IsPresent
    $frame.PendingFields.Add($field)
    $field
}

function Element {
    <#
    .SYNOPSIS
        The current element of a primitive array inside Each. Pipe it to Must.
    #>
    [CmdletBinding()]
    param()

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Element')
    $frame = Test-BylawParent -Keyword 'Element' -Allowed 'Each', 'AnyOf', 'AllOf' -Location $location
    if ($null -eq $frame) {
        return
    }
    if (-not (Test-BylawConditionContext -Keyword 'Element' -Allowed 'Each' -Location $location)) {
        return
    }

    $field = [BylawFieldRef]::new()
    $field.Kind = [BylawFieldKind]::Element
    $field.Location = $location
    $frame.PendingFields.Add($field)
    $field
}
