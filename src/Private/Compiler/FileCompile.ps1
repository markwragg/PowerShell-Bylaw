# Compiling one source file (ADR-0014).
#
# Invoke-BylawFileInRunspace runs in the caller. It creates a fresh runspace, imports Bylaw there,
# runs the file by path, and calls Invoke-BylawFileCompile in that runspace's copy of the module.
# Only plain data crosses back: Bylaw classes don't exist outside the runspace that loaded them.

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

function Invoke-BylawFileInRunspace {
    # Compiles one file in a fresh runspace. Returns the plain result of Invoke-BylawFileCompile,
    # with Diagnostics and each policy's Diagnostics converted back to BylawDiagnostic.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [hashtable] $SnapshotData,
        [bool] $AllowUnknownAlias,
        [string] $Format = 'Epac'
    )

    $manifest = Join-Path -Path $ExecutionContext.SessionState.Module.ModuleBase -ChildPath 'Bylaw.psd1'
    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    if ($IsWindows) {
        # Use the caller's effective policy, e.g. a -ExecutionPolicy Bypass process.
        $initialState.ExecutionPolicy = Get-ExecutionPolicy
    }
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
    $shell = $null
    try {
        $runspace.Open()
        $shell = [powershell]::Create()
        $shell.Runspace = $runspace
        $null = $shell.AddScript($script:BylawFileRunnerScript)
        foreach ($argument in @($manifest, $File, $SnapshotData, $AllowUnknownAlias, $Format)) {
            $null = $shell.AddArgument($argument)
        }

        $output = $null
        $failure = $null
        try {
            $output = @($shell.Invoke()) | Select-Object -Last 1
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
        if ($shell) {
            $shell.Dispose()
        }
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
