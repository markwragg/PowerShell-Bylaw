function When {
    <#
    .SYNOPSIS
        Applicability conditions. Emitted as written; not inverted (ADR-0002).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'When')
    $parent = Test-BylawParent -Keyword 'When' -Allowed 'Resource' -Location $location
    if ($null -eq $parent) {
        return
    }

    $node = [BylawApplicability]::new()
    $node.Location = $location
    Invoke-BylawContainer -Keyword 'When' -Node $node -Body $Body -Location $location
    $parent.Node.When.Add($node)
}

function Invoke-BylawContainer {
    # Runs a When, Require or Each body and reports an empty block.
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [BylawNode] $Node,
        [Parameter(Mandatory)] [scriptblock] $Body,
        [BylawSourceLocation] $Location
    )
    $frame = Enter-BylawFrame -Keyword $Keyword -Node $Node
    try {
        Invoke-BylawBlock -Body $Body
    }
    finally {
        Exit-BylawFrame -Frame $frame
    }
    if ($Node.Children.Count -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $Location -Message (
            "'$Keyword' block is empty. Add at least one Field ... | Must ... statement."
        )
    }
}
