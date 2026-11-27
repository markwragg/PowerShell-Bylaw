#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }

<#
.SYNOPSIS
    Checks that Azure accepts the plain JSON initiatives Bylaw builds, for ADR-0034 and ADR-0035.

.DESCRIPTION
    Developer-only script. It is not part of the Bylaw module.

    It answers two questions that the build can't:
      Accepted:  does Azure accept the plain JSON policies and initiatives Bylaw builds, with members
                 from the build referenced by a full ID at the definition scope (ADR-0035)? And
                 can each initiative be assigned?
      Version:   what does Azure do with definitionVersion on a member from the build, given that
                 Bylaw emits Version only as metadata.version (ADR-0016, BYL3129)? The report
                 records whether the pinned initiative is accepted and assigned, and the version
                 Azure reports for each policy definition.

    It does not check EPAC: that EPAC resolves policyDefinitionName needs an EPAC environment.

    Deploy:  builds sources/ with -Format PlainJson and this subscription as -DefinitionScope,
             creates each policy and initiative definition at subscription scope, reads each
             initiative back, creates a resource group, and assigns each initiative to it. Every
             step is recorded, and a refused step doesn't stop the others. Writes a JSON and a
             Markdown report. Definitions and assignments cost nothing.
    Remove:  deletes the assignments, initiatives, policies and resource group.

    Every name starts with bylaw-verify.

.PARAMETER Action
    Deploy or Remove.

.PARAMETER SubscriptionId
    Sandbox subscription to use.

.PARAMETER ResourceGroupName
    Resource group to create and assign to. Default: rg-bylaw-verify-initiatives.

.PARAMETER Location
    Azure region for the resource group. Default: uksouth.

.PARAMETER OutputPath
    Folder for the built JSON and the reports. Default: ./out under this script's folder.

.EXAMPLE
    ./Invoke-InitiativeVerification.ps1 -Action Deploy -SubscriptionId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    ./Invoke-InitiativeVerification.ps1 -Action Remove -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters are used inside nested functions via script scope; PSSA does not track that.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Deploy', 'Remove')]
    [string] $Action,

    [Parameter(Mandatory)]
    [guid] $SubscriptionId,

    [ValidatePattern('^[A-Za-z0-9._()-]{1,90}$')]
    [string] $ResourceGroupName = 'rg-bylaw-verify-initiatives',

    [string] $Location = 'uksouth',

    [string] $OutputPath = (Join-Path $PSScriptRoot 'out')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$prefix = 'bylaw-verify'
$sourcePath = Join-Path $PSScriptRoot 'sources'
$scope = "/subscriptions/$SubscriptionId"
$resourceGroupScope = "$scope/resourceGroups/$ResourceGroupName"

function ConvertTo-CompressedJson {
    param([AllowNull()] [object] $Value)
    ConvertTo-Json -InputObject $Value -Depth 50 -Compress
}

function Invoke-Step {
    # Runs one Azure call and records whether it was accepted, without stopping the run.
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]] $Steps,
        # Not called Name: $Call runs in this scope, so a parameter called Name would hide the caller's $name.
        [Parameter(Mandatory)] [string] $StepName,
        [Parameter(Mandatory)] [scriptblock] $Call
    )

    try {
        $result = & $Call
        $Steps.Add([pscustomobject]@{ Step = $StepName; Result = 'accepted'; Detail = '' })
        $result
    }
    catch {
        $Steps.Add([pscustomobject]@{ Step = $StepName; Result = 'rejected'; Detail = $_.Exception.Message })
        Write-Warning "$StepName was rejected: $($_.Exception.Message)"
    }
}

function Get-BuildResult {
    # The plain JSON policies and initiatives, built with this subscription as the definition scope.
    $module = Join-Path $PSScriptRoot '../../src/Bylaw.psd1'
    Import-Module -Name $module -Force
    $buildPath = Join-Path $OutputPath 'json'
    $warnings = $null
    $results = @(Build-Bylaw -Path $sourcePath -OutputPath $buildPath -Format PlainJson -DefinitionScope $scope -PassThru -WarningVariable warnings -WarningAction SilentlyContinue)
    foreach ($warning in $warnings) {
        Write-Information "Build warning: $warning"
    }
    [pscustomobject]@{ Results = $results; Warnings = @($warnings | ForEach-Object { "$_" }) }
}

function Invoke-Deploy {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $build = Get-BuildResult
    $steps = [System.Collections.Generic.List[object]]::new()
    $readBack = [System.Collections.Generic.List[object]]::new()
    $policyVersions = [System.Collections.Generic.List[object]]::new()

    foreach ($result in $build.Results | Where-Object Kind -EQ 'Policy') {
        $definition = $result.Json | ConvertFrom-Json -AsHashtable
        $properties = $definition['properties']
        if (-not $PSCmdlet.ShouldProcess($definition['name'], 'Create policy definition')) {
            continue
        }
        $arguments = @{
            Name           = $definition['name']
            SubscriptionId = $SubscriptionId
            DisplayName    = $properties['displayName']
            Mode           = $properties['mode']
            Policy         = ConvertTo-CompressedJson $properties['policyRule']
        }
        foreach ($entry in @(@('description', 'Description'), @('metadata', 'Metadata'), @('parameters', 'Parameter'))) {
            if ($properties.Contains($entry[0])) {
                $arguments[$entry[1]] = if ($entry[0] -eq 'description') { $properties[$entry[0]] } else { ConvertTo-CompressedJson $properties[$entry[0]] }
            }
        }
        $created = Invoke-Step -Steps $steps -StepName "Create policy $($definition['name'])" -Call { New-AzPolicyDefinition @arguments -ErrorAction Stop }
        if ($created) {
            $policyVersions.Add([pscustomobject]@{ Name = $definition['name']; MetadataVersion = $properties['metadata']['version']; AzureVersion = if ($created.PSObject.Properties['Version']) { [string] $created.Version } else { '(none)' } })
        }
    }

    foreach ($result in $build.Results | Where-Object Kind -EQ 'Initiative') {
        $definition = $result.Json | ConvertFrom-Json -AsHashtable
        $properties = $definition['properties']
        $name = $definition['name']
        if (-not $PSCmdlet.ShouldProcess($name, 'Create initiative and assign it')) {
            continue
        }
        $arguments = @{
            Name             = $name
            SubscriptionId   = $SubscriptionId
            DisplayName      = $properties['displayName']
            PolicyDefinition = ConvertTo-CompressedJson @($properties['policyDefinitions'])
        }
        foreach ($entry in @(@('description', 'Description'), @('metadata', 'Metadata'), @('parameters', 'Parameter'), @('policyDefinitionGroups', 'PolicyDefinitionGroup'))) {
            if ($properties.Contains($entry[0])) {
                $value = $properties[$entry[0]]
                $arguments[$entry[1]] = if ($entry[0] -eq 'description') { $value } elseif ($entry[0] -eq 'policyDefinitionGroups') { ConvertTo-CompressedJson @($value) } else { ConvertTo-CompressedJson $value }
            }
        }
        $created = Invoke-Step -Steps $steps -StepName "Create initiative $name" -Call { New-AzPolicySetDefinition @arguments -ErrorAction Stop }
        if (-not $created) {
            continue
        }
        # What Azure stored for each member.
        $stored = Invoke-Step -Steps $steps -StepName "Read back initiative $name" -Call { Get-AzPolicySetDefinition -Name $name -SubscriptionId $SubscriptionId -ErrorAction Stop }
        if ($stored) {
            foreach ($member in @($stored.PolicyDefinition)) {
                $readBack.Add([pscustomobject]@{
                        Initiative        = $name
                        ReferenceId       = $member.policyDefinitionReferenceId
                        PolicyDefinition  = $member.policyDefinitionId
                        DefinitionVersion = if ($member.PSObject.Properties['definitionVersion']) { [string] $member.definitionVersion } else { '' }
                    })
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Create resource group and assign the initiatives')) {
        $null = Invoke-Step -Steps $steps -StepName "Create resource group $ResourceGroupName" -Call { New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction Stop }
        foreach ($result in $build.Results | Where-Object Kind -EQ 'Initiative') {
            $name = ($result.Json | ConvertFrom-Json -AsHashtable)['name']
            # Get-AzPolicySetDefinition throws for a missing initiative even with SilentlyContinue.
            $set = try { Get-AzPolicySetDefinition -Name $name -SubscriptionId $SubscriptionId -ErrorAction Stop } catch { $null }
            if (-not $set) {
                $steps.Add([pscustomobject]@{ Step = "Assign $name"; Result = 'skipped'; Detail = 'The initiative was not created.' })
                continue
            }
            $null = Invoke-Step -Steps $steps -StepName "Assign $name" -Call {
                # bylaw-verify-set has a Modify member (the built-in), which needs a managed identity.
                New-AzPolicyAssignment -Name $name -Scope $resourceGroupScope -DisplayName $set.DisplayName -PolicyDefinition $set -IdentityType SystemAssigned -Location $Location -ErrorAction Stop
            }
        }
    }

    $report = [ordered]@{
        builtWarnings  = $build.Warnings
        steps          = $steps
        policyVersions = $policyVersions
        readBack       = $readBack
    }
    $jsonPath = Join-Path $OutputPath 'initiative-results.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding utf8NoBOM

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Initiative verification')
    $lines.Add('')
    $lines.Add("Run $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. Plain JSON built with the subscription as -DefinitionScope.")
    $lines.Add('')
    $lines.Add('## Steps')
    $lines.Add('')
    $lines.Add('| Step | Result | Detail |')
    $lines.Add('|---|---|---|')
    foreach ($step in $steps) {
        $lines.Add("| $($step.Step) | $($step.Result) | $(($step.Detail -replace '\r?\n', ' ') -replace '\|', '\|') |")
    }
    $lines.Add('')
    $lines.Add('## Policy versions')
    $lines.Add('')
    $lines.Add('Bylaw emits Version as metadata.version only. "Azure" is the version Azure reports for the created definition.')
    $lines.Add('')
    $lines.Add('| Policy | metadata.version | Azure |')
    $lines.Add('|---|---|---|')
    foreach ($version in $policyVersions) {
        $lines.Add("| $($version.Name) | $($version.MetadataVersion) | $($version.AzureVersion) |")
    }
    $lines.Add('')
    $lines.Add('## Members as Azure stored them')
    $lines.Add('')
    $lines.Add('| Initiative | Reference ID | Policy definition | definitionVersion |')
    $lines.Add('|---|---|---|---|')
    foreach ($member in $readBack) {
        $lines.Add("| $($member.Initiative) | $($member.ReferenceId) | ``$($member.PolicyDefinition)`` | $($member.DefinitionVersion) |")
    }
    $lines.Add('')
    $lines.Add('## Build warnings')
    $lines.Add('')
    if ($build.Warnings.Count -eq 0) {
        $lines.Add('None.')
    }
    foreach ($warning in $build.Warnings) {
        $lines.Add("- $warning")
    }
    $markdownPath = Join-Path $OutputPath 'initiative-results.md'
    ($lines -join "`n") + "`n" | Set-Content -Path $markdownPath -Encoding utf8NoBOM -NoNewline

    $rejected = @($steps | Where-Object Result -NE 'accepted').Count
    Write-Information "Wrote $markdownPath and $jsonPath ($rejected step(s) not accepted)."
}

function Invoke-Remove {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    foreach ($assignment in @(Get-AzPolicyAssignment -Scope $resourceGroupScope -ErrorAction SilentlyContinue | Where-Object Name -Like "$prefix*")) {
        if ($PSCmdlet.ShouldProcess($assignment.Name, 'Remove policy assignment')) {
            Remove-AzPolicyAssignment -Name $assignment.Name -Scope $resourceGroupScope -ErrorAction SilentlyContinue
        }
    }
    foreach ($set in @(Get-AzPolicySetDefinition -SubscriptionId $SubscriptionId -Custom -ErrorAction SilentlyContinue | Where-Object Name -Like "$prefix*")) {
        if ($PSCmdlet.ShouldProcess($set.Name, 'Remove initiative')) {
            Remove-AzPolicySetDefinition -Name $set.Name -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($definition in @(Get-AzPolicyDefinition -SubscriptionId $SubscriptionId -Custom -ErrorAction SilentlyContinue | Where-Object Name -Like "$prefix*")) {
        if ($PSCmdlet.ShouldProcess($definition.Name, 'Remove policy definition')) {
            Remove-AzPolicyDefinition -Name $definition.Name -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
        }
    }
    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Remove resource group')) {
        $null = Remove-AzResourceGroup -Name $ResourceGroupName -Force -ErrorAction SilentlyContinue
    }
    Write-Information 'Removed verification resources.'
}

$null = Set-AzContext -Subscription $SubscriptionId.ToString()
if (-not (Test-Path $OutputPath)) {
    $null = New-Item -ItemType Directory -Path $OutputPath
}

switch ($Action) {
    'Deploy' { Invoke-Deploy }
    'Remove' { Invoke-Remove }
}
