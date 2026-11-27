function Resource {
    <#
    .SYNOPSIS
        Scopes the policy to a resource type and sets the alias resolution context.
        Resource * means no type condition.

    .DESCRIPTION
        Resource emits a type condition, and short field names inside it are resolved against
        that type's aliases. With Resource *, the policy applies to every resource type, and fields
        are reserved fields such as location or tags, or full aliases.

    .EXAMPLE
        Resource 'Microsoft.Storage/storageAccounts' {
            Require 'TLS 1.2 or later' {
                Field minimumTlsVersion | Must -Be 'TLS1_2'
            }
        }

    .EXAMPLE
        Resource * {
            Require 'An allowed location' {
                Field location | Must -BeIn (Param AllowedLocations)
            }
        }
    #>
    [CmdletBinding()]
    param(
        # The resource type, e.g. Microsoft.Storage/storageAccounts, or * for every type.
        [Parameter(Mandatory, Position = 0)]
        [string] $Type,

        # When and Require blocks.
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
