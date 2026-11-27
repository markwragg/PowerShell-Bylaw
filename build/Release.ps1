# Release helpers for build/build.ps1 (ADR-0036). These functions only work on text and versions, so
# tests/Build/Release.Tests.ps1 can test them without the Gallery, git or the file system.

# "## !Deploy" requests a release; "## !Deploy 0.2.0" or "## !Deploy 0.2.0-beta" pins its version.
$script:DeployLinePattern = '^## !Deploy(?:[ \t]+(?<Version>\S+))?[ \t]*$'

# major.minor.patch, then an optional prerelease label of letters and digits, as the Gallery allows.
$script:ReleaseVersionPattern = '^(?<Core>\d+\.\d+\.\d+)(?:-(?<Label>[A-Za-z0-9]+))?$'

function Get-DeployRequest {
    # The "## !Deploy" line of a changelog: $null when there is none, otherwise its line index and
    # the version it pins ('' when it pins none).
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]] $ChangeLog)

    $found = @()
    for ($i = 0; $i -lt $ChangeLog.Count; $i++) {
        if ($ChangeLog[$i] -match $script:DeployLinePattern) {
            $found += [pscustomobject]@{ Index = $i; Version = [string] $Matches['Version'] }
        }
    }
    if ($found.Count -gt 1) {
        throw "CHANGELOG.md has $($found.Count) '## !Deploy' lines. Keep one, above the changes it releases."
    }
    if ($found.Count -eq 0) {
        return $null
    }
    $found[0]
}

function ConvertTo-ReleaseVersion {
    # A version string as a SemanticVersion, or an error that says what the Gallery accepts.
    param([Parameter(Mandatory)] [string] $Version)

    if ($Version -notmatch $script:ReleaseVersionPattern) {
        throw "'$Version' is not a release version. Use major.minor.patch with an optional label of letters and digits, e.g. 0.2.0 or 0.2.0-alpha."
    }
    [System.Management.Automation.SemanticVersion]::new($Version)
}

function Get-ReleaseVersion {
    # The version to release. A pinned version must be newer than the newest one published. Without
    # one, the release is the next patch after the newest published version, with the manifest's
    # prerelease label; the first release uses the manifest's version.
    param(
        [AllowEmptyString()] [string] $Requested,
        [AllowNull()] [System.Management.Automation.SemanticVersion] $Published,
        [Parameter(Mandatory)] [string] $ManifestVersion,
        [AllowEmptyString()] [string] $ManifestPrerelease
    )

    if ($Requested) {
        $version = ConvertTo-ReleaseVersion -Version $Requested
        if ($null -ne $Published -and $version -le $Published) {
            throw "CHANGELOG.md asks to release $version, but $Published is already on the PowerShell Gallery. Use a later version."
        }
        return $version
    }
    $text = if ($null -eq $Published) {
        $ManifestVersion
    }
    else {
        '{0}.{1}.{2}' -f $Published.Major, $Published.Minor, ($Published.Patch + 1)
    }
    if ($ManifestPrerelease) {
        $text += "-$ManifestPrerelease"
    }
    ConvertTo-ReleaseVersion -Version $text
}

function Get-VersionedManifest {
    # The manifest's text with ModuleVersion and the Prerelease label set to Version. A stable
    # version comments out the Prerelease line, so the next prerelease only needs it restored.
    param([Parameter(Mandatory)] [string] $Manifest, [Parameter(Mandatory)] [System.Management.Automation.SemanticVersion] $Version)

    $core = '{0}.{1}.{2}' -f $Version.Major, $Version.Minor, $Version.Patch
    $moduleVersion = [regex]::new("(?m)(?<=^|[\s{;])(ModuleVersion\s*=\s*)'[^']*'")
    if (-not $moduleVersion.IsMatch($Manifest)) {
        throw 'The manifest has no ModuleVersion line.'
    }
    $text = $moduleVersion.Replace($Manifest, "`${1}'$core'", 1)
    $prerelease = [regex]::new("(?m)^(\s*)(?:# )?Prerelease(\s*=\s*)'[^']*'")
    if (-not $prerelease.IsMatch($text)) {
        throw 'The manifest has no Prerelease line in PrivateData.PSData.'
    }
    if ($Version.PreReleaseLabel) {
        return $prerelease.Replace($text, "`${1}Prerelease`${2}'$($Version.PreReleaseLabel)'", 1)
    }
    $prerelease.Replace($text, "`${1}# Prerelease`${2}''", 1)
}

function Get-ReleasedChangeLog {
    # The changelog with its "## !Deploy" line replaced by "## [version] - date".
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $ChangeLog,
        [Parameter(Mandatory)] [int] $Index,
        [Parameter(Mandatory)] [System.Management.Automation.SemanticVersion] $Version,
        [Parameter(Mandatory)] [datetime] $Date
    )

    $lines = [string[]] $ChangeLog.Clone()
    $lines[$Index] = "## [$Version] - $($Date.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture))"
    $lines
}

function Get-ChangeLogSection {
    # The notes under a released version's heading, up to the next version heading.
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $ChangeLog, [Parameter(Mandatory)] [System.Management.Automation.SemanticVersion] $Version)

    $heading = "## [$Version] - "
    $start = [array]::FindIndex($ChangeLog, [Predicate[string]] { param($line) $line.StartsWith($heading, [StringComparison]::Ordinal) })
    if ($start -lt 0) {
        throw "CHANGELOG.md has no section for $Version."
    }
    $end = $start + 1
    while ($end -lt $ChangeLog.Count -and -not $ChangeLog[$end].StartsWith('## ', [StringComparison]::Ordinal)) {
        $end++
    }
    (($ChangeLog[($start + 1)..($end - 1)] | Where-Object { $null -ne $_ }) -join "`n").Trim()
}

function Get-CoveragePercent {
    # The share of commands covered in a JaCoCo report from Pester, as Pester's CoveragePercent.
    param([Parameter(Mandatory)] [xml] $Report)

    $counter = $Report.report.counter | Where-Object type -EQ 'INSTRUCTION'
    if ($null -eq $counter) {
        throw 'The coverage report has no INSTRUCTION counter.'
    }
    $covered = [double] $counter.covered
    $total = $covered + [double] $counter.missed
    if ($total -eq 0) {
        return 0.0
    }
    100.0 * $covered / $total
}

function Get-ReadmeWithCoverage {
    # The README with its shields.io coverage badge set to Percent, rounded down to a whole number.
    param([Parameter(Mandatory)] [string] $Readme, [Parameter(Mandatory)] [double] $Percent)

    $badge = [regex]::new('https://img\.shields\.io/badge/coverage-[0-9.]+%25-[a-z]+\.svg')
    if (-not $badge.IsMatch($Readme)) {
        throw 'README.md has no coverage badge (https://img.shields.io/badge/coverage-<n>%25-<colour>.svg).'
    }
    $whole = [math]::Floor($Percent)
    $colour = if ($whole -ge 90) { 'brightgreen' } elseif ($whole -ge 75) { 'green' } elseif ($whole -ge 60) { 'yellow' } else { 'red' }
    $badge.Replace($Readme, "https://img.shields.io/badge/coverage-$whole%25-$colour.svg", 1)
}
