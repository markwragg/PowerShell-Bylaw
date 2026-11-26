function Tag {
    <#
    .SYNOPSIS
        A tag field reference: tags['name'] (ADR-0020). Pipe it to Must.

    .EXAMPLE
        Tag CostCenter | Must -Exist

    .EXAMPLE
        Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName))
    #>
    [CmdletBinding()]
    param(
        # The tag name, or (Param Name) for a parameter that holds it.
        [Parameter(Mandatory, Position = 0)]
        [object] $Name
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Tag')
    $frame = Test-BylawParent -Keyword 'Tag' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf' -Location $location
    if ($null -eq $frame) {
        return
    }
    if ((Get-BylawConditionContext) -eq 'Each') {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1002' -Location $location -Message (
            "'Tag' cannot be used inside 'Each': fields inside Each refer to the array element. Check the tag in a separate Require, outside the Each."
        )
        return
    }
    $tagName = ConvertTo-BylawTagName -Keyword 'Tag' -Name $Name -Location $location
    if ($null -eq $tagName) {
        return
    }

    $displayName = if ($tagName -is [BylawParamRef]) { "tags[$tagName]" } else { "tags['$($tagName.Value)']" }
    $field = [BylawFieldRef]::new($displayName)
    $field.Kind = [BylawFieldKind]::Tag
    $field.TagName = $tagName
    $field.Location = $location
    $frame.PendingFields.Add($field)
    $field
}

function ResourceGroupTag {
    <#
    .SYNOPSIS
        The resource group's value for a tag: [resourceGroup().tags['name']] (ADR-0020). Use it as a
        value, or pipe it to Must to test it (ADR-0025).

    .EXAMPLE
        Tag CostCenter | Must -Be (ResourceGroupTag CostCenter)

    .EXAMPLE
        When { ResourceGroupTag CostCenter | Must -Not -Be '' }
    #>
    [CmdletBinding()]
    param(
        # The tag name, or (Param Name) for a parameter that holds it.
        [Parameter(Mandatory, Position = 0)]
        [object] $Name
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'ResourceGroupTag')
    if ($null -eq (Get-BylawCurrentFrame)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $location -Message (
            "'ResourceGroupTag' can only be used inside a Policy block."
        )
        return
    }
    $tagName = ConvertTo-BylawTagName -Keyword 'ResourceGroupTag' -Name $Name -Location $location
    if ($null -eq $tagName) {
        return
    }
    $value = [BylawResourceGroupTag]::new($tagName)
    $value.Location = $location
    $value
}

function ConvertTo-BylawTagName {
    # A tag name argument as a BylawLiteral string or a BylawParamRef, or $null after recording a
    # diagnostic. A literal name can't contain ', [ or ], because it is written inside tags['...'].
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [AllowNull()] [object] $Name,
        [BylawSourceLocation] $Location
    )

    if ($Name -is [BylawParamRef]) {
        return $Name
    }
    if ($Name -isnot [string] -or [string]::IsNullOrWhiteSpace($Name)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1023' -Location $Location -Message (
            "$Keyword needs a tag name or a parameter, e.g. $Keyword CostCenter or $Keyword (Param TagName)."
        )
        return $null
    }
    if ($Name.IndexOfAny([char[]] "'[]") -ge 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1023' -Location $Location -Message (
            "Tag name '$Name' contains ', [ or ], which can't be written safely inside tags['...']. Use Arm with the expression you need."
        )
        return $null
    }
    $literal = [BylawLiteral]::new($Name)
    $literal.Location = $Location
    $literal
}
