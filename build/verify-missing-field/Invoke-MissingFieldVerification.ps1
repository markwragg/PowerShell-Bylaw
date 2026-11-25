#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.PolicyInsights'; ModuleVersion = '1.6.0' }

<#
.SYNOPSIS
    Empirically verifies how Azure Policy operators evaluate against missing and empty fields.

.DESCRIPTION
    Developer-only script that supports ADR-0004. It is not part of the Bylaw module.

    Deploy:  creates a resource group with one route table (free) carrying known tags, one
             Audit-effect policy definition per (field, operator) case, an initiative containing
             them, and an assignment of that initiative to the resource group.
    Collect: triggers an on-demand compliance scan and records, for each case, whether the
             condition evaluated true (NonCompliant), false (Compliant) or something else.
             Writes a JSON and a Markdown report.
    Remove:  deletes the assignment, initiative, definitions and resource group.

    Each policy rule is: type equals routeTables AND name equals <route table> AND <case condition>.
    So NonCompliant means "<case condition> evaluated true" and Compliant means "false".

    Run Deploy, wait 15-30 minutes for the assignment to take effect, then run Collect
    (re-run Collect if cases are still missing), then Remove.

.PARAMETER Action
    Deploy, Collect or Remove.

.PARAMETER SubscriptionId
    Sandbox subscription to use. Definitions are created at subscription scope.

.PARAMETER ResourceGroupName
    Resource group to create and assign to. Default: rg-bylaw-verify.

.PARAMETER Location
    Azure region for the resource group and route table. Default: uksouth.

.PARAMETER ExtraField
    Additional full field or alias names to test. Use this to add a same-type alias that you know
    is absent, or present but null, on a route table.

.PARAMETER OutputPath
    Folder for the reports. Default: the current folder.

.EXAMPLE
    ./Invoke-MissingFieldVerification.ps1 -Action Deploy -SubscriptionId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    ./Invoke-MissingFieldVerification.ps1 -Action Collect -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters are used inside nested functions via script scope; PSSA does not track that.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Deploy', 'Collect', 'Remove')]
    [string] $Action,

    [Parameter(Mandatory)]
    [guid] $SubscriptionId,

    [ValidatePattern('^[A-Za-z0-9._()-]{1,90}$')]
    [string] $ResourceGroupName = 'rg-bylaw-verify',

    [string] $Location = 'uksouth',

    [string[]] $ExtraField = @(),

    [string] $OutputPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$prefix = 'bylaw-verify'
$routeTableName = "rt-$prefix"
$setName = "$prefix-set"
$assignmentName = "$prefix-assignment"

# Fields under test. Tags are fully controllable; the storage alias does not apply to route tables,
# so it is a missing alias. ExtraField adds anything else the caller wants to probe.
$fields = [ordered]@{
    tagPresent   = "tags['bylawPresent']"
    tagEmpty     = "tags['bylawEmpty']"
    tagMissing   = "tags['bylawMissing']"
    aliasMissing = 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
}
$extraIndex = 0
foreach ($extra in $ExtraField) {
    $extraIndex++
    $fields["extra$extraIndex"] = $extra
}

$tags = @{
    bylawPresent = 'abc'
    bylawEmpty   = ''
}

# Operator cases. Values are chosen so the tagPresent control ('abc') has a known answer.
$operators = @(
    @{ Id = 'equals'; Operator = 'equals'; Value = 'abc' }
    @{ Id = 'notEquals'; Operator = 'notEquals'; Value = 'abc' }
    @{ Id = 'in'; Operator = 'in'; Value = @('abc') }
    @{ Id = 'notIn'; Operator = 'notIn'; Value = @('abc') }
    @{ Id = 'like'; Operator = 'like'; Value = 'a*' }
    @{ Id = 'notLike'; Operator = 'notLike'; Value = 'a*' }
    @{ Id = 'match'; Operator = 'match'; Value = '???' }
    @{ Id = 'notMatch'; Operator = 'notMatch'; Value = '???' }
    @{ Id = 'matchI'; Operator = 'matchInsensitively'; Value = '???' }
    @{ Id = 'notMatchI'; Operator = 'notMatchInsensitively'; Value = '???' }
    @{ Id = 'contains'; Operator = 'contains'; Value = 'b' }
    @{ Id = 'notContains'; Operator = 'notContains'; Value = 'b' }
    @{ Id = 'containsKey'; Operator = 'containsKey'; Value = 'k' }
    @{ Id = 'notContainsKey'; Operator = 'notContainsKey'; Value = 'k' }
    @{ Id = 'greaterStr'; Operator = 'greater'; Value = 'm' }
    @{ Id = 'greaterOrEqualsStr'; Operator = 'greaterOrEquals'; Value = 'm' }
    @{ Id = 'lessStr'; Operator = 'less'; Value = 'm' }
    @{ Id = 'lessOrEqualsStr'; Operator = 'lessOrEquals'; Value = 'm' }
    @{ Id = 'greaterNum'; Operator = 'greater'; Value = 5 }
    @{ Id = 'lessNum'; Operator = 'less'; Value = 5 }
    @{ Id = 'existsTrue'; Operator = 'exists'; Value = $true }
    @{ Id = 'existsFalse'; Operator = 'exists'; Value = $false }
)

function Get-VerificationCase {
    $index = 0
    foreach ($fieldKey in $fields.Keys) {
        foreach ($op in $operators) {
            $index++
            [pscustomobject]@{
                Number         = $index
                DefinitionName = '{0}-{1:d3}' -f $prefix, $index
                ReferenceId    = '{0}-{1}' -f $fieldKey, $op.Id
                FieldKey       = $fieldKey
                Field          = $fields[$fieldKey]
                OperatorId     = $op.Id
                Operator       = $op.Operator
                Value          = $op.Value
            }
        }
    }
}

function ConvertTo-CaseRuleJson {
    param([Parameter(Mandatory)] $Case)

    $condition = [ordered]@{ field = $Case.Field }
    $condition[$Case.Operator] = $Case.Value

    $rule = [ordered]@{
        if   = [ordered]@{
            allOf = @(
                [ordered]@{ field = 'type'; equals = 'Microsoft.Network/routeTables' }
                [ordered]@{ field = 'name'; equals = $routeTableName }
                $condition
            )
        }
        then = [ordered]@{ effect = 'audit' }
    }
    $rule | ConvertTo-Json -Depth 20 -Compress
}

function Invoke-Deploy {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Create resource group and route table')) {
        $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
        $routeTable = @{
            ResourceGroupName = $ResourceGroupName
            ResourceType      = 'Microsoft.Network/routeTables'
            ResourceName      = $routeTableName
            Location          = $Location
            Properties        = @{}
            Tag               = $tags
            ApiVersion        = '2023-09-01'
            Force             = $true
        }
        $null = New-AzResource @routeTable
        Write-Information "Created route table $routeTableName in $ResourceGroupName."
    }

    $members = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[object]]::new()
    foreach ($case in Get-VerificationCase) {
        if (-not $PSCmdlet.ShouldProcess($case.DefinitionName, 'Create policy definition')) {
            continue
        }
        $definition = @{
            Name           = $case.DefinitionName
            SubscriptionId = $SubscriptionId
            DisplayName    = "Bylaw verify: $($case.ReferenceId)"
            Description    = "Field $($case.Field), operator $($case.Operator)."
            Mode           = 'All'
            Metadata       = '{"category":"Bylaw verification"}'
            Policy         = ConvertTo-CaseRuleJson -Case $case
        }
        try {
            $null = New-AzPolicyDefinition @definition
            $members.Add([ordered]@{
                    policyDefinitionId          = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyDefinitions/$($case.DefinitionName)"
                    policyDefinitionReferenceId = $case.ReferenceId
                })
        }
        catch {
            # A rejected definition is itself a result (e.g. operator not valid for the field).
            $rejected.Add([pscustomobject]@{ ReferenceId = $case.ReferenceId; Error = $_.Exception.Message })
            Write-Warning "Definition $($case.DefinitionName) ($($case.ReferenceId)) was rejected: $($_.Exception.Message)"
        }
    }

    $rejectedPath = Join-Path $OutputPath 'missing-field-rejected.json'
    $rejected | ConvertTo-Json -Depth 5 | Set-Content -Path $rejectedPath -Encoding utf8NoBOM

    if ($members.Count -eq 0) {
        throw 'No policy definitions were created; nothing to assign.'
    }

    if ($PSCmdlet.ShouldProcess($setName, 'Create initiative and assign it')) {
        $set = @{
            Name             = $setName
            SubscriptionId   = $SubscriptionId
            DisplayName      = 'Bylaw missing-field verification'
            Metadata         = '{"category":"Bylaw verification"}'
            PolicyDefinition = ConvertTo-Json -InputObject $members.ToArray() -Depth 5 -Compress
        }
        $setDefinition = New-AzPolicySetDefinition @set

        $assignment = @{
            Name             = $assignmentName
            Scope            = $scope
            DisplayName      = 'Bylaw missing-field verification'
            PolicyDefinition = $setDefinition
        }
        $null = New-AzPolicyAssignment @assignment
    }

    Write-Information "Deployed $($members.Count) definitions ($($rejected.Count) rejected, see $rejectedPath)."
    Write-Information 'Wait 15-30 minutes, then run with -Action Collect.'
}

function ConvertTo-ConditionResult {
    param([string] $ComplianceState)

    switch ($ComplianceState) {
        'NonCompliant' { 'true' }
        'Compliant' { 'false' }
        '' { 'missing' }
        default { $ComplianceState }
    }
}

function Invoke-Collect {
    Write-Information "Starting compliance scan of $ResourceGroupName (this can take several minutes)."
    Start-AzPolicyComplianceScan -ResourceGroupName $ResourceGroupName

    $stateQuery = @{
        SubscriptionId       = $SubscriptionId
        ResourceGroupName    = $ResourceGroupName
        PolicyAssignmentName = $assignmentName
        Filter               = "ResourceType eq 'Microsoft.Network/routeTables'"
    }
    $states = @(Get-AzPolicyState @stateQuery)
    $byReference = @{}
    foreach ($state in $states) {
        $byReference[$state.PolicyDefinitionReferenceId] = $state.ComplianceState
    }

    $rejectedPath = Join-Path $OutputPath 'missing-field-rejected.json'
    $rejectedById = @{}
    if (Test-Path $rejectedPath) {
        $rejectedJson = Get-Content -Path $rejectedPath -Raw
        if ($rejectedJson.Trim()) {
            foreach ($item in @($rejectedJson | ConvertFrom-Json)) {
                $rejectedById[$item.ReferenceId] = $item.Error
            }
        }
    }

    $results = foreach ($case in Get-VerificationCase) {
        $result = if ($rejectedById.ContainsKey($case.ReferenceId)) {
            'rejected'
        }
        else {
            ConvertTo-ConditionResult -ComplianceState ([string] $byReference[$case.ReferenceId])
        }
        [pscustomobject]@{
            FieldKey   = $case.FieldKey
            Field      = $case.Field
            OperatorId = $case.OperatorId
            Operator   = $case.Operator
            Value      = $case.Value
            Result     = $result
        }
    }

    $jsonPath = Join-Path $OutputPath 'missing-field-results.json'
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding utf8NoBOM

    $fieldKeys = @($fields.Keys)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Azure Policy missing-field verification')
    $lines.Add('')
    $lines.Add("Collected $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. Cell = whether the condition evaluated true.")
    $lines.Add('`true` = NonCompliant, `false` = Compliant, `missing` = no state yet (re-run Collect), `rejected` = definition refused by Azure.')
    $lines.Add('')
    $lines.Add('Fields:')
    foreach ($key in $fieldKeys) {
        $lines.Add("- **$key**: ``$($fields[$key])``")
    }
    $lines.Add('')
    $lines.Add('| Operator | Value | ' + ($fieldKeys -join ' | ') + ' |')
    $lines.Add('|---|---|' + ('---|' * $fieldKeys.Count))
    foreach ($op in $operators) {
        $cells = foreach ($key in $fieldKeys) {
            ($results | Where-Object { $_.FieldKey -eq $key -and $_.OperatorId -eq $op.Id }).Result
        }
        $value = ConvertTo-Json -InputObject $op.Value -Compress
        $lines.Add("| $($op.Operator) | ``$value`` | " + ($cells -join ' | ') + ' |')
    }

    $markdownPath = Join-Path $OutputPath 'missing-field-results.md'
    ($lines -join "`n") + "`n" | Set-Content -Path $markdownPath -Encoding utf8NoBOM -NoNewline

    $pending = @($results | Where-Object Result -EQ 'missing').Count
    Write-Information "Wrote $markdownPath and $jsonPath."
    if ($pending -gt 0) {
        Write-Warning "$pending cases have no compliance state yet. Wait and run -Action Collect again."
    }
}

function Invoke-Remove {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

    if ($PSCmdlet.ShouldProcess($assignmentName, 'Remove policy assignment')) {
        Remove-AzPolicyAssignment -Name $assignmentName -Scope $scope -ErrorAction SilentlyContinue
    }
    if ($PSCmdlet.ShouldProcess($setName, 'Remove initiative')) {
        Remove-AzPolicySetDefinition -Name $setName -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
    }
    foreach ($case in Get-VerificationCase) {
        if ($PSCmdlet.ShouldProcess($case.DefinitionName, 'Remove policy definition')) {
            Remove-AzPolicyDefinition -Name $case.DefinitionName -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
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
    'Collect' { Invoke-Collect }
    'Remove' { Invoke-Remove }
}
