# Shared helpers for Bylaw tests. Dot-source from BeforeAll.

function Invoke-BylawTestScript {
    # Writes a .bylaw.ps1 file to TestDrive, runs it as an author would (from outside the module),
    # and returns the policies and diagnostics collected by the front-end.
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $FileName = 'test.bylaw.ps1'
    )
    $path = Join-Path $TestDrive $FileName
    Set-Content -Path $path -Value $Script -Encoding utf8NoBOM
    InModuleScope Bylaw { Reset-BylawFrontEnd }
    $thrown = $null
    try {
        $null = & $path
    }
    catch {
        $thrown = $_
    }
    InModuleScope Bylaw -Parameters @{ Path = $path; Thrown = $thrown } {
        param($Path, $Thrown)
        [pscustomobject]@{
            Path        = $Path
            Policies    = @(Get-BylawCollectedPolicy)
            Diagnostics = @(Get-BylawFrontEndDiagnostic)
            Codes       = @(Get-BylawFrontEndDiagnostic | ForEach-Object Code)
            Thrown      = $Thrown
        }
    }
}

function Invoke-BylawTestCompile {
    # Front-end plus compiler passes for a .bylaw.ps1 script. Returns the policy, all diagnostics,
    # the compiled policyRule as canonical JSON, and the EPAC emitter result (when it compiled).
    # Emitter diagnostics are in Emitted.Diagnostics, not Diagnostics. Uses the bundled snapshot
    # unless -SnapshotPath is given.
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $SnapshotPath = (Join-Path $PSScriptRoot '../../src/Data/aliases.json'),
        [switch] $AllowUnknownAlias
    )
    $frontEnd = Invoke-BylawTestScript -Script $Script
    InModuleScope Bylaw -Parameters @{ FrontEnd = $frontEnd; SnapshotPath = $SnapshotPath; Allow = $AllowUnknownAlias.IsPresent } {
        param($FrontEnd, $SnapshotPath, $Allow)
        $snapshot = Get-BylawAliasSnapshot -Path $SnapshotPath
        $diagnostics = [System.Collections.Generic.List[object]]::new()
        $diagnostics.AddRange([object[]] @($FrontEnd.Diagnostics))
        $policy = $FrontEnd.Policies | Select-Object -First 1
        $ruleObject = $null
        $ruleJson = $null
        $emitted = $null
        if ($policy -and $FrontEnd.Diagnostics.Count -eq 0) {
            $diagnostics.AddRange([object[]] @(Invoke-BylawCompilerPass -Policy $policy -Snapshot $snapshot -AllowUnknownAlias:$Allow))
            if ($policy.Rule) {
                $ruleObject = ConvertTo-BylawPolicyRuleObject -Policy $policy
                $ruleJson = ConvertTo-BylawJson -InputObject $ruleObject
                $emitted = Invoke-BylawEmitter -Policy $policy -Format Epac
            }
        }
        [pscustomobject]@{
            Policy      = $policy
            Diagnostics = $diagnostics.ToArray()
            Codes       = @($diagnostics | ForEach-Object Code)
            Errors      = @($diagnostics | Where-Object { $_.Severity.ToString() -eq 'Error' } | ForEach-Object Code)
            RuleObject  = $ruleObject
            RuleJson    = $ruleJson
            Emitted     = $emitted
        }
    }
}

function Format-BylawTestCondition {
    # Compact text for a condition object, in the notation of the ADR-0004 truth table:
    # 'anyOf[exists:false, equals]', 'notEquals', 'count>0(where: ...)'.
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Condition)

    foreach ($kind in 'allOf', 'anyOf') {
        if ($Condition.Contains($kind)) {
            $children = foreach ($child in $Condition[$kind]) { Format-BylawTestCondition -Condition $child }
            return "$kind[$($children -join ', ')]"
        }
    }
    if ($Condition.Contains('count')) {
        $where = Format-BylawTestCondition -Condition $Condition['count']['where']
        return "count(where: $where)"
    }
    $operator = @($Condition.Keys | Where-Object { $_ -notin 'field', 'value' })[0]
    if ($operator -eq 'exists') {
        return "exists:$(([string] $Condition[$operator]).ToLowerInvariant())"
    }
    $operator
}

function Get-BylawLeakedKeyword {
    # A Bylaw keyword function still visible outside Policy: defined by Bylaw or by no module.
    # Reads the function: drive so it never auto-loads other modules.
    param([Parameter(Mandatory)] [string] $Name)

    Get-Item -LiteralPath "function:$Name" -ErrorAction SilentlyContinue |
        Where-Object { -not $_.ModuleName -or $_.ModuleName -eq 'Bylaw' }
}

function Format-BylawTestPolicy {
    # Wraps requirement/When text in a minimal valid policy, so tests can focus on one keyword.
    param(
        [string] $Requirements = "Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }",
        [string] $Extra = '',
        [string] $Type = 'Microsoft.Storage/storageAccounts',
        [string] $Properties = "DisplayName = 'Test policy'",
        [string] $Effect = 'Deny'
    )
    @"
Policy 'test-policy' {
    Properties @{ $Properties }
    $Extra
    Resource '$Type' {
        $Requirements
    }
    Effect $Effect
}
"@
}
