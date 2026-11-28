function Each {
    <#
    .SYNOPSIS
        Every element of an array must satisfy the block. Compiles to count/where (ADR-0002).

    .DESCRIPTION
        Field names inside Each are relative to the element, and Element is the element itself
        when the array holds plain values. A missing or empty array is compliant, as in Azure.
        Inside Each, a missing field on an element is compliant unless -Strict is used on Must.

    .EXAMPLE
        Each networkAcls.ipRules[*] {
            Field value | Must -Not -Be '0.0.0.0/0'
        }

    .EXAMPLE
        Each accessPolicies[*] {
            Each permissions.keys[*] {
                Element | Must -Not -Be 'purge'
            }
        }
    #>
    [CmdletBinding()]
    param(
        # The array, ending in [*], e.g. networkAcls.ipRules[*]. Inside another Each, it is
        # relative to that element.
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        # The requirement every element must meet.
        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Each')
    $parent = Test-BylawParent -Keyword 'Each' -Allowed 'Require', 'Each', 'AnyOf', 'AllOf' -Location $location
    if ($null -eq $parent) {
        return
    }
    if (-not (Test-BylawConditionContext -Keyword 'Each' -Allowed 'Require', 'Each' -Location $location)) {
        return
    }
    if (-not $Path.EndsWith('[*]')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1016' -Location $location -Message (
            "Each needs an array path ending in [*], e.g. Each networkAcls.ipRules[*] { ... } (got '$Path')."
        )
        return
    }

    $field = [BylawFieldRef]::new($Path)
    $field.Location = $location
    $node = [BylawEach]::new($field)
    $node.Location = $location
    Invoke-BylawContainer -Keyword 'Each' -Node $node -Body $Body -Location $location
    $parent.Node.Children.Add($node)
}
