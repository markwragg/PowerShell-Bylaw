# Condition statements (ADR-0040): finding them in a scope, resolving their field names, and the
# values and fields they use, for the validation passes.

function Get-BylawRawStatement {
    # Every Condition statement in a resource scope, or in a list of Require blocks, in source
    # order, including inside Each, groups and Count -Where.
    param(
        [Parameter(Mandatory, ParameterSetName = 'Scope')] [BylawResourceScope] $Scope,
        [Parameter(Mandatory, ParameterSetName = 'Requirements')] [AllowEmptyCollection()] [object[]] $Requirements
    )

    $queue = [System.Collections.Generic.List[object]]::new()
    if ($PSCmdlet.ParameterSetName -eq 'Scope') {
        foreach ($applicability in $Scope.When) {
            $queue.AddRange($applicability.Children)
        }
        $Requirements = @($Scope.Requirements)
    }
    foreach ($requirement in $Requirements) {
        $queue.AddRange($requirement.Children)
    }
    $index = 0
    while ($index -lt $queue.Count) {
        $node = $queue[$index]
        $index++
        if ($node -is [BylawEach] -or $node -is [BylawConditionGroup]) {
            $queue.InsertRange($index, $node.Children)
        }
        elseif ($node -is [BylawAssertion] -and $node.Subject -is [BylawCount]) {
            $queue.InsertRange($index, $node.Subject.Children)
        }
        elseif ($node -is [BylawRawCondition]) {
            $node
        }
    }
}

function Get-BylawRawConditionPart {
    # Every condition in a raw condition's tree, depth first, including inside count where.
    param([Parameter(Mandatory)] [BylawCondition] $Condition)

    $Condition
    if ($Condition -is [BylawGroup]) {
        foreach ($child in $Condition.Children) {
            Get-BylawRawConditionPart -Condition $child
        }
    }
    elseif ($Condition -is [BylawNot]) {
        Get-BylawRawConditionPart -Condition $Condition.Child
    }
    elseif ($Condition -is [BylawCountCondition] -and $null -ne $Condition.Where) {
        Get-BylawRawConditionPart -Condition $Condition.Where
    }
}

function Get-BylawRawConditionValue {
    # The IR values a raw condition uses: operator values, value-condition subjects and value-count
    # lists. A literal string that is an ARM expression, such as "[parameters('x')]", is returned as
    # a BylawExpr, so the parameters it uses count as used.
    param([Parameter(Mandatory)] [BylawCondition] $Condition)

    foreach ($part in Get-BylawRawConditionPart -Condition $Condition) {
        $values = switch ($part.GetType().Name) {
            'BylawFieldCondition' { , $part.Value }
            'BylawValueCondition' { $part.Subject, $part.Value }
            'BylawCountCondition' { $part.Value, $part.ValueSource }
            default { @() }
        }
        foreach ($value in $values) {
            if ($value -is [BylawLiteral] -and $value.Value -is [string] -and $value.Value -match '^\[[^\[].*\]$') {
                [BylawExpr]::new($value.Value)
            }
            elseif ($null -ne $value) {
                $value
            }
        }
    }
}

function Get-BylawRawConditionField {
    # The resolved names of the fields a raw condition tests, for checks such as "Modify changes a
    # field no Require checks" (BYL3070).
    param([Parameter(Mandatory)] [BylawCondition] $Condition)

    foreach ($part in Get-BylawRawConditionPart -Condition $Condition) {
        if (($part -is [BylawFieldCondition] -or $part -is [BylawCountCondition]) -and $null -ne $part.Field -and $part.Field.Resolved) {
            $part.Field.Resolved
        }
    }
}

function Resolve-BylawRawConditionAlias {
    # Resolves the field names in a raw condition like Field does (ADR-0040), with three
    # differences: a full alias, or a path with [*], is used as it is, even inside Each; a name that is an ARM expression
    # is kept as written; and [*] fields are allowed, since they are a reason to write raw JSON.
    param(
        [Parameter(Mandatory)] [BylawCondition] $Condition,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [AllowNull()] [string] $ArrayAlias
    )

    if ($Condition -is [BylawGroup]) {
        foreach ($child in $Condition.Children) {
            Resolve-BylawRawConditionAlias -Condition $child -Context $Context -ArrayAlias $ArrayAlias
        }
        return
    }
    if ($Condition -is [BylawNot]) {
        Resolve-BylawRawConditionAlias -Condition $Condition.Child -Context $Context -ArrayAlias $ArrayAlias
        return
    }
    if ($Condition -is [BylawFieldCondition]) {
        $null = Resolve-BylawRawFieldAlias -Field $Condition.Field -Context $Context -ArrayAlias $ArrayAlias
        return
    }
    if ($Condition -is [BylawCountCondition]) {
        $whereAlias = $ArrayAlias
        if ($null -ne $Condition.Field) {
            $whereAlias = Resolve-BylawRawFieldAlias -Field $Condition.Field -Context $Context -ArrayAlias $ArrayAlias -IsArrayPath
            if (-not $whereAlias) {
                return
            }
        }
        if ($null -ne $Condition.Where) {
            Resolve-BylawRawConditionAlias -Condition $Condition.Where -Context $Context -ArrayAlias $whereAlias
        }
    }
}

function Resolve-BylawRawFieldAlias {
    # One field name in a raw condition, resolved in place. Returns the resolved name, or '' on error.
    param(
        [Parameter(Mandatory)] [BylawFieldRef] $Field,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [AllowNull()] [string] $ArrayAlias,
        [switch] $IsArrayPath
    )

    $name = $Field.Name
    if ($name.StartsWith('[') -and -not $name.StartsWith('[[')) {
        # An ARM expression that names the field, e.g. "[concat('tags[', parameters('tagName'), ']')]".
        $Field.Resolved = $name
        return $name
    }
    # A full alias, or a path with [*] as policy JSON writes it inside a count's where, is absolute;
    # a plain name is relative to the element, as with Field.
    $array = if ($name.Contains('/') -or $name.Contains('[*]')) { $null } else { $ArrayAlias }
    $resolved = Get-BylawResolvedAlias -Field $Field -Context $Context -ArrayAlias $array -IsArrayPath:$IsArrayPath -AllowArrayField
    if ($resolved) {
        $Field.Resolved = $resolved
    }
    $resolved
}

function Test-BylawRawConditionParameter {
    # Every Param a raw condition uses is declared (BYL3020).
    param(
        [Parameter(Mandatory)] [BylawRawCondition] $Statement,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    foreach ($value in Get-BylawRawConditionValue -Condition $Statement.Condition) {
        $references = @(if ($value -is [BylawParamRef]) { $value } elseif ($value -is [BylawParamLength]) { $value.Parameter } elseif ($value -is [BylawResourceGroupTag] -and $value.TagName -is [BylawParamRef]) { $value.TagName })
        foreach ($reference in $references) {
            if ($null -eq $Policy.FindParameter($reference.Name)) {
                & $Add 'BYL3020' "Parameter '$($reference.Name)' is used in a Condition but not declared. Add a Parameter $($reference.Name) declaration." $Statement.Location
            }
        }
    }
}
