# Validation of AuditIfNotExists and DeployIfNotExists (ADR-0030). Called by Invoke-BylawValidation
# after alias resolution. Assertions in the existence condition are checked with the rest.

$script:BylawSameResourceNames = @("[field('name')]", "[field('fullName')]")

function Test-BylawDeployment {
    # The values passed to the template match its parameters (ADR-0031): every name is a template
    # parameter (BYL3093), and every template parameter without a defaultValue is given (BYL3094).
    # Policy parameters used as values must be declared (BYL3020).
    param(
        [Parameter(Mandatory)] [BylawDeployment] $Deployment,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $source = if ($Deployment.TemplateFile) { "template file '$([System.IO.Path]::GetFileName($Deployment.TemplateFile))'" } else { 'template' }
    $declared = Get-BylawTemplateKey -Object $Deployment.Template -Key 'parameters'
    $templateParameters = if ($null -ne $declared -and $declared.Value -is [System.Collections.IDictionary]) { $declared.Value } else { [ordered]@{} }
    $names = @($templateParameters.Keys | ForEach-Object { [string] $_ })

    foreach ($entry in $Deployment.Parameters.GetEnumerator()) {
        $match = $names | Where-Object { [string]::Equals($_, $entry.Key, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $match) {
            $known = if ($names.Count -gt 0) { " Its parameters: $($names -join ', ')." } else { ' It has no parameters.' }
            & $Add 'BYL3093' "Deployment passes '$($entry.Key)', which is not a parameter of the $source.$known" $Deployment.Location
        }
        $value = $entry.Value
        if ($value -is [BylawParamRef] -and $null -eq $Policy.FindParameter($value.Name)) {
            & $Add 'BYL3020' "Parameter '$($value.Name)' is passed to the template but not declared. Add a Parameter $($value.Name) declaration." $value.Location
        }
    }
    foreach ($name in $names) {
        $definition = $templateParameters[$name]
        $hasDefault = $definition -is [System.Collections.IDictionary] -and $null -ne (Get-BylawTemplateKey -Object $definition -Key 'defaultValue')
        $given = @($Deployment.Parameters.Keys | Where-Object { [string]::Equals([string] $_, $name, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $hasDefault -and -not $given) {
            & $Add 'BYL3094' "The $source requires parameter '$name', which has no defaultValue. Pass it: Deployment ... -Parameters @{ $name = ... }." $Deployment.Location
        }
    }
    if ($Deployment.DeploymentLocation -is [BylawParamRef] -and $null -eq $Policy.FindParameter($Deployment.DeploymentLocation.Name)) {
        & $Add 'BYL3020' "Parameter '$($Deployment.DeploymentLocation.Name)' is used in -Location but not declared. Add: Parameter $($Deployment.DeploymentLocation.Name) -Type String." $Deployment.DeploymentLocation.Location
    }
}

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

    if ($Effect -is [BylawDeployIfNotExists]) {
        Resolve-BylawEffectRole -Effect $Effect -Add $Add
        Test-BylawDeployment -Deployment $Effect.Deployment -Policy $Policy -Add $Add
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
