# Validation of AuditIfNotExists and DeployIfNotExists (ADR-0030). Called by Invoke-BylawValidation
# after alias resolution. Assertions in the existence condition are checked with the rest.

$script:BylawSameResourceNames = @("[field('name')]", "[field('fullName')]")

function Test-BylawIfNotExistsEffect {
    param(
        [Parameter(Mandatory)] [BylawIfNotExists] $Effect,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $keyword = Get-BylawEffectKeyword -Effect $Effect
    foreach ($entry in @(@('Name', $Effect.Name), @('ResourceGroupName', $Effect.ResourceGroupName))) {
        $value = $entry[1]
        if ($value -is [BylawParamRef] -and $null -eq $Policy.FindParameter($value.Name)) {
            & $Add 'BYL3020' "Parameter '$($value.Name)' is used in -$($entry[0]) but not declared. Add: Parameter $($value.Name) -Type String." $value.Location
        }
    }

    $scope = $Policy.Resource
    if ($scope.IsAnyType()) {
        return
    }
    $resourceType = if ($scope.ResolvedType) { $scope.ResolvedType } else { $scope.Type }
    $relatedType = if ($Effect.ResolvedType) { $Effect.ResolvedType } else { $Effect.Type }

    # Learn: when the related type is the evaluated type, name is required and must be the
    # resource's own name.
    if ([string]::Equals($relatedType, $resourceType, [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = $Effect.Name
        $isOwnName = $name -is [BylawExpr] -and @($script:BylawSameResourceNames | Where-Object { [string]::Equals($_, $name.Text.Trim(), [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $isOwnName) {
            & $Add 'BYL3090' "$keyword -Type is the Resource type, so -Name must be the resource's own name: -Name (Arm `"[field('name')]`"), or (Arm `"[field('fullName')]`") for a child resource." $Effect.Location
        }
        elseif ($keyword -eq 'AuditIfNotExists') {
            & $Add 'BYL3091' "AuditIfNotExists checks the resource itself. Learn suggests the Audit effect for this: Effect Audit, with the existence condition as a Require block." $Effect.Location ([BylawSeverity]::Warning)
        }
        return
    }

    # Learn: resourceGroupName and existenceScope don't apply to a child of the evaluated resource.
    if ($relatedType.StartsWith("$resourceType/", [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($set in @(@('ResourceGroupName', ($null -ne $Effect.ResourceGroupName)), @('ExistenceScope', [bool] $Effect.ExistenceScope))) {
            if ($set[1]) {
                & $Add 'BYL3092' "-$($set[0]) has no effect: '$relatedType' is a child of '$resourceType', and Azure only looks for child resources under the evaluated resource." $Effect.Location ([BylawSeverity]::Warning)
            }
        }
    }
}
