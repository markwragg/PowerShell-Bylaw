# Golden-file tests (ADR-0009): building examples/ and tests/Golden/ must reproduce the expected
# JSON beside each source file byte for byte, and every golden file must be EPAC-valid.
#
# After an intentional output change, regenerate with ./build/build.ps1 -Task UpdateGolden and
# review the diff.

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
    $script:GoldenRoots = foreach ($relative in 'examples', 'tests/Golden') {
        $root = Join-Path $repoRoot $relative
        @{
            Name   = $relative
            Root   = $root
            Golden = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' | ForEach-Object {
                    @{ Relative = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'); File = $_.FullName }
                })
        }
    }
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../src/Bylaw.psd1') -Force
    $script:Schema = Join-Path $PSScriptRoot '../Schemas/epac-policy-definition-schema.json'
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Golden files in <Name>' -ForEach $GoldenRoots {
    BeforeAll {
        $script:Out = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $warnings = $null
        $script:Results = @(Build-Bylaw -Path $Root -OutputPath $Out -PassThru -WarningVariable warnings -WarningAction SilentlyContinue)
        $script:BuildWarnings = @($warnings)
        $script:Produced = @(Get-ChildItem -LiteralPath $Out -Recurse -File | ForEach-Object {
                [System.IO.Path]::GetRelativePath($Out, $_.FullName).Replace('\', '/')
            })
    }

    It 'compiles without warnings' {
        $BuildWarnings | Should -BeNullOrEmpty
    }

    It 'has a golden file for every policy, and a policy for every golden file' {
        $expected = @($Golden.Relative | Sort-Object -Culture ([cultureinfo]::InvariantCulture))
        @($Produced | Sort-Object -Culture ([cultureinfo]::InvariantCulture)) | Should -Be $expected
    }

    It 'reproduces <Relative> byte for byte' -ForEach $Golden {
        $actualPath = Join-Path $Out $Relative
        Test-Path -LiteralPath $actualPath | Should -BeTrue -Because 'the build should produce every golden file'
        $expectedBytes = [System.IO.File]::ReadAllBytes($File)
        $actualBytes = [System.IO.File]::ReadAllBytes($actualPath)
        if ([System.Linq.Enumerable]::SequenceEqual($expectedBytes, $actualBytes)) {
            return
        }
        # Show the first line that differs, then fail.
        $expectedLines = [System.Text.Encoding]::UTF8.GetString($expectedBytes) -split "`n"
        $actualLines = [System.Text.Encoding]::UTF8.GetString($actualBytes) -split "`n"
        $line = 0
        while ($line -lt $expectedLines.Count -and $line -lt $actualLines.Count -and $expectedLines[$line] -ceq $actualLines[$line]) {
            $line++
        }
        $want = if ($line -lt $expectedLines.Count) { $expectedLines[$line] } else { '<end of file>' }
        $got = if ($line -lt $actualLines.Count) { $actualLines[$line] } else { '<end of file>' }
        throw "Output differs from the golden file at line $($line + 1).`n  expected: $want`n  actual:   $got`nIf the change is intended, run ./build/build.ps1 -Task UpdateGolden and review the diff."
    }

    It 'has a golden <Relative> that is UTF-8 without BOM, with LF line endings' -ForEach $Golden {
        $bytes = [System.IO.File]::ReadAllBytes($File)
        ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        $bytes | Should -Not -Contain ([byte] 13)
    }

    It 'has a golden <Relative> that is valid against the EPAC schema' -ForEach $Golden {
        Test-Json -Json ([System.IO.File]::ReadAllText($File)) -SchemaFile $Schema -ErrorAction SilentlyContinue | Should -BeTrue
    }
}
