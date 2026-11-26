function Field {
    <#
    .SYNOPSIS
        A field reference, resolved to a full alias at compile time. Pipe it to Must, or inside
        Modify to an operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        # Accept an alias that is not in the alias snapshot (ADR-0008).
        [switch] $AllowUnknownAlias
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Field')
    $frame = Test-BylawParent -Keyword 'Field' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Where', 'Modify', 'Append' -Location $location
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
    $frame = Test-BylawParent -Keyword 'Element' -Allowed 'Each', 'AnyOf', 'AllOf', 'Where' -Location $location
    if ($null -eq $frame) {
        return
    }
    if (-not (Test-BylawConditionContext -Keyword 'Element' -Allowed 'Each', 'Where' -Location $location)) {
        return
    }
    # In Count -Where, Element is the element of a field count; a value count has members, which
    # are Current (ADR-0032).
    if ((Get-BylawConditionContext) -eq 'Where' -and -not (@(Get-BylawEnclosingCount -WhereOnly)[0]).IsFieldCount()) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1002' -Location $location -Message (
            "'Element' is the element of an array, so it only applies in a field count. In a value count, use Current for the member being counted."
        )
        return
    }

    $field = [BylawFieldRef]::new()
    $field.Kind = [BylawFieldKind]::Element
    $field.Location = $location
    $frame.PendingFields.Add($field)
    $field
}
