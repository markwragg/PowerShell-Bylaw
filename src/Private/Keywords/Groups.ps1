function AnyOf {
    <#
    .SYNOPSIS
        Alternatives: holds when at least one statement or group inside it holds (ADR-0026).

    .EXAMPLE
        Each securityRules[*] {
            AnyOf {
                Field direction | Must -Not -Be 'Inbound'
                Field access | Must -Not -Be 'Allow'
            }
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'AnyOf')
    $parent = Test-BylawParent -Keyword 'AnyOf' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Where' -Location $location
    if ($null -eq $parent) {
        return
    }
    Invoke-BylawGroup -Kind AnyOf -Parent $parent -Body $Body -Location $location
}

function AllOf {
    <#
    .SYNOPSIS
        Inside AnyOf, one alternative made of several statements that must all hold (ADR-0026).

    .EXAMPLE
        AnyOf {
            Field publicNetworkAccess | Must -Be 'Disabled'
            AllOf {
                Field networkAcls.defaultAction | Must -Be 'Deny'
                Field networkAcls.bypass | Must -Be 'AzureServices'
            }
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'AllOf')
    $parent = Get-BylawCurrentFrame
    if ($null -ne $parent -and $parent.Keyword -in 'When', 'Require', 'Each', 'AllOf') {
        # Statements already combine with AND here, so AllOf would change nothing.
        Add-BylawDiagnostic -Severity Error -Code 'BYL1022' -Location $location -Message (
            "AllOf is only needed directly inside AnyOf. Statements in '$($parent.Keyword)' already combine with AND, so write them without AllOf."
        )
        return
    }
    $parent = Test-BylawParent -Keyword 'AllOf' -Allowed 'AnyOf' -Location $location
    if ($null -eq $parent) {
        return
    }
    Invoke-BylawGroup -Kind AllOf -Parent $parent -Body $Body -Location $location
}

function Invoke-BylawGroup {
    param(
        [Parameter(Mandatory)] [BylawGroupKind] $Kind,
        [Parameter(Mandatory)] [BylawFrame] $Parent,
        [Parameter(Mandatory)] [scriptblock] $Body,
        [BylawSourceLocation] $Location
    )

    $node = [BylawConditionGroup]::new($Kind)
    $node.Location = $Location
    Invoke-BylawContainer -Keyword ([string] $Kind) -Node $node -Body $Body -Location $Location
    $Parent.Node.Children.Add($node)
}
