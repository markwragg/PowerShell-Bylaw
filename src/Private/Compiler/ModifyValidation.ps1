# Validation of Modify blocks (ADR-0022, ADR-0024). Called by Invoke-BylawValidation after alias
# resolution. Also resolves -Role values to role definition IDs.

$script:BylawIdentityTypeResourceTypes = @('Microsoft.Compute/virtualMachines', 'Microsoft.Compute/virtualMachineScaleSets')
$script:BylawResourceGroupType = 'Microsoft.Resources/subscriptions/resourceGroups'
# The role map, set by Invoke-BylawFileCompile for each file's runspace. $null outside a build.
$script:BylawRoleData = $null

function Test-BylawModify {
    param(
        [Parameter(Mandatory)] [BylawModify] $Modify,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [AllowNull()] [BylawAliasSnapshot] $Snapshot,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    Resolve-BylawEffectRole -Effect $Modify -Add $Add

    $scope = $Policy.Resource
    $type = if ($scope.ResolvedType) { $scope.ResolvedType } else { $scope.Type }
    $mode = if ($Policy.Properties -and $Policy.Properties.Mode) { $Policy.Properties.Mode } else { 'All' }
    $checked = Get-BylawRequirementFieldName -Scope $scope
    $seen = @{}
    $tagModeWarned = $false
    $aliasOperation = $null

    foreach ($operation in $Modify.Operations) {
        $field = $operation.Field
        $location = $operation.Location
        Test-BylawModifyParameter -Operation $operation -Policy $Policy -Add $Add

        if ($operation.Condition -and $operation.Condition.Text -match '(?i)\b(field|resourceGroup|subscription)\s*\(') {
            & $Add 'BYL3068' "-Condition uses $($Matches[1])(), which Azure doesn't support in a Modify operation's condition. Use other policy functions, such as parameters() or requestContext()." $location
        }

        if ($field.Kind -eq [BylawFieldKind]::Field -and $field.Name.Contains('[*]')) {
            & $Add 'BYL3066' "Modify can't change '$($field.Name)': Azure doesn't document modifying array elements ([*]). Modify the whole array alias, or a tag." $location
            continue
        }
        $name = $field.Resolved
        if (-not $name) {
            # Alias resolution already reported it.
            continue
        }

        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            & $Add 'BYL3067' "'$name' is changed by more than one operation (first at line $($seen[$key].Line)). Use one operation per field." $location
            continue
        }
        $seen[$key] = $location

        $isTag = $field.Kind -eq [BylawFieldKind]::Tag -or $name -match '^tags(\[|\.)'
        if ($operation.Operation -eq 'remove' -and -not $isTag) {
            & $Add 'BYL3063' "Remove only works on tags: Azure can only remove tags. To change '$name', use AddOrReplace." $location
            continue
        }

        if ($isTag) {
            if (-not $tagModeWarned -and $mode -ne 'Indexed' -and $type -ne $script:BylawResourceGroupType) {
                & $Add 'BYL3069' "Modify changes the tag '$name' but Mode is $mode. Azure recommends Mode = 'Indexed' for Modify policies on tags, unless the resource type is a resource group." $location ([BylawSeverity]::Warning)
                $tagModeWarned = $true
            }
        }
        elseif ($name -eq 'identity.type') {
            if (-not $scope.IsAnyType() -and $type -notin $script:BylawIdentityTypeResourceTypes) {
                & $Add 'BYL3065' "Modify can only change identity.type on virtual machines and virtual machine scale sets. Azure skips the operation for '$type', so the policy would do nothing." $location
                continue
            }
        }
        elseif (Get-BylawReservedField -Name $name) {
            & $Add 'BYL3064' "Modify can't change '$name'. It can change tags, identity.type and aliases marked Modifiable." $location
            continue
        }
        else {
            if ($Snapshot -and $Snapshot.FindAlias($name) -and -not $Snapshot.IsModifiable($name)) {
                & $Add 'BYL3064' "Alias '$name' isn't marked Modifiable in the alias snapshot ($($Snapshot.Path)), so Modify can't change it." $location
                continue
            }
            $aliasOperation = if ($aliasOperation) { $aliasOperation } else { $operation }
        }

        if (-not $checked.Contains($name)) {
            & $Add 'BYL3070' "Modify changes '$name', but no Require checks it, so a remediated resource still won't be compliant. Add a Require for '$name'." $location ([BylawSeverity]::Warning)
        }
    }

    if ($aliasOperation -and $Modify.ConflictEffect -ne 'audit') {
        $current = if ($Modify.ConflictEffect) { "-ConflictEffect $($Modify.ConflictEffect)" } else { 'no -ConflictEffect (Azure defaults to deny)' }
        & $Add 'BYL3071' "Modify changes '$($aliasOperation.Field.Resolved)', which isn't a tag, with $current. Azure recommends -ConflictEffect Audit when Modify changes aliases, so requests using API versions where the property isn't modifiable aren't denied." $Modify.Location ([BylawSeverity]::Warning)
    }
}

function Resolve-BylawEffectRole {
    # Sets RoleDefinitionIds from -Role (ADR-0022), in the order written, for Modify and
    # DeployIfNotExists.
    param([Parameter(Mandatory)] [BylawEffect] $Effect, [Parameter(Mandatory)] [scriptblock] $Add)

    $roleData = $script:BylawRoleData
    if ($null -eq $roleData) {
        # Outside Build-Bylaw (e.g. in tests), use the bundled map.
        $roleData = Read-BylawRoleMapData -Path (Get-BylawBundledRoleMapPath)
    }
    $ids = [System.Collections.Generic.List[string]]::new()
    $written = @{}
    foreach ($role in $Effect.Roles) {
        $resolved = Resolve-BylawRoleDefinitionId -Role $role -RoleData $roleData
        if (-not $resolved.Id) {
            & $Add 'BYL3060' $resolved.Message $Effect.Location
            continue
        }
        $key = $resolved.Id.ToLowerInvariant()
        if ($written.ContainsKey($key)) {
            & $Add 'BYL3061' "Role '$role' is the same role as '$($written[$key])'. Give each role once." $Effect.Location
            continue
        }
        $written[$key] = $role
        $ids.Add($resolved.Id)
    }
    $Effect.RoleDefinitionIds = $ids.ToArray()
}

function Test-BylawModifyParameter {
    # Parameters used by an operation must be declared; a tag-name parameter must be a String.
    param(
        [Parameter(Mandatory)] [BylawModifyOperation] $Operation,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $tagNames = [System.Collections.Generic.List[object]]::new()
    if ($Operation.Field.Kind -eq [BylawFieldKind]::Tag) {
        $tagNames.Add($Operation.Field.TagName)
    }
    if ($Operation.Value -is [BylawResourceGroupTag]) {
        $tagNames.Add($Operation.Value.TagName)
    }
    foreach ($tagName in $tagNames) {
        if ($tagName -isnot [BylawParamRef]) {
            continue
        }
        $parameter = $Policy.FindParameter($tagName.Name)
        if ($null -eq $parameter) {
            & $Add 'BYL3020' "Parameter '$($tagName.Name)' is used as a tag name but not declared. Add: Parameter $($tagName.Name) -Type String." $tagName.Location
        }
        elseif ($parameter.Type -ne 'String') {
            & $Add 'BYL3034' "Parameter '$($parameter.Name)' holds a tag name, so it must be of type String (it is $($parameter.Type))." $tagName.Location
        }
    }
    if ($Operation.Value -is [BylawParamRef] -and $null -eq $Policy.FindParameter($Operation.Value.Name)) {
        & $Add 'BYL3020' "Parameter '$($Operation.Value.Name)' is used but not declared. Add a Parameter $($Operation.Value.Name) declaration." $Operation.Value.Location
    }
}

function Get-BylawRequirementFieldName {
    # The resolved names of the fields that Require blocks check, ignoring case, including the
    # array paths of Each blocks (such as 'x/ipRules[*]').
    param([Parameter(Mandatory)] [BylawResourceScope] $Scope)

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($requirement in $Scope.Requirements) {
        $queue.AddRange($requirement.Children)
    }
    $index = 0
    while ($index -lt $queue.Count) {
        $node = $queue[$index]
        $index++
        if ($node -is [BylawEach] -or $node -is [BylawConditionGroup]) {
            $queue.AddRange($node.Children)
            if ($node -is [BylawEach] -and $node.Field.Resolved) {
                $null = $names.Add($node.Field.Resolved)
            }
        }
        elseif ($node -is [BylawAssertion] -and $null -ne $node.Field -and $node.Field.Resolved) {
            $null = $names.Add($node.Field.Resolved)
        }
    }
    , $names
}
