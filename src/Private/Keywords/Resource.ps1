function Resource {
    <#
    .SYNOPSIS
        Scopes the policy to a resource type and sets the alias resolution context.
        Resource * means no type condition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Type,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Resource')
    $parent = Test-BylawParent -Keyword 'Resource' -Allowed 'Policy' -Location $location
    if ($null -eq $parent -or -not (Test-BylawSingleton -Frame $parent -Keyword 'Resource' -Location $location)) {
        return
    }
    if ($Type -ne '*' -and $Type -notmatch '^[A-Za-z0-9.]+/[A-Za-z0-9./]+$') {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1021' -Location $location -Message (
            "Resource type '$Type' is not a valid type such as 'Microsoft.Storage/storageAccounts'. Use Resource * for no type condition."
        )
        return
    }

    $scope = [BylawResourceScope]::new($Type)
    $scope.Location = $location
    $parent.Node.Resource = $scope

    $frame = Enter-BylawFrame -Keyword 'Resource' -Node $scope
    try {
        Invoke-BylawBlock -Body $Body
    }
    finally {
        Exit-BylawFrame -Frame $frame
    }
}
