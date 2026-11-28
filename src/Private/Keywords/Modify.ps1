# Modify block and its operations (ADR-0024). Modify takes the place of Effect; its operations take
# the field to change from the pipeline, as Must does.

$script:BylawConflictEffects = @('audit', 'deny', 'disabled')

function Modify {
    <#
    .SYNOPSIS
        The modify effect: what to change on a non-compliant resource. Use it instead of Effect.

    .EXAMPLE
        Modify -Role 'Tag Contributor' {
            Tag Environment | AddOrReplace 'Production'
            Tag CostCenter | Add (ResourceGroupTag CostCenter)
            Tag TempResource | Remove
        }
    #>
    [CmdletBinding()]
    param(
        # The operations.
        [Parameter(Position = 0)]
        [scriptblock] $Body,

        # Roles the assignment's managed identity needs: built-in role names, GUIDs or full role
        # definition IDs (ADR-0022).
        [AllowEmptyCollection()] [AllowEmptyString()]
        [string[]] $Role,

        # What happens when another policy modifies the same field, or the field can't be
        # modified: Audit, Deny (Azure's default) or Disabled.
        [string] $ConflictEffect,

        # The effect as a parameter, (Param Effect). Without it, the effect is Modify.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Modify')
    $frame = Test-BylawParent -Keyword 'Modify' -Allowed 'Policy' -Location $location
    if ($null -eq $frame) {
        return
    }
    if (-not (Test-BylawEffectKeyword -Frame $frame -Keyword 'Modify' -Location $location)) {
        return
    }

    $valid = $true
    $effectValue = [BylawLiteral]::new('Modify')
    $effectValue.Location = $location
    if ($PSBoundParameters.ContainsKey('Effect')) {
        if ($Effect -is [BylawParamRef] -or $Effect -is [BylawExpr]) {
            $effectValue = $Effect
        }
        else {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1030' -Location $location -Message (
                'Modify -Effect takes a parameter, e.g. -Effect (Param Effect). Without -Effect, the effect is Modify.'
            )
            $valid = $false
        }
    }
    $roles = @($Role | Where-Object { $null -ne $_ })
    if ($roles.Count -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1032' -Location $location -Message (
            "Modify needs -Role: the role the assignment's managed identity needs to make the change, e.g. Modify -Role 'Tag Contributor' { ... } (ADR-0022)."
        )
        $valid = $false
    }
    $conflict = $null
    if ($PSBoundParameters.ContainsKey('ConflictEffect')) {
        $conflict = $script:BylawConflictEffects | Where-Object { $_ -eq $ConflictEffect } | Select-Object -First 1
        if (-not $conflict) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1029' -Location $location -Message (
                "-ConflictEffect '$ConflictEffect' is not valid. Use Audit, Deny or Disabled."
            )
            $valid = $false
        }
    }

    $node = [BylawModify]::new($effectValue)
    $node.Location = $location
    $node.Roles = [string[]] $roles
    $node.ConflictEffect = $conflict

    if ($null -eq $Body) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $location -Message (
            "Modify needs a block of operations, e.g. Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }."
        )
        return
    }

    $diagnosticsBefore = $script:BylawDiagnostics.Count
    $modifyFrame = Enter-BylawFrame -Keyword 'Modify' -Node $node
    try {
        Invoke-BylawBlock -Body $Body
    }
    finally {
        Exit-BylawFrame -Frame $modifyFrame
    }
    $innerErrors = @($script:BylawDiagnostics | Select-Object -Skip $diagnosticsBefore | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count
    if ($node.Operations.Count -eq 0 -and $innerErrors -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $location -Message (
            "'Modify' block is empty. Add at least one operation, e.g. Tag Environment | AddOrReplace 'Production'."
        )
    }
    if ($valid) {
        $frame.Node.Effect = $node
    }
}

function AddOrReplace {
    <#
    .SYNOPSIS
        Sets the piped field to a value, replacing any value it has. Use inside Modify.

    .EXAMPLE
        Tag Environment | AddOrReplace 'Production'
    #>
    [CmdletBinding()]
    param(
        # The field to change: a Field or Tag, piped to the operation.
        [Parameter(ValueFromPipeline)]
        [object] $InputObject,

        # The value to set: a literal, Param, Arm or ResourceGroupTag.
        [Parameter(Position = 0)]
        [AllowNull()] [object] $Value,

        # Only apply the operation when this Arm expression is true.
        [object] $Condition
    )

    begin {
        $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'AddOrReplace')
        $frame = Test-BylawModifyOnlyParent -Keyword 'AddOrReplace' -Location $location
        $received = $false
        $bound = $PSBoundParameters
    }
    process {
        if ($null -ne $frame -and $bound.ContainsKey('InputObject')) {
            $received = $true
            Add-BylawModifyOperation -Keyword 'AddOrReplace' -Operation 'addOrReplace' -InputObject $InputObject -Bound $bound -Frame $frame -Location $location
        }
    }
    end {
        if ($null -ne $frame -and -not $received) {
            Add-BylawMissingOperationField -Keyword 'AddOrReplace' -Location $location
        }
    }
}

function Add {
    <#
    .SYNOPSIS
        In Modify, sets the piped field to a value only when it has none. In Append, adds the value
        to the request: it sets a field, or adds an element to a [*] array.

    .EXAMPLE
        Tag CostCenter | Add (ResourceGroupTag CostCenter)
    #>
    [CmdletBinding()]
    param(
        # The field to change: a Field or Tag, piped to the operation.
        [Parameter(ValueFromPipeline)]
        [object] $InputObject,

        # The value to set: a literal, Param, Arm or ResourceGroupTag.
        [Parameter(Position = 0)]
        [AllowNull()] [object] $Value,

        # Only apply the operation when this Arm expression is true.
        [object] $Condition
    )

    begin {
        $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Add')
        $frame = Test-BylawParent -Keyword 'Add' -Allowed 'Modify', 'Append' -Location $location
        $received = $false
        $bound = $PSBoundParameters
    }
    process {
        if ($null -ne $frame -and $bound.ContainsKey('InputObject')) {
            $received = $true
            Add-BylawModifyOperation -Keyword 'Add' -Operation 'add' -InputObject $InputObject -Bound $bound -Frame $frame -Location $location
        }
    }
    end {
        if ($null -ne $frame -and -not $received) {
            Add-BylawMissingOperationField -Keyword 'Add' -Location $location
        }
    }
}

function Remove {
    <#
    .SYNOPSIS
        Removes the piped tag. Use inside Modify. Only tags can be removed.

    .EXAMPLE
        Tag TempResource | Remove
    #>
    [CmdletBinding()]
    param(
        # The tag to remove, piped to Remove.
        [Parameter(ValueFromPipeline)]
        [object] $InputObject,

        # Not allowed: accepted only so that Remove 'x' gets a clear error.
        [Parameter(Position = 0)]
        [AllowNull()] [object] $Value,

        # Only apply the operation when this Arm expression is true.
        [object] $Condition
    )

    begin {
        $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Remove')
        $frame = Test-BylawModifyOnlyParent -Keyword 'Remove' -Location $location
        $received = $false
        $bound = $PSBoundParameters
    }
    process {
        if ($null -ne $frame -and $bound.ContainsKey('InputObject')) {
            $received = $true
            Add-BylawModifyOperation -Keyword 'Remove' -Operation 'remove' -InputObject $InputObject -Bound $bound -Frame $frame -Location $location
        }
    }
    end {
        if ($null -ne $frame -and -not $received) {
            Add-BylawMissingOperationField -Keyword 'Remove' -Location $location
        }
    }
}

function Test-BylawModifyOnlyParent {
    # The frame for AddOrReplace and Remove, which only Modify has. In Append, BYL1036 explains that
    # Append only adds (ADR-0029).
    param([Parameter(Mandatory)] [string] $Keyword, [BylawSourceLocation] $Location)

    $current = Get-BylawCurrentFrame
    if ($null -ne $current -and $current.Keyword -eq 'Append') {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1036' -Location $Location -Message (
            "$Keyword can't be used in Append, which can only Add values to the request. To replace or remove a value, use Modify."
        )
        return $null
    }
    Test-BylawParent -Keyword $Keyword -Allowed 'Modify' -Location $Location
}

function Add-BylawMissingOperationField {
    param([Parameter(Mandatory)] [string] $Keyword, [BylawSourceLocation] $Location)

    $example = if ($Keyword -eq 'Remove') { 'Tag TempResource | Remove' } else { "Tag Environment | $Keyword 'Production'" }
    Add-BylawDiagnostic -Severity Error -Code 'BYL1031' -Location $Location -Message (
        "$Keyword needs a field from the pipeline, e.g. $example."
    )
}

function Add-BylawModifyOperation {
    # Adds one operation to the Modify block, or records diagnostics.
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [string] $Operation,
        [AllowNull()] [object] $InputObject,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Bound,
        [Parameter(Mandatory)] [BylawFrame] $Frame,
        [BylawSourceLocation] $Location
    )

    if ($InputObject -isnot [BylawFieldRef] -or $InputObject.Kind -eq [BylawFieldKind]::Element) {
        Add-BylawMissingOperationField -Keyword $Keyword -Location $Location
        return
    }
    $null = $Frame.PendingFields.Remove($InputObject)

    $hasValue = $Bound.ContainsKey('Value')
    if ($Operation -eq 'remove' -and $hasValue) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1027' -Location $Location -Message (
            "Remove takes no value: it removes the field. Write: $InputObject | Remove"
        )
        return
    }
    if ($Operation -ne 'remove' -and -not $hasValue) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1027' -Location $Location -Message (
            "$Keyword needs the value to set, e.g. $InputObject | $Keyword 'Production'."
        )
        return
    }

    $condition = $null
    if ($Frame.Keyword -eq 'Append' -and $Bound.ContainsKey('Condition')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1037' -Location $Location -Message (
            "Add in Append takes no -Condition: Azure's append details have no conditions. Put the condition in When or Require."
        )
        return
    }
    if ($Bound.ContainsKey('Condition')) {
        if ($Bound['Condition'] -isnot [BylawExpr]) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1028' -Location $Location -Message (
                "-Condition takes an Arm expression that is true or false, e.g. -Condition (Arm `"[equals(parameters('mode'), 'strict')]`")."
            )
            return
        }
        $condition = $Bound['Condition']
    }

    $operationNode = [BylawModifyOperation]::new($Operation, $InputObject)
    $operationNode.Location = $Location
    $operationNode.Condition = $condition
    if ($hasValue) {
        $value = ConvertTo-BylawValue -Value $Bound['Value'] -Location $Location
        if ($null -eq $value) {
            return
        }
        $operationNode.Value = $value
    }
    $Frame.Node.Operations.Add($operationNode)
}
