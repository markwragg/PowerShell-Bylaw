function Build-Bylaw {
    <#
    .SYNOPSIS
        Compiles *.bylaw.ps1 files to Azure Policy definition files.

    .DESCRIPTION
        Finds *.bylaw.ps1 files under -Path (recursively), compiles each one in a fresh runspace,
        and writes one file per policy to -OutputPath, mirroring the source folder structure.

        Every file is compiled and every error is reported before the build fails. If anything
        fails, no files are written.

        Compiling a policy file runs it: .bylaw.ps1 files are PowerShell scripts and run with your
        permissions. Don't build files you don't trust.

    .PARAMETER Path
        Source files or folders. Defaults to the current folder.

    .PARAMETER OutputPath
        Output folder. Required unless -PassThru is used.

    .PARAMETER Format
        Output format. Epac (the default) writes EPAC policy definition files.

    .PARAMETER PassThru
        Returns one result per policy: Name, SourceFile, SourceLine, OutputFile, Json, Warnings.
        Without -OutputPath, compiles in memory and writes nothing.

    .PARAMETER Settings
        Path to a bylaw.json settings file. By default, the nearest bylaw.json at or above -Path
        is used, up to the repository root.

    .PARAMETER AliasCachePath
        Alias snapshot to resolve and validate aliases against, instead of the default.

    .PARAMETER AllowUnknownAlias
        Reports unknown aliases as warnings instead of errors, for the whole build.

    .EXAMPLE
        Build-Bylaw -Path ./policies -OutputPath ./Definitions/policyDefinitions

    .EXAMPLE
        Build-Bylaw -Path ./policies/storage.bylaw.ps1 -PassThru | Select-Object Name, Json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Bylaw.BuildResult')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path = '.',

        [Parameter(Position = 1)]
        [string] $OutputPath,

        [ValidateSet('Epac')]
        [string] $Format = 'Epac',

        [switch] $PassThru,

        [string] $Settings,

        [string] $AliasCachePath,

        [switch] $AllowUnknownAlias
    )

    begin {
        $paths = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Path) {
            $paths.Add($item)
        }
    }

    end {
        if (-not $OutputPath -and -not $PassThru) {
            $PSCmdlet.ThrowTerminatingError((New-BylawErrorRecord -Message 'Specify -OutputPath, or -PassThru to compile in memory.' -Id 'BylawOutputPathRequired' -Category InvalidArgument))
        }
        if ($paths.Count -eq 0) {
            $paths.Add('.')
        }
        $emitter = Get-BylawEmitter -Format $Format

        # Discovery (ADR-0013).
        $discovery = Find-BylawSourceFile -Path $paths.ToArray()
        if ($discovery.Diagnostics.Count -gt 0) {
            $PSCmdlet.ThrowTerminatingError((New-BylawBuildErrorRecord -Diagnostics $discovery.Diagnostics))
        }
        $sources = $discovery.Files
        if ($sources.Count -eq 0) {
            Write-Warning "No *.bylaw.ps1 files found in: $($paths -join ', ')"
            return
        }

        # Settings (ADR-0012) and alias snapshot (ADR-0008), read once for the whole build.
        $settingsPath = if ($Settings) { $Settings } else { Find-BylawSettingsFile -StartPath $sources[0].Root }
        $settingsResult = Read-BylawSettingsFile -Path $settingsPath
        if ($settingsResult.Diagnostics.Count -gt 0) {
            $PSCmdlet.ThrowTerminatingError((New-BylawBuildErrorRecord -Diagnostics $settingsResult.Diagnostics))
        }
        if ($settingsResult.Settings.Path) {
            Write-Verbose "Settings: $($settingsResult.Settings.Path) (language version $($settingsResult.Settings.LanguageVersion))"
        }
        try {
            $snapshotPath = Resolve-BylawAliasSnapshotPath -AliasCachePath $AliasCachePath -SettingsAliasCache $settingsResult.Settings.AliasCache
            $snapshotData = Read-BylawAliasSnapshotData -Path $snapshotPath
        }
        catch {
            $PSCmdlet.ThrowTerminatingError((New-BylawErrorRecord -Message $_.Exception.Message -Id 'BylawAliasSnapshot' -Category ObjectNotFound))
        }
        Write-Verbose "Alias snapshot: $($snapshotData.Path)"

        # Compile every file, one runspace each (ADR-0014).
        $diagnostics = [System.Collections.Generic.List[object]]::new()
        $compiled = [System.Collections.Generic.List[object]]::new()
        foreach ($source in $sources) {
            Write-Verbose "Compiling $($source.Relative)"
            $result = Invoke-BylawFileInRunspace -File $source.File -SnapshotData $snapshotData -AllowUnknownAlias $AllowUnknownAlias.IsPresent -Format $emitter.Name
            $diagnostics.AddRange([object[]] @($result.Diagnostics))
            foreach ($policy in $result.Policies) {
                $diagnostics.AddRange([object[]] @($policy.Diagnostics))
                $compiled.Add([pscustomobject]@{ Source = $source; Policy = $policy; FileDiagnostics = $result.Diagnostics })
            }
            if ($result.Policies.Count -eq 0 -and $result.Diagnostics.Count -eq 0) {
                $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Warning, 'BYL5021', 'The file contains no Policy blocks.', [BylawSourceLocation]::new($source.File, 0, 0, $null)))
            }
        }

        # Names are unique across the build, ignoring case (ADR-0013).
        $names = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $compiled) {
            $name = $entry.Policy.Name
            if ($names.ContainsKey($name)) {
                $first = $names[$name]
                $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL5020', "Policy name '$name' is already used at $($first.Source.File):$($first.Policy.Line). Names must be unique across a build, ignoring case.", [BylawSourceLocation]::new($entry.Source.File, $entry.Policy.Line, 0, 'Policy')))
            }
            else {
                $names[$name] = $entry
            }
        }

        foreach ($warning in $diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Warning)) {
            Write-Warning $warning.ToString()
        }
        $errors = @($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error))
        if ($errors.Count -gt 0) {
            # No partial output: nothing is written when any file fails.
            $PSCmdlet.ThrowTerminatingError((New-BylawBuildErrorRecord -Diagnostics $errors))
        }

        # Output, mirroring the source folders (ADR-0011).
        $outputRoot = if ($OutputPath) { $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath) } else { $null }
        foreach ($entry in $compiled) {
            $outputFile = $null
            if ($outputRoot) {
                $folder = [System.IO.Path]::GetDirectoryName($entry.Source.Relative)
                $outputFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($outputRoot, $folder, $entry.Policy.Name + $emitter.FileExtension))
            }
            $entry | Add-Member -NotePropertyName OutputFile -NotePropertyValue $outputFile
        }

        if ($outputRoot) {
            $produced = [System.Collections.Generic.HashSet[string]]::new([string[]] @($compiled.OutputFile), [System.StringComparer]::OrdinalIgnoreCase)
            if ([System.IO.Directory]::Exists($outputRoot)) {
                $existing = [System.IO.Directory]::GetFiles($outputRoot, '*' + $emitter.FileExtension, [System.IO.SearchOption]::AllDirectories)
                foreach ($stale in ($existing | Sort-Object -Culture ([cultureinfo]::InvariantCulture))) {
                    if (-not $produced.Contains($stale)) {
                        Write-Warning "$stale BYL5030: This file was not produced by this build. Bylaw never deletes output; remove it if its policy is gone."
                    }
                }
            }
            $encoding = [System.Text.UTF8Encoding]::new($false)
            foreach ($entry in $compiled) {
                $file = $entry.OutputFile
                if ([System.IO.File]::Exists($file) -and [System.IO.File]::ReadAllText($file, $encoding) -ceq $entry.Policy.Text) {
                    Write-Verbose "Unchanged $file"
                    continue
                }
                if ($PSCmdlet.ShouldProcess($file, 'Write policy definition')) {
                    $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($file))
                    [System.IO.File]::WriteAllText($file, $entry.Policy.Text, $encoding)
                }
            }
        }

        if ($PassThru) {
            foreach ($entry in $compiled) {
                $warnings = @(@($entry.FileDiagnostics) + @($entry.Policy.Diagnostics) | Where-Object Severity -EQ ([BylawSeverity]::Warning) | ForEach-Object { $_.ToString() })
                [pscustomobject]@{
                    PSTypeName = 'Bylaw.BuildResult'
                    Name       = $entry.Policy.Name
                    SourceFile = $entry.Source.File
                    SourceLine = $entry.Policy.Line
                    OutputFile = $entry.OutputFile
                    Json       = $entry.Policy.Text
                    Warnings   = [string[]] $warnings
                }
            }
        }
    }
}
