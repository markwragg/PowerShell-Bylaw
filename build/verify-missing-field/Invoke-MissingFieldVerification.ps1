#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.PolicyInsights'; ModuleVersion = '1.6.0' }

<#
.SYNOPSIS
    Measures Azure Policy behaviour that Microsoft Learn doesn't document, for Bylaw's ADRs.

.DESCRIPTION
    Developer-only script that supports ADR-0004, ADR-0024 and ADR-0025. It is not part of the
    Bylaw module.

    It measures three things:
      Fields:      how each operator evaluates against present, empty and missing fields (ADR-0004).
      Expressions: how a missing or empty resource group tag compares in a value condition (ADR-0025).
      Modify:      whether Audit is accepted as the effect of a definition with a modify details
                   block, and whether it then reports compliance (ADR-0024).

    Deploy:  creates a resource group (tagged) with one route table (free) carrying known tags,
             one Audit-effect policy definition per field and expression case, an initiative
             containing them and an assignment of it to the resource group. Also creates one
             Modify definition and assigns it separately, with its effect set to Audit.
    Collect: triggers an on-demand compliance scan and records, for each case, whether the
             condition evaluated true (NonCompliant), false (Compliant) or something else.
             Writes a JSON and a Markdown report.
    Remove:  deletes the assignments, initiative, definitions and resource group.

    Each rule is: type equals routeTables AND name equals <route table> AND <case condition>.
    So NonCompliant means "<case condition> evaluated true" and Compliant means "false".

    Run Deploy, wait 15-30 minutes for the assignments to take effect, then run Collect
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
    Additional full field or alias names to test, for example a route-table alias that is present
    but null.

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
$modifyDefinitionName = "$prefix-modify-audit"
$modifyAssignmentName = "$prefix-modify-audit"

# Fields under test. Tags are fully controllable. A route table with no associated subnets has no
# 'subnets' property, so it is a missing alias of the resource's own type. (An alias of another
# resource type is never evaluated at all, so it can't be used as a missing field: ADR-0004.)
# ExtraField adds anything else the caller wants to probe.
$fields = [ordered]@{
    tagPresent   = "tags['bylawPresent']"
    tagEmpty     = "tags['bylawEmpty']"
    tagMissing   = "tags['bylawMissing']"
    aliasMissing = 'Microsoft.Network/routeTables/subnets'
}
$extraIndex = 0
foreach ($extra in $ExtraField) {
    $extraIndex++
    $fields["extra$extraIndex"] = $extra
}

# The same tag names go on the route table and on the resource group.
$tags = @{
    bylawPresent = 'abc'
    bylawEmpty   = ''
}

# Operator cases for fields. Values are chosen so the tagPresent control ('abc') has a known answer.
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

# Expressions under test, as value conditions (ADR-0025). The built-in tag inheritance policies
# assume a missing resource group tag compares equal to ''.
$expressions = [ordered]@{
    rgTagPresent = "[resourceGroup().tags['bylawPresent']]"
    rgTagEmpty   = "[resourceGroup().tags['bylawEmpty']]"
    rgTagMissing = "[resourceGroup().tags['bylawMissing']]"
}
$expressionOperators = @(
    @{ Id = 'equalsValue'; Operator = 'equals'; Value = 'abc' }
    @{ Id = 'equalsEmpty'; Operator = 'equals'; Value = '' }
    @{ Id = 'notEqualsEmpty'; Operator = 'notEquals'; Value = '' }
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
                Kind           = 'field'
                SubjectKey     = $fieldKey
                Subject        = $fields[$fieldKey]
                OperatorId     = $op.Id
                Operator       = $op.Operator
                Value          = $op.Value
            }
        }
    }
    foreach ($expressionKey in $expressions.Keys) {
        foreach ($op in $expressionOperators) {
            $index++
            [pscustomobject]@{
                Number         = $index
                DefinitionName = '{0}-{1:d3}' -f $prefix, $index
                ReferenceId    = '{0}-{1}' -f $expressionKey, $op.Id
                Kind           = 'value'
                SubjectKey     = $expressionKey
                Subject        = $expressions[$expressionKey]
                OperatorId     = $op.Id
                Operator       = $op.Operator
                Value          = $op.Value
            }
        }
    }
}

function Get-RouteTableCondition {
    @(
        [ordered]@{ field = 'type'; equals = 'Microsoft.Network/routeTables' }
        [ordered]@{ field = 'name'; equals = $routeTableName }
    )
}

function ConvertTo-CaseRuleJson {
    param([Parameter(Mandatory)] $Case)

    $condition = [ordered]@{}
    $condition[$Case.Kind] = $Case.Subject
    $condition[$Case.Operator] = $Case.Value

    $rule = [ordered]@{
        if   = [ordered]@{ allOf = @(Get-RouteTableCondition) + @($condition) }
        then = [ordered]@{ effect = 'audit' }
    }
    $rule | ConvertTo-Json -Depth 20 -Compress
}

function ConvertTo-ModifyRuleJson {
    # The route table has no 'bylawMissing' tag, so with effect Audit it should be NonCompliant.
    $rule = [ordered]@{
        if   = [ordered]@{
            allOf = @(Get-RouteTableCondition) + @([ordered]@{ field = "tags['bylawMissing']"; exists = $false })
        }
        then = [ordered]@{
            effect  = "[parameters('effect')]"
            details = [ordered]@{
                roleDefinitionIds = @('/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f')
                operations        = @(
                    [ordered]@{ operation = 'add'; field = "tags['bylawMissing']"; value = 'added' }
                )
            }
        }
    }
    $rule | ConvertTo-Json -Depth 20 -Compress
}

function Invoke-Deploy {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Create resource group and route table')) {
        $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $tags -Force
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
            Description    = "$($case.Kind) $($case.Subject), operator $($case.Operator)."
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

    # The Modify check has its own assignment, so a failure here can't affect the other cases.
    # The definition and the assignment are recorded separately, because either can be refused.
    if ($PSCmdlet.ShouldProcess($modifyDefinitionName, 'Create Modify definition and assign it with effect Audit')) {
        $modifyDefinition = $null
        $modifyParameters = [ordered]@{
            effect = [ordered]@{
                type          = 'String'
                allowedValues = @('Modify', 'Audit', 'Disabled')
                defaultValue  = 'Modify'
            }
        }
        $definition = @{
            Name           = $modifyDefinitionName
            SubscriptionId = $SubscriptionId
            DisplayName    = 'Bylaw verify: Modify definition with effect Audit'
            Mode           = 'Indexed'
            Metadata       = '{"category":"Bylaw verification"}'
            Parameter      = ConvertTo-Json -InputObject $modifyParameters -Depth 5 -Compress
            Policy         = ConvertTo-ModifyRuleJson
        }
        try {
            $modifyDefinition = New-AzPolicyDefinition @definition
        }
        catch {
            $rejected.Add([pscustomobject]@{ ReferenceId = 'modifyAudit-definition'; Error = $_.Exception.Message })
            Write-Warning "The Modify definition was rejected: $($_.Exception.Message)"
        }
        if ($modifyDefinition) {
            $assignment = @{
                Name                  = $modifyAssignmentName
                Scope                 = $scope
                DisplayName           = 'Bylaw verify: Modify definition with effect Audit'
                PolicyDefinition      = $modifyDefinition
                PolicyParameterObject = @{ effect = 'Audit' }
            }
            try {
                $null = New-AzPolicyAssignment @assignment
            }
            catch {
                $rejected.Add([pscustomobject]@{ ReferenceId = 'modifyAudit-assignment'; Error = $_.Exception.Message })
                Write-Warning "The Modify assignment with effect Audit was rejected: $($_.Exception.Message)"
            }
        }
    }

    $rejectedPath = Join-Path $OutputPath 'missing-field-rejected.json'
    # Always write the file (as [] when nothing was rejected) so Collect can tell "none rejected"
    # apart from "Deploy output not found".
    ConvertTo-Json -InputObject @($rejected) -Depth 5 | Set-Content -Path $rejectedPath -Encoding utf8NoBOM

    Write-Information "Deployed $($members.Count) case definitions and the Modify check ($($rejected.Count) rejected, see $rejectedPath)."
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

function Get-AssignmentState {
    param([Parameter(Mandatory)] [string] $Name)

    $stateQuery = @{
        SubscriptionId       = $SubscriptionId
        ResourceGroupName    = $ResourceGroupName
        PolicyAssignmentName = $Name
        Filter               = "ResourceType eq 'Microsoft.Network/routeTables'"
    }
    try {
        @(Get-AzPolicyState @stateQuery)
    }
    catch {
        Write-Warning "No compliance states for assignment ${Name}: $($_.Exception.Message)"
        @()
    }
}

function Add-ResultTable {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]] $Lines,
        [Parameter(Mandatory)] [object[]] $Results,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Subjects,
        [Parameter(Mandatory)] [object[]] $Operators
    )

    $keys = @($Subjects.Keys)
    $Lines.Add('| Operator | Value | ' + ($keys -join ' | ') + ' |')
    $Lines.Add('|---|---|' + ('---|' * $keys.Count))
    foreach ($op in $Operators) {
        $cells = foreach ($key in $keys) {
            ($Results | Where-Object { $_.SubjectKey -eq $key -and $_.OperatorId -eq $op.Id }).Result
        }
        $value = ConvertTo-Json -InputObject $op.Value -Compress
        $Lines.Add("| $($op.Operator) | ``$value`` | " + ($cells -join ' | ') + ' |')
    }
}

function Invoke-Collect {
    Write-Information "Starting compliance scan of $ResourceGroupName (this can take several minutes)."
    Start-AzPolicyComplianceScan -ResourceGroupName $ResourceGroupName

    $byReference = @{}
    foreach ($state in Get-AssignmentState -Name $assignmentName) {
        $byReference[$state.PolicyDefinitionReferenceId] = $state.ComplianceState
    }
    $modifyStates = @(Get-AssignmentState -Name $modifyAssignmentName)
    $modifyState = if ($modifyStates.Count -gt 0) { [string] $modifyStates[0].ComplianceState } else { '' }

    $rejectedPath = Join-Path $OutputPath 'missing-field-rejected.json'
    $rejectedById = @{}
    if (Test-Path $rejectedPath) {
        $rejectedJson = Get-Content -Path $rejectedPath -Raw
        if ($rejectedJson -and $rejectedJson.Trim()) {
            foreach ($item in @($rejectedJson | ConvertFrom-Json)) {
                $rejectedById[$item.ReferenceId] = $item.Error
            }
        }
    }
    else {
        Write-Warning "$rejectedPath not found: rejected definitions will be reported as 'missing'. Use the same -OutputPath as Deploy."
    }

    $results = @(foreach ($case in Get-VerificationCase) {
            $result = if ($rejectedById.ContainsKey($case.ReferenceId)) {
                'rejected'
            }
            else {
                ConvertTo-ConditionResult -ComplianceState ([string] $byReference[$case.ReferenceId])
            }
            [pscustomobject]@{
                Kind       = $case.Kind
                SubjectKey = $case.SubjectKey
                Subject    = $case.Subject
                OperatorId = $case.OperatorId
                Operator   = $case.Operator
                Value      = $case.Value
                Result     = $result
            }
        })

    $modifyResult = if ($rejectedById.ContainsKey('modifyAudit-definition')) {
        "definition rejected: $($rejectedById['modifyAudit-definition'])"
    }
    elseif ($rejectedById.ContainsKey('modifyAudit-assignment')) {
        "assignment rejected: $($rejectedById['modifyAudit-assignment'])"
    }
    else {
        ConvertTo-ConditionResult -ComplianceState $modifyState
    }

    $jsonPath = Join-Path $OutputPath 'missing-field-results.json'
    [ordered]@{ cases = $results; modifyAudit = $modifyResult } | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding utf8NoBOM

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Azure Policy verification')
    $lines.Add('')
    $lines.Add("Collected $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. Cell = whether the condition evaluated true.")
    $lines.Add('`true` = NonCompliant, `false` = Compliant, `missing` = no state yet (re-run Collect), `rejected` = definition refused by Azure.')
    $lines.Add('')
    $lines.Add('## Fields')
    $lines.Add('')
    foreach ($key in $fields.Keys) {
        $lines.Add("- **$key**: ``$($fields[$key])``")
    }
    $lines.Add('')
    Add-ResultTable -Lines $lines -Results @($results | Where-Object Kind -EQ 'field') -Subjects $fields -Operators $operators
    $lines.Add('')
    $lines.Add('## Resource group tags in value conditions')
    $lines.Add('')
    foreach ($key in $expressions.Keys) {
        $lines.Add("- **$key**: ``$($expressions[$key])``")
    }
    $lines.Add('')
    Add-ResultTable -Lines $lines -Results @($results | Where-Object Kind -EQ 'value') -Subjects $expressions -Operators $expressionOperators
    $lines.Add('')
    $lines.Add('## Modify definition assigned with effect Audit')
    $lines.Add('')
    $lines.Add('The rule matches the route table, so `true` means Audit was accepted and reports NonCompliant.')
    $lines.Add('')
    $lines.Add("Result: $modifyResult")

    $markdownPath = Join-Path $OutputPath 'missing-field-results.md'
    ($lines -join "`n") + "`n" | Set-Content -Path $markdownPath -Encoding utf8NoBOM -NoNewline

    $pending = @($results | Where-Object Result -EQ 'missing').Count + [int] ($modifyResult -eq 'missing')
    Write-Information "Wrote $markdownPath and $jsonPath."
    if ($pending -gt 0) {
        Write-Warning "$pending cases have no compliance state yet. Wait and run -Action Collect again."
    }
}

function Invoke-Remove {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

    foreach ($name in $assignmentName, $modifyAssignmentName) {
        if ($PSCmdlet.ShouldProcess($name, 'Remove policy assignment')) {
            Remove-AzPolicyAssignment -Name $name -Scope $scope -ErrorAction SilentlyContinue
        }
    }
    if ($PSCmdlet.ShouldProcess($setName, 'Remove initiative')) {
        Remove-AzPolicySetDefinition -Name $setName -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
    }
    $definitionNames = @(Get-VerificationCase | ForEach-Object DefinitionName) + $modifyDefinitionName
    foreach ($name in $definitionNames) {
        if ($PSCmdlet.ShouldProcess($name, 'Remove policy definition')) {
            Remove-AzPolicyDefinition -Name $name -SubscriptionId $SubscriptionId -Force -ErrorAction SilentlyContinue
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
