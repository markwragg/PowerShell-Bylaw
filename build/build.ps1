#Requires -Version 7.2

<#
.SYNOPSIS
    Build entry point for Bylaw.

.DESCRIPTION
    Tasks (run in the order given):
      Bootstrap  Install the pinned dev dependencies from build/requirements.psd1 (CurrentUser).
      Analyze    Run PSScriptAnalyzer over src, tests and build with the repository settings.
      Test       Run the Pester suite. With -CI, writes NUnit results and fails the process on failure.
      Package    Produce out/Bylaw: the manifest, data files and a single merged Bylaw.psm1.
      UpdateCoverageBadge  Set README.md's coverage badge from out/coverage.xml, written by
                 Test -Coverage.
      Publish    If CHANGELOG.md has a '## !Deploy' line: set the version, package, publish to the
                 PowerShell Gallery with $env:NUGET_API_KEY, and date the changelog (ADR-0036).
      UpdateGolden  Regenerate the expected JSON in the golden folders listed in
                 tests/Golden/GoldenRoots.psd1 after an intentional output change. Review the
                 diff before committing.

    Default: Analyze, Test.

.EXAMPLE
    ./build/build.ps1 -Task Bootstrap, Analyze, Test
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters are used inside nested functions via script scope; PSSA does not track that.')]
[CmdletBinding()]
param(
    [ValidateSet('Bootstrap', 'Analyze', 'Test', 'Package', 'UpdateGolden', 'UpdateCoverageBadge', 'Publish')]
    [string[]] $Task = @('Analyze', 'Test'),

    # Pester paths to run. Defaults to the whole tests folder.
    [string[]] $TestPath,

    # CI mode: NUnit test results in out/, non-zero exit code on failure.
    [switch] $CI,

    # Test with code coverage of src, written to out/coverage.xml (JaCoCo). Takes about twice as long.
    [switch] $Coverage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'src'
$outRoot = Join-Path $repoRoot 'out'
$requirements = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'requirements.psd1')
$coveragePath = Join-Path $outRoot 'coverage.xml'
. (Join-Path $PSScriptRoot 'Release.ps1')

function Import-PinnedModule {
    param([Parameter(Mandatory)] [string] $Name)

    $version = $requirements[$Name]
    Import-Module -Name $Name -RequiredVersion $version -Force -ErrorAction Stop
}

function Invoke-Bootstrap {
    foreach ($name in $requirements.Keys) {
        $version = $requirements[$name]
        $installed = Get-Module -ListAvailable -Name $name |
            Where-Object { $_.Version -eq [version] $version }
        if ($installed) {
            Write-Information "$name $version already installed." -InformationAction Continue
            continue
        }
        $install = @{
            Name            = $name
            RequiredVersion = $version
            Scope           = 'CurrentUser'
            Force           = $true
            SkipPublisherCheck = $true
            AllowClobber    = $true
        }
        Install-Module @install
        Write-Information "Installed $name $version." -InformationAction Continue
    }
}

function Invoke-Analyze {
    Import-PinnedModule -Name 'PSScriptAnalyzer'
    $settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
    $findings = foreach ($folder in 'src', 'tests', 'build') {
        $path = Join-Path $repoRoot $folder
        if (Test-Path $path) {
            Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings
        }
    }
    $findings = @($findings)
    if ($findings.Count -gt 0) {
        $findings |
            Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap |
            Out-String -Width 200 |
            Write-Information -InformationAction Continue
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }
    Write-Information 'PSScriptAnalyzer: no findings.' -InformationAction Continue
}

function Invoke-Test {
    Import-PinnedModule -Name 'Pester'
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = if ($TestPath) { $TestPath } else { Join-Path $repoRoot 'tests' }
    $configuration.Output.Verbosity = 'Detailed'
    if ($CI) {
        $null = New-Item -ItemType Directory -Path $outRoot -Force
        $configuration.Run.Exit = $true
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputFormat = 'NUnitXml'
        $configuration.TestResult.OutputPath = Join-Path $outRoot 'testResults.xml'
    }
    else {
        $configuration.Run.Throw = $true
    }
    if ($Coverage) {
        $null = New-Item -ItemType Directory -Path $outRoot -Force
        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = $sourceRoot
        $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
        $configuration.CodeCoverage.OutputPath = $coveragePath
        $configuration.CodeCoverage.UseBreakpoints = $false
    }
    Invoke-Pester -Configuration $configuration
}

function Invoke-UpdateGolden {
    # Golden files are the expected output beside each source file, so building a golden folder
    # into itself regenerates them. Review the diff before committing.
    Import-Module -Name (Join-Path $sourceRoot 'Bylaw.psd1') -Force -ErrorAction Stop
    $goldenRoots = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'tests/Golden/GoldenRoots.psd1')
    foreach ($golden in $goldenRoots.Roots) {
        $root = Join-Path $repoRoot $golden.Path
        $build = @{ Path = $root; OutputPath = $root; Format = $golden.Format; PassThru = $true }
        if ($golden.ContainsKey('DefinitionScope')) {
            $build.DefinitionScope = $golden.DefinitionScope
        }
        $results = @(Build-Bylaw @build)
        Write-Information "$($golden.Path) ($($golden.Format)): $($results.Count) golden file(s)." -InformationAction Continue
    }
}

function Invoke-Package {
    $manifest = Import-PowerShellDataFile -Path (Join-Path $sourceRoot 'Bylaw.psd1')
    $packageRoot = Join-Path $outRoot 'Bylaw'
    if (Test-Path $packageRoot) {
        Remove-Item -Path $packageRoot -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $packageRoot -Force

    Copy-Item -Path (Join-Path $sourceRoot 'Bylaw.psd1') -Destination $packageRoot
    $dataPath = Join-Path $sourceRoot 'Data'
    if (Test-Path $dataPath) {
        Copy-Item -Path $dataPath -Destination $packageRoot -Recurse
    }

    # Same load order as src/Bylaw.psm1.
    $loadOrder = @('Private/IR', 'Private/Compiler', 'Private/Emitters', 'Private/Keywords', 'Private', 'Public')
    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append("# Bylaw $($manifest.ModuleVersion). Generated by build/build.ps1; do not edit.`n")
    $null = $builder.Append("# Loaded by Bylaw.psm1, which parses it afresh on every import (ADR-0006).`n`n")
    $null = $builder.Append("Set-StrictMode -Version Latest`n")
    foreach ($folder in $loadOrder) {
        $folderPath = Join-Path $sourceRoot $folder
        if (-not (Test-Path $folderPath)) {
            continue
        }
        $files = Get-ChildItem -Path $folderPath -Filter '*.ps1' -File |
            Sort-Object -Property Name -Culture ([cultureinfo]::InvariantCulture)
        foreach ($file in $files) {
            $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $file.FullName).Replace('\', '/')
            $content = [System.IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
            $null = $builder.Append("`n#region $relative`n").Append($content.TrimEnd("`n")).Append("`n#endregion`n")
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $packageRoot 'Bylaw.Module.ps1'), $builder.ToString(), $utf8NoBom)
    $loader = @(
        '#Requires -Version 7.2'
        "# Bylaw $($manifest.ModuleVersion). Generated by build/build.ps1; do not edit."
        '#'
        '# Bylaw.Module.ps1 is parsed afresh on every import, never dot-sourced, so each runspace'
        "# defines its own copy of Bylaw's classes (ADR-0006)."
        ''
        '$tokens = $null'
        '$parseErrors = $null'
        '$path = Join-Path -Path $PSScriptRoot -ChildPath ''Bylaw.Module.ps1'''
        '$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $parseErrors)'
        'if ($parseErrors) {'
        '    throw "${path}: $($parseErrors[0])"'
        '}'
        '. $ast.GetScriptBlock()'
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $packageRoot 'Bylaw.psm1'), $loader, $utf8NoBom)

    $null = Test-ModuleManifest -Path (Join-Path $packageRoot 'Bylaw.psd1') -ErrorAction Stop

    # Smoke test the package in a new process: building the examples must reproduce the goldens.
    $smoke = @'
param($Manifest, $Examples)
$ErrorActionPreference = 'Stop'
Import-Module -Name $Manifest
$failed = @(Build-Bylaw -Path $Examples -PassThru | Where-Object {
    $golden = Join-Path ([System.IO.Path]::GetDirectoryName($_.SourceFile)) ($_.Name + '.json')
    -not [System.IO.File]::Exists($golden) -or [System.IO.File]::ReadAllText($golden) -cne $_.Json
})
if ($failed) { throw "The packaged module does not reproduce: $($failed.Name -join ', ')" }
'@
    $pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    & $pwsh -NoProfile -NonInteractive -Command ([scriptblock]::Create($smoke)) -args (Join-Path $packageRoot 'Bylaw.psd1'), (Join-Path $repoRoot 'examples')
    if ($LASTEXITCODE -ne 0) {
        throw 'The packaged module failed its smoke test.'
    }
    Write-Information "Packaged Bylaw $($manifest.ModuleVersion) to $packageRoot." -InformationAction Continue
}

function Invoke-UpdateCoverageBadge {
    if (-not (Test-Path $coveragePath)) {
        throw "$coveragePath not found. Run the Test task with -Coverage first."
    }
    $percent = Get-CoveragePercent -Report ([xml] [System.IO.File]::ReadAllText($coveragePath))
    $readmePath = Join-Path $repoRoot 'README.md'
    $readme = [System.IO.File]::ReadAllText($readmePath)
    $updated = Get-ReadmeWithCoverage -Readme $readme -Percent $percent
    [System.IO.File]::WriteAllText($readmePath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Information ('Coverage {0:N2}%: the README badge {1}.' -f $percent, $(if ($updated -ceq $readme) { 'is unchanged' } else { 'is updated' })) -InformationAction Continue
}

function Write-GitHubOutput {
    # A step output for later steps in the same GitHub Actions job; ignored outside Actions.
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Value)

    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
}

function Invoke-Publish {
    # Changelog-driven release (ADR-0036): nothing happens without a "## !Deploy" line.
    $changeLogPath = Join-Path $repoRoot 'CHANGELOG.md'
    $changeLog = if (Test-Path $changeLogPath) { [string[]] (Get-Content -Path $changeLogPath) } else { [string[]] @() }
    $request = Get-DeployRequest -ChangeLog $changeLog
    if ($null -eq $request) {
        Write-Information "CHANGELOG.md has no '## !Deploy' line, so nothing is published." -InformationAction Continue
        Write-GitHubOutput -Name 'published' -Value 'false'
        return
    }
    if (-not $env:NUGET_API_KEY) {
        throw "CHANGELOG.md asks for a release, but NUGET_API_KEY is not set. Add it as a repository secret."
    }

    $manifestPath = Join-Path $sourceRoot 'Bylaw.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $published = @(Find-PSResource -Name 'Bylaw' -Repository 'PSGallery' -Prerelease -ErrorAction SilentlyContinue | ForEach-Object {
            $text = "$($_.Version.Major).$($_.Version.Minor).$($_.Version.Build)"
            if ($_.Prerelease) {
                $text += "-$($_.Prerelease)"
            }
            [System.Management.Automation.SemanticVersion]::new($text)
        } | Sort-Object -Descending | Select-Object -First 1)
    $latest = if ($published.Count -gt 0) { $published[0] } else { $null }
    $version = Get-ReleaseVersion -Requested $request.Version -Published $latest -ManifestVersion $manifest.ModuleVersion -ManifestPrerelease ([string] $manifest.PrivateData.PSData.Prerelease)
    Write-Information "Releasing Bylaw $version (newest on the Gallery: $(if ($latest) { $latest } else { 'none' }))." -InformationAction Continue

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $manifestText = Get-VersionedManifest -Manifest ([System.IO.File]::ReadAllText($manifestPath)) -Version $version
    [System.IO.File]::WriteAllText($manifestPath, $manifestText, $utf8NoBom)
    Invoke-Package
    Publish-PSResource -Path (Join-Path $outRoot 'Bylaw') -Repository 'PSGallery' -ApiKey $env:NUGET_API_KEY -ErrorAction Stop

    $released = Get-ReleasedChangeLog -ChangeLog $changeLog -Index $request.Index -Version $version -Date ([datetime]::UtcNow)
    [System.IO.File]::WriteAllText($changeLogPath, (($released -join "`n") + "`n"), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $outRoot 'release-notes.md'), (Get-ChangeLogSection -ChangeLog $released -Version $version) + "`n", $utf8NoBom)
    Write-GitHubOutput -Name 'published' -Value 'true'
    Write-GitHubOutput -Name 'version' -Value "$version"
    Write-Information "Published Bylaw $version to the PowerShell Gallery." -InformationAction Continue
}

foreach ($name in $Task) {
    Write-Information "== $name" -InformationAction Continue
    switch ($name) {
        'Bootstrap' { Invoke-Bootstrap }
        'Analyze' { Invoke-Analyze }
        'Test' { Invoke-Test }
        'Package' { Invoke-Package }
        'UpdateGolden' { Invoke-UpdateGolden }
        'UpdateCoverageBadge' { Invoke-UpdateCoverageBadge }
        'Publish' { Invoke-Publish }
    }
}
