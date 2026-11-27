# The release helpers in build/Release.ps1 (ADR-0036): the changelog's Deploy line, the version to
# release, and the text changes to the manifest, changelog and README badge.

BeforeAll {
    . (Join-Path $PSScriptRoot '../../build/Release.ps1')

    function ConvertTo-TestVersion([string] $Text) {
        [System.Management.Automation.SemanticVersion]::new($Text)
    }
}

Describe 'Get-DeployRequest' {
    It 'returns nothing without a Deploy line' {
        Get-DeployRequest -ChangeLog @('# Change Log', '', '## [0.1.0] - 2026-01-01') | Should -BeNullOrEmpty
    }

    It 'returns nothing for an empty changelog' {
        Get-DeployRequest -ChangeLog @() | Should -BeNullOrEmpty
    }

    It 'finds <Line>' -ForEach @(
        @{ Line = '## !Deploy'; Version = '' }
        @{ Line = '## !Deploy 0.2.0'; Version = '0.2.0' }
        @{ Line = '## !Deploy 0.2.0-alpha  '; Version = '0.2.0-alpha' }
    ) {
        $request = Get-DeployRequest -ChangeLog @('# Change Log', '', $Line, '', '* A change')
        $request.Index | Should -Be 2
        $request.Version | Should -BeExactly $Version
    }

    It 'ignores a Deploy line that is not a heading of its own' {
        Get-DeployRequest -ChangeLog @('Write ## !Deploy to release.', '### !Deploy') | Should -BeNullOrEmpty
    }

    It 'refuses two Deploy lines' {
        { Get-DeployRequest -ChangeLog @('## !Deploy', '## !Deploy 0.2.0') } | Should -Throw "*has 2 '## !Deploy' lines*"
    }
}

Describe 'Get-ReleaseVersion' {
    It 'uses a pinned version newer than the published one' {
        "$(Get-ReleaseVersion -Requested '0.2.0' -Published (ConvertTo-TestVersion '0.1.0') -ManifestVersion '0.1.0' -ManifestPrerelease 'alpha')" | Should -BeExactly '0.2.0'
    }

    It 'treats a stable version as newer than its prerelease' {
        "$(Get-ReleaseVersion -Requested '0.1.0' -Published (ConvertTo-TestVersion '0.1.0-alpha') -ManifestVersion '0.1.0' -ManifestPrerelease 'alpha')" | Should -BeExactly '0.1.0'
    }

    It 'uses a pinned version for the first release' {
        "$(Get-ReleaseVersion -Requested '0.1.0-alpha' -Published $null -ManifestVersion '0.1.0' -ManifestPrerelease '')" | Should -BeExactly '0.1.0-alpha'
    }

    It 'refuses a pinned version that is <Case>' -ForEach @(
        @{ Case = 'already published'; Requested = '0.1.0-alpha'; Published = '0.1.0-alpha' }
        @{ Case = 'older'; Requested = '0.1.0'; Published = '0.2.0' }
        @{ Case = 'a prerelease of the published version'; Requested = '0.1.0-beta'; Published = '0.1.0' }
    ) {
        { Get-ReleaseVersion -Requested $Requested -Published (ConvertTo-TestVersion $Published) -ManifestVersion '0.1.0' -ManifestPrerelease '' } | Should -Throw '*is already on the PowerShell Gallery*'
    }

    It 'refuses <Requested>' -ForEach @(
        @{ Requested = '0.2' }, @{ Requested = '0.2.0.1' }, @{ Requested = 'v0.2.0' }, @{ Requested = '0.2.0-alpha.1' }
    ) {
        { Get-ReleaseVersion -Requested $Requested -Published $null -ManifestVersion '0.1.0' -ManifestPrerelease '' } | Should -Throw '*is not a release version*'
    }

    It 'uses the manifest version for a first release without a pin' {
        "$(Get-ReleaseVersion -Requested '' -Published $null -ManifestVersion '0.1.0' -ManifestPrerelease 'alpha')" | Should -BeExactly '0.1.0-alpha'
    }

    It 'takes the next patch, with the manifest label, without a pin' {
        "$(Get-ReleaseVersion -Requested '' -Published (ConvertTo-TestVersion '0.1.0-alpha') -ManifestVersion '0.1.0' -ManifestPrerelease 'alpha')" | Should -BeExactly '0.1.1-alpha'
        "$(Get-ReleaseVersion -Requested '' -Published (ConvertTo-TestVersion '1.2.3') -ManifestVersion '1.2.3' -ManifestPrerelease '')" | Should -BeExactly '1.2.4'
    }
}

Describe 'Get-VersionedManifest' {
    BeforeAll {
        $script:Manifest = "@{`n    ModuleVersion        = '0.1.0'`n    PrivateData          = @{`n        PSData = @{`n            Prerelease = 'alpha'`n        }`n    }`n}`n"
    }

    It 'sets the version and label of a prerelease' {
        $text = Get-VersionedManifest -Manifest $Manifest -Version (ConvertTo-TestVersion '0.2.0-beta')
        $text | Should -Match "(?m)^    ModuleVersion        = '0\.2\.0'$"
        $text | Should -Match "(?m)^            Prerelease = 'beta'$"
    }

    It 'comments out the label for a stable version, and restores it for the next prerelease' {
        $stable = Get-VersionedManifest -Manifest $Manifest -Version (ConvertTo-TestVersion '1.0.0')
        $stable | Should -Match "(?m)^    ModuleVersion        = '1\.0\.0'$"
        $stable | Should -Match "(?m)^            # Prerelease = ''$"
        $next = Get-VersionedManifest -Manifest $stable -Version (ConvertTo-TestVersion '1.1.0-alpha')
        $next | Should -Match "(?m)^            Prerelease = 'alpha'$"
    }

    It 'gives a manifest that PowerShell can read' {
        $data = [scriptblock]::Create((Get-VersionedManifest -Manifest $Manifest -Version (ConvertTo-TestVersion '1.0.0'))).InvokeReturnAsIs()
        $data.ModuleVersion | Should -BeExactly '1.0.0'
        $data.PrivateData.PSData.ContainsKey('Prerelease') | Should -BeFalse
    }

    It 'refuses a manifest without <Missing>' -ForEach @(
        @{ Missing = 'ModuleVersion'; Text = "@{ Prerelease = 'a' }" }
        @{ Missing = 'Prerelease'; Text = "@{ ModuleVersion = '0.1.0' }" }
    ) {
        { Get-VersionedManifest -Manifest $Text -Version (ConvertTo-TestVersion '0.2.0') } | Should -Throw "*no $Missing line*"
    }

    It 'works on the real manifest' {
        $real = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../src/Bylaw.psd1'))
        { Get-VersionedManifest -Manifest $real -Version (ConvertTo-TestVersion '9.9.9-test') } | Should -Not -Throw
    }
}

Describe 'Get-ReleasedChangeLog and Get-ChangeLogSection' {
    BeforeAll {
        $script:ChangeLog = @('# Change Log', '', '## !Deploy 0.2.0', '', '* Added a thing.', '* Fixed a thing.', '', '## [0.1.0] - 2026-01-01', '', '* First release.')
        $script:Released = Get-ReleasedChangeLog -ChangeLog $ChangeLog -Index 2 -Version (ConvertTo-TestVersion '0.2.0') -Date ([datetime]::new(2026, 11, 27))
    }

    It 'dates the Deploy line, leaving the rest' {
        $Released[2] | Should -BeExactly '## [0.2.0] - 2026-11-27'
        $Released.Count | Should -Be $ChangeLog.Count
        $ChangeLog[2] | Should -BeExactly '## !Deploy 0.2.0' -Because 'the input is not changed'
    }

    It 'returns the notes of a release, up to the next one' {
        Get-ChangeLogSection -ChangeLog $Released -Version (ConvertTo-TestVersion '0.2.0') | Should -BeExactly "* Added a thing.`n* Fixed a thing."
    }

    It 'returns the notes of the last release' {
        Get-ChangeLogSection -ChangeLog $Released -Version (ConvertTo-TestVersion '0.1.0') | Should -BeExactly '* First release.'
    }

    It 'refuses a version with no section' {
        { Get-ChangeLogSection -ChangeLog $Released -Version (ConvertTo-TestVersion '0.3.0') } | Should -Throw '*no section for 0.3.0*'
    }
}

Describe 'Get-CoveragePercent and Get-ReadmeWithCoverage' {
    It 'reads the command coverage from a JaCoCo report' {
        $report = [xml] '<report name="Pester"><counter type="INSTRUCTION" missed="25" covered="75" /><counter type="LINE" missed="1" covered="1" /></report>'
        Get-CoveragePercent -Report $report | Should -Be 75
    }

    It 'sets the badge to <Percent>% as <Expected>' -ForEach @(
        @{ Percent = 93.28; Expected = 'coverage-93%25-brightgreen' }
        @{ Percent = 89.99; Expected = 'coverage-89%25-green' }
        @{ Percent = 60; Expected = 'coverage-60%25-yellow' }
        @{ Percent = 12.5; Expected = 'coverage-12%25-red' }
    ) {
        $readme = "# Bylaw`n![coverage](https://img.shields.io/badge/coverage-92%25-brightgreen.svg)`n"
        Get-ReadmeWithCoverage -Readme $readme -Percent $Percent | Should -BeExactly "# Bylaw`n![coverage](https://img.shields.io/badge/$Expected.svg)`n"
    }

    It 'refuses a README without the badge' {
        { Get-ReadmeWithCoverage -Readme '# Bylaw' -Percent 90 } | Should -Throw '*no coverage badge*'
    }

    It 'finds the badge in the real README' {
        $real = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../README.md'))
        { Get-ReadmeWithCoverage -Readme $real -Percent 90 } | Should -Not -Throw
    }
}

Describe 'The repository changelog' {
    It 'has at most one Deploy heading, with a valid version if it pins one' {
        $changeLog = [string[]] (Get-Content -Path (Join-Path $PSScriptRoot '../../CHANGELOG.md'))
        $request = Get-DeployRequest -ChangeLog $changeLog
        if ($request -and $request.Version) {
            { ConvertTo-ReleaseVersion -Version $request.Version } | Should -Not -Throw
        }
    }
}
