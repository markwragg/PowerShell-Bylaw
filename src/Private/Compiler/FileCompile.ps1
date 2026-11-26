# Compiling one source file (ADR-0014).
#
# Invoke-BylawFileInRunspace runs in the caller. For each file it creates a fresh runspace, imports
# Bylaw there, runs the file by path, and calls Invoke-BylawFileCompile in that runspace's copy of
# the module. Several files can compile at once, each in its own runspace; results are returned
# in file order, so output doesn't depend on which finishes first.
# Only plain data crosses back: each runspace defines its own copy of Bylaw's classes (ADR-0006).

# Runs in the new runspace. The file is invoked from outside the module, as an author would run it.
$script:BylawFileRunnerScript = @'
param($ModuleManifest, $File, $SnapshotData, $AllowUnknownAlias, $Format)
Set-Location -LiteralPath ([System.IO.Path]::GetDirectoryName($File))
$module = Import-Module -Name $ModuleManifest -PassThru -Force -ErrorAction Stop
& $module { Reset-BylawFrontEnd }
$thrown = $null
try {
    $null = & $File
}
catch {
    $thrown = $_
}
& $module {
    param($File, $Thrown, $SnapshotData, $AllowUnknownAlias, $Format)
    Invoke-BylawFileCompile -File $File -Thrown $Thrown -SnapshotData $SnapshotData -AllowUnknownAlias $AllowUnknownAlias -Format $Format
} $File $thrown $SnapshotData $AllowUnknownAlias $Format
'@

function Get-BylawDefaultThrottleLimit {
    # Files compiled at once by default: one per processor, at most 16.
    [OutputType([int])]
    param()

    [Math]::Max(1, [Math]::Min([Environment]::ProcessorCount, 16))
}

function Invoke-BylawFileInRunspace {
    # Compiles files, each in its own fresh runspace, up to ThrottleLimit at once. Runspaces are
    # never reused (ADR-0014). Returns one result per file, in the order of -File: the plain result
    # of Invoke-BylawFileCompile, with diagnostics converted back to BylawDiagnostic.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string[]] $File,
        [Parameter(Mandatory)] [hashtable] $SnapshotData,
        [bool] $AllowUnknownAlias,
        [string] $Format = 'Epac',
        [ValidateRange(1, 64)] [int] $ThrottleLimit = 1
    )

    $manifest = Join-Path -Path $ExecutionContext.SessionState.Module.ModuleBase -ChildPath 'Bylaw.psd1'
    # Use the caller's effective policy, e.g. a -ExecutionPolicy Bypass process.
    $executionPolicy = if ($IsWindows) { Get-ExecutionPolicy } else { $null }
    $results = [object[]]::new($File.Count)
    $running = [System.Collections.Generic.List[object]]::new()
    $next = 0
    try {
        while ($next -lt $File.Count -or $running.Count -gt 0) {
            while ($running.Count -lt $ThrottleLimit -and $next -lt $File.Count) {
                $running.Add((Start-BylawFileJob -Index $next -File $File[$next] -Manifest $manifest -ExecutionPolicy $executionPolicy -SnapshotData $SnapshotData -AllowUnknownAlias $AllowUnknownAlias -Format $Format))
                $next++
            }
            # Wait in short slices so Ctrl+C can stop the build.
            $handles = [System.Threading.WaitHandle[]] @($running | ForEach-Object { $_.Async.AsyncWaitHandle })
            $done = [System.Threading.WaitHandle]::WaitAny($handles, 200)
            if ($done -eq [System.Threading.WaitHandle]::WaitTimeout) {
                continue
            }
            $job = $running[$done]
            $running.RemoveAt($done)
            $results[$job.Index] = Complete-BylawFileJob -Job $job
        }
    }
    finally {
        # Only reached with jobs still running when the build is stopped.
        foreach ($job in $running) {
            $job.Shell.Stop()
            $job.Shell.Dispose()
            $job.Runspace.Dispose()
        }
    }
    foreach ($result in $results) {
        $result
    }
}

function Start-BylawFileJob {
    # Starts compiling one file in a new runspace, asynchronously.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts an in-memory runspace only.')]
    param(
        [Parameter(Mandatory)] [int] $Index,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string] $Manifest,
        [AllowNull()] [object] $ExecutionPolicy,
        [Parameter(Mandatory)] [hashtable] $SnapshotData,
        [bool] $AllowUnknownAlias,
        [string] $Format
    )

    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    if ($null -ne $ExecutionPolicy) {
        $initialState.ExecutionPolicy = $ExecutionPolicy
    }
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
    $shell = $null
    try {
        $runspace.Open()
        $shell = [powershell]::Create()
        $shell.Runspace = $runspace
        $null = $shell.AddScript($script:BylawFileRunnerScript)
        foreach ($argument in @($Manifest, $File, $SnapshotData, $AllowUnknownAlias, $Format)) {
            $null = $shell.AddArgument($argument)
        }
        $async = $shell.BeginInvoke()
    }
    catch {
        if ($shell) {
            $shell.Dispose()
        }
        $runspace.Dispose()
        throw
    }
    [pscustomobject]@{ Index = $Index; File = $File; Runspace = $runspace; Shell = $shell; Async = $async }
}

function Complete-BylawFileJob {
    # Collects a finished file job's result and disposes its runspace.
    param([Parameter(Mandatory)] [object] $Job)

    $shell = $Job.Shell
    $runspace = $Job.Runspace
    $File = $Job.File
    try {
        $output = $null
        $failure = $null
        try {
            $output = @($shell.EndInvoke($Job.Async)) | Select-Object -Last 1
        }
        catch {
            $failure = $_.Exception.InnerException ?? $_.Exception
        }

        $diagnostics = [System.Collections.Generic.List[object]]::new()
        $policies = @()
        if ($null -ne $output) {
            foreach ($plain in $output.Diagnostics) {
                $diagnostics.Add((ConvertFrom-BylawPlainDiagnostic -Plain $plain))
            }
            $policies = @(foreach ($policy in $output.Policies) {
                    [pscustomobject]@{
                        Name        = $policy.Name
                        Line        = $policy.Line
                        Text        = $policy.Text
                        Diagnostics = @($policy.Diagnostics | ForEach-Object { ConvertFrom-BylawPlainDiagnostic -Plain $_ })
                    }
                })
        }
        foreach ($record in $shell.Streams.Error) {
            $diagnostics.Add((ConvertTo-BylawErrorRecordDiagnostic -ErrorRecord $record -File $File -Code 'BYL5011' -Prefix 'The file wrote an error'))
        }
        if ($failure) {
            $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL5012', "The file could not be compiled: $($failure.Message)", [BylawSourceLocation]::new($File, 0, 0, $null)))
        }
        [pscustomobject]@{
            Diagnostics = $diagnostics.ToArray()
            Policies    = $policies
        }
    }
    finally {
        $shell.Dispose()
        $runspace.Dispose()
    }
}

function Invoke-BylawFileCompile {
    # Runs in the file's runspace, after the file has run: compiles and emits every collected
    # policy. Returns plain data: @{ Diagnostics; Policies = @{ Name; Line; Text; Diagnostics } }.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $File,
        [AllowNull()] [System.Management.Automation.ErrorRecord] $Thrown,
        [Parameter(Mandatory)] [hashtable] $SnapshotData,
        [bool] $AllowUnknownAlias,
        [string] $Format = 'Epac'
    )

    $fileDiagnostics = [System.Collections.Generic.List[object]]::new()
    foreach ($diagnostic in Get-BylawFrontEndDiagnostic) {
        $fileDiagnostics.Add($diagnostic)
    }
    if ($Thrown) {
        # Explain the one way the Param keyword clashes with PowerShell's param block, before
        # PowerShell's own parse errors.
        if ($Thrown.Exception -is [System.Management.Automation.ParseException]) {
            foreach ($hint in Get-BylawParamKeywordHint -File $File) {
                $fileDiagnostics.Add($hint)
            }
        }
        $fileDiagnostics.Add((ConvertTo-BylawErrorRecordDiagnostic -ErrorRecord $Thrown -File $File -Code 'BYL5010' -Prefix 'The file failed'))
    }

    $policies = [System.Collections.Generic.List[object]]::new()
    $frontEndFailed = @($fileDiagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -gt 0
    $snapshot = $null
    foreach ($policy in Get-BylawCollectedPolicy) {
        $diagnostics = [System.Collections.Generic.List[object]]::new()
        $text = $null
        # After a front-end error the IR may be incomplete, so compiling would only add noise.
        if (-not $frontEndFailed) {
            if ($null -eq $snapshot) {
                $snapshot = New-BylawAliasSnapshot -Data $SnapshotData
            }
            foreach ($diagnostic in Invoke-BylawCompilerPass -Policy $policy -Snapshot $snapshot -AllowUnknownAlias:$AllowUnknownAlias) {
                $diagnostics.Add($diagnostic)
            }
            if ($null -ne $policy.Rule -and @($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -eq 0) {
                $emitted = Invoke-BylawEmitter -Policy $policy -Format $Format
                foreach ($diagnostic in $emitted.Diagnostics) {
                    $diagnostics.Add($diagnostic)
                }
                $text = $emitted.Text
            }
        }
        $policies.Add([pscustomobject]@{
                Name        = $policy.Name
                Line        = if ($policy.Location) { $policy.Location.Line } else { 0 }
                Text        = $text
                Diagnostics = @($diagnostics | ForEach-Object { ConvertTo-BylawPlainDiagnostic -Diagnostic $_ })
            })
    }

    [pscustomobject]@{
        Diagnostics = @($fileDiagnostics | ForEach-Object { ConvertTo-BylawPlainDiagnostic -Diagnostic $_ })
        Policies    = $policies.ToArray()
    }
}

function Get-BylawParamKeywordHint {
    # 'param' is a PowerShell keyword at the start of a script block, so Param(Enabled) or
    # Param ('Enabled') as the first statement of a When or Require block is read as a parameter
    # declaration, and the file fails to parse. A real declaration starts with a variable, a type
    # or an attribute, so 'param (' followed by a name or a string is this mistake.
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [string] $File)

    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref] $tokens, [ref] $null)
    $significant = @($tokens | Where-Object { $_.Kind -notin 'NewLine', 'LineContinuation', 'Comment' })
    $nameKinds = @('Identifier', 'Generic', 'StringLiteral', 'StringExpandable')
    for ($index = 0; $index -lt $significant.Count - 2; $index++) {
        if ($significant[$index].Kind -ne 'Param' -or $significant[$index + 1].Kind -ne 'LParen' -or $significant[$index + 2].Kind -notin $nameKinds) {
            continue
        }
        $name = $significant[$index + 2].Text.Trim("'", '"')
        $location = [BylawSourceLocation]::new($File, $significant[$index].Extent.StartLineNumber, $significant[$index].Extent.StartColumnNumber, 'Param')
        [BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL5013', (
                "PowerShell reads 'Param(' at the start of a block as a parameter declaration, so the file can't be parsed. " +
                "To reference the Bylaw parameter, write Param $name without brackets, or (Param $name)."
            ), $location)
    }
}

function ConvertTo-BylawErrorRecordDiagnostic {
    # A diagnostic for a PowerShell error raised by the file outside any Policy block.
    param(
        [Parameter(Mandatory)] [System.Management.Automation.ErrorRecord] $ErrorRecord,
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Prefix
    )

    $invocation = $ErrorRecord.InvocationInfo
    $line = 0
    if ($invocation -and $invocation.ScriptName -and [string]::Equals($invocation.ScriptName, $File, [System.StringComparison]::OrdinalIgnoreCase)) {
        $line = $invocation.ScriptLineNumber
    }
    [BylawDiagnostic]::new([BylawSeverity]::Error, $Code, "${Prefix}: $($ErrorRecord.Exception.Message)", [BylawSourceLocation]::new($File, $line, 0, $null))
}

function ConvertTo-BylawPlainDiagnostic {
    param([Parameter(Mandatory)] [BylawDiagnostic] $Diagnostic)

    $location = $Diagnostic.Location
    [pscustomobject]@{
        Severity = $Diagnostic.Severity.ToString()
        Code     = $Diagnostic.Code
        Message  = $Diagnostic.Message
        File     = if ($location) { $location.File } else { $null }
        Line     = if ($location) { $location.Line } else { 0 }
        Column   = if ($location) { $location.Column } else { 0 }
        Keyword  = if ($location) { $location.Keyword } else { $null }
    }
}

function ConvertFrom-BylawPlainDiagnostic {
    param([Parameter(Mandatory)] [object] $Plain)

    $location = [BylawSourceLocation]::new($Plain.File, $Plain.Line, $Plain.Column, $Plain.Keyword)
    [BylawDiagnostic]::new([BylawSeverity] $Plain.Severity, $Plain.Code, $Plain.Message, $location)
}
