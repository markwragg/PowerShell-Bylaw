function Build-Bylaw {
    <#
    .SYNOPSIS
        Compiles *.bylaw.ps1 files to Azure Policy definition files.

    .DESCRIPTION
        Finds *.bylaw.ps1 files under -Path (recursively), compiles each one in a fresh runspace,
        and writes one file per policy to -OutputPath, mirroring the source folder structure.
        Initiatives are written the same way, to -InitiativeOutputPath (ADR-0035).

        Every file is compiled and every error is reported before the build fails. If anything
        fails, no files are written.

        Compiling a policy file runs it: .bylaw.ps1 files are PowerShell scripts and run with your
        permissions. Don't build files you don't trust.

    .PARAMETER Path
        Source files or folders. Defaults to the current folder.

    .PARAMETER OutputPath
        Output folder. Required unless -PassThru is used.

    .PARAMETER Format
        Output format:
          Epac (the default) writes EPAC policy definition files (ADR-0011, ADR-0023).
          PlainJson writes { name, properties } definitions, as Azure publishes built-in ones,
          for New-AzPolicyDefinition, the Azure CLI, Bicep or Terraform (ADR-0027). The policy is
          emitted as written: a literal effect stays literal and nothing is generated.

    .PARAMETER InitiativeOutputPath
        Folder for initiatives. Defaults to initiativeOutputPath in bylaw.json, then to -OutputPath.
        For EPAC, use its policySetDefinitions folder (ADR-0035).

    .PARAMETER DefinitionScope
        The scope the build's policies are deployed at, such as
        /providers/Microsoft.Management/managementGroups/contoso. Plain JSON initiatives need it to
        give their members from the build a full policyDefinitionId (ADR-0035). Defaults to
        definitionScope in bylaw.json.

    .PARAMETER PassThru
        Returns one result per policy and initiative: Kind, Name, SourceFile, SourceLine,
        OutputFile, Json, Warnings. Without -OutputPath, compiles in memory and writes nothing.

    .PARAMETER Settings
        Path to a bylaw.json settings file. By default, the nearest bylaw.json at or above -Path
        is used, up to the repository root.

    .PARAMETER AliasCachePath
        Alias snapshot to resolve and validate aliases against, instead of the default.

    .PARAMETER RoleCachePath
        Role map to resolve Modify -Role names against, instead of the default.

    .PARAMETER AllowUnknownAlias
        Reports unknown aliases as warnings instead of errors, for the whole build.

    .PARAMETER ThrottleLimit
        How many files to compile at once, each in its own fresh runspace. Defaults to the number
        of processors, at most 16. Use 1 to compile one file at a time. Output is the same either way.

    .EXAMPLE
        Build-Bylaw -Path ./policies -OutputPath ./Definitions/policyDefinitions

    .EXAMPLE
        Build-Bylaw -Path ./policies/storage.bylaw.ps1 -PassThru | Select-Object Name, Json

    .EXAMPLE
        Build-Bylaw -Path ./policies -OutputPath ./out -Format PlainJson

    .EXAMPLE
        Build-Bylaw ./policies -OutputPath ./Definitions/policyDefinitions -InitiativeOutputPath ./Definitions/policySetDefinitions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Bylaw.BuildResult')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path = '.',

        [Parameter(Position = 1)]
        [string] $OutputPath,

        [string] $InitiativeOutputPath,

        [string] $DefinitionScope,

        [ValidateSet('Epac', 'PlainJson')]
        [string] $Format = 'Epac',

        [switch] $PassThru,

        [string] $Settings,

        [string] $AliasCachePath,

        [string] $RoleCachePath,

        [switch] $AllowUnknownAlias,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit
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

        # Settings (ADR-0012), alias snapshot (ADR-0008) and role map (ADR-0022), read once for the
        # whole build.
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
        try {
            $roleMapPath = Resolve-BylawRoleMapPath -RoleCachePath $RoleCachePath -SettingsRoleCache $settingsResult.Settings.RoleCache
            $roleData = Read-BylawRoleMapData -Path $roleMapPath
        }
        catch {
            $PSCmdlet.ThrowTerminatingError((New-BylawErrorRecord -Message $_.Exception.Message -Id 'BylawRoleMap' -Category ObjectNotFound))
        }
        Write-Verbose "Role map: $($roleData.Path)"

        # The scope for plain JSON initiatives' member IDs (ADR-0035).
        $scope = $settingsResult.Settings.DefinitionScope
        if ($PSBoundParameters.ContainsKey('DefinitionScope')) {
            $problem = Get-BylawDefinitionScopeProblem -Scope $DefinitionScope
            if ($problem) {
                $PSCmdlet.ThrowTerminatingError((New-BylawErrorRecord -Message "BYL5006: -DefinitionScope $problem" -Id 'BylawDefinitionScope' -Category InvalidArgument))
            }
            $scope = $DefinitionScope
        }

        # Compile every file, one fresh runspace each, several at once (ADR-0014).
        # Results come back in file order, so output doesn't depend on which file finishes first.
        $throttle = if ($PSBoundParameters.ContainsKey('ThrottleLimit')) { $ThrottleLimit } else { Get-BylawDefaultThrottleLimit }
        $throttle = [Math]::Min($throttle, $sources.Count)
        Write-Verbose "Compiling $($sources.Count) file(s), up to $throttle at once"
        $results = @(Invoke-BylawFileInRunspace -File @($sources.File) -SnapshotData $snapshotData -RoleData $roleData -AllowUnknownAlias $AllowUnknownAlias.IsPresent -Format $emitter.Name -DefinitionScope $scope -ThrottleLimit $throttle)
        $diagnostics = [System.Collections.Generic.List[object]]::new()
        $compiled = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $sources.Count; $index++) {
            $source = $sources[$index]
            $result = $results[$index]
            Write-Verbose "Compiled $($source.Relative)"
            $diagnostics.AddRange([object[]] @($result.Diagnostics))
            foreach ($policy in $result.Policies) {
                $diagnostics.AddRange([object[]] @($policy.Diagnostics))
                $compiled.Add([pscustomobject]@{ Kind = 'Policy'; Source = $source; Policy = $policy; FileDiagnostics = $result.Diagnostics })
            }
            # An initiative is handled like a policy from here on; only its output folder differs.
            foreach ($initiative in @($result.Initiatives)) {
                $diagnostics.AddRange([object[]] @($initiative.Diagnostics))
                $compiled.Add([pscustomobject]@{ Kind = 'Initiative'; Source = $source; Policy = $initiative; FileDiagnostics = $result.Diagnostics })
            }
            if ($result.Policies.Count -eq 0 -and @($result.Initiatives).Count -eq 0 -and $result.Diagnostics.Count -eq 0) {
                $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Warning, 'BYL5021', 'The file contains no Policy or Initiative blocks.', [BylawSourceLocation]::new($source.File, 0, 0, $null)))
            }
        }

        # Names are unique across the build, ignoring case, for policies and initiatives together
        # (ADR-0013, ADR-0033).
        $names = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $compiled) {
            $name = $entry.Policy.Name
            if ($names.ContainsKey($name)) {
                $first = $names[$name]
                $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL5020', "$($entry.Kind) name '$name' is already used by the $($first.Kind.ToLowerInvariant()) at $($first.Source.File):$($first.Policy.Line). Policy and initiative names must be unique across a build, ignoring case.", [BylawSourceLocation]::new($entry.Source.File, $entry.Policy.Line, 0, $entry.Kind)))
            }
            else {
                $names[$name] = $entry
            }
        }

        # Initiative members against the build's policies, once every file has compiled (ADR-0034).
        # Only when the files compiled cleanly: a policy with errors has nothing reliable to check.
        if (@($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -eq 0) {
            $policyResults = @($compiled | Where-Object Kind -EQ 'Policy' | ForEach-Object Policy)
            $initiativeResults = @($compiled | Where-Object Kind -EQ 'Initiative' | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Policy.Name; File = $_.Source.File; Parameters = $_.Policy.Parameters; Members = $_.Policy.Members }
                })
            foreach ($diagnostic in Test-BylawInitiativeMemberSet -Policies $policyResults -Initiatives $initiativeResults) {
                $diagnostics.Add($diagnostic)
                # -PassThru reports warnings with the initiative they're about: the last one in the
                # file that starts at or before the member's line.
                $owner = $compiled | Where-Object { $_.Kind -eq 'Initiative' -and $_.Source.File -eq $diagnostic.Location.File -and $_.Policy.Line -le $diagnostic.Location.Line } |
                    Sort-Object { $_.Policy.Line } | Select-Object -Last 1
                if ($owner -and $diagnostic.Severity -eq [BylawSeverity]::Warning) {
                    $owner.Policy.Diagnostics = @($owner.Policy.Diagnostics) + $diagnostic
                }
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

        # Output, mirroring the source folders (ADR-0011). Initiatives go to their own folder, which
        # defaults to the policies' one (ADR-0035).
        $outputRoot = if ($OutputPath) { [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)) } else { $null }
        $initiativeRoot = if ($InitiativeOutputPath) {
            [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($InitiativeOutputPath))
        }
        elseif ($settingsResult.Settings.InitiativeOutputPath) {
            $settingsResult.Settings.InitiativeOutputPath
        }
        else {
            $outputRoot
        }
        foreach ($entry in $compiled) {
            $outputFile = $null
            $root = if ($entry.Kind -eq 'Initiative') { $initiativeRoot } else { $outputRoot }
            if ($outputRoot -and $root) {
                $folder = [System.IO.Path]::GetDirectoryName($entry.Source.Relative)
                $outputFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, $folder, $entry.Policy.Name + $emitter.FileExtension))
            }
            $entry | Add-Member -NotePropertyName OutputFile -NotePropertyValue $outputFile
        }

        if ($outputRoot) {
            $produced = [System.Collections.Generic.HashSet[string]]::new([string[]] @($compiled.OutputFile), [System.StringComparer]::OrdinalIgnoreCase)
            # Files a policy reads, such as a deployment template (ADR-0031), are inputs, not stale output.
            foreach ($inputFile in @($compiled | Where-Object Kind -EQ 'Policy' | ForEach-Object { $_.Policy.Inputs })) {
                if ($inputFile) {
                    $null = $produced.Add([System.IO.Path]::GetFullPath($inputFile))
                }
            }
            # Both output folders, each once, and every file in them at most once.
            $roots = @($outputRoot, $initiativeRoot | Where-Object { $_ } | Sort-Object -Unique)
            $existing = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($root in $roots) {
                if ([System.IO.Directory]::Exists($root)) {
                    foreach ($file in [System.IO.Directory]::GetFiles($root, '*' + $emitter.FileExtension, [System.IO.SearchOption]::AllDirectories)) {
                        $null = $existing.Add($file)
                    }
                }
            }
            foreach ($stale in $existing) {
                if (-not $produced.Contains($stale)) {
                    Write-Warning "$stale BYL5030: This file was not produced by this build. Bylaw never deletes output; remove it if its policy or initiative is gone."
                }
            }
            $encoding = [System.Text.UTF8Encoding]::new($false)
            foreach ($entry in $compiled) {
                $file = $entry.OutputFile
                if ([System.IO.File]::Exists($file) -and [System.IO.File]::ReadAllText($file, $encoding) -ceq $entry.Policy.Text) {
                    Write-Verbose "Unchanged $file"
                    continue
                }
                $what = if ($entry.Kind -eq 'Initiative') { 'Write initiative definition' } else { 'Write policy definition' }
                if ($PSCmdlet.ShouldProcess($file, $what)) {
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
                    Kind       = $entry.Kind
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
