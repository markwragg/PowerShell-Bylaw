# Golden-file tests (ADR-0009): building each golden folder must reproduce the expected JSON beside
# each source file byte for byte. The folders and their formats are listed in GoldenRoots.psd1.
# EPAC golden files must be valid against the EPAC schema; plain JSON ones (ADR-0027) have no
# published schema, so their structure is checked instead.
#
# After an intentional output change, regenerate with ./build/build.ps1 -Task UpdateGolden and
# review the diff.

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
    $roots = (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'GoldenRoots.psd1')).Roots
    $script:GoldenRoots = foreach ($golden in $roots) {
        $root = Join-Path $repoRoot $golden.Path
        @{
            Name            = $golden.Path
            Root            = $root
            Format          = $golden.Format
            DefinitionScope = if ($golden.ContainsKey('DefinitionScope')) { $golden.DefinitionScope } else { $null }
            # Deployment templates (ADR-0031) are inputs, kept in templates folders, not golden files.
            Golden          = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' | Where-Object { $_.Directory.Name -ne 'templates' } | ForEach-Object {
                    @{ Relative = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'); File = $_.FullName; Format = $golden.Format }
                })
        }
    }
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../src/Bylaw.psd1') -Force
    $script:Schema = Join-Path $PSScriptRoot '../Schemas/epac-policy-definition-schema.json'
    $script:SetSchema = Join-Path $PSScriptRoot '../Schemas/epac-policy-set-definition-schema.json'
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Golden files in <Name> (<Format>)' -ForEach $GoldenRoots {
    BeforeAll {
        $script:Out = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $warnings = $null
        $build = @{ Path = $Root; OutputPath = $Out; Format = $Format; PassThru = $true }
        if ($DefinitionScope) {
            $build.DefinitionScope = $DefinitionScope
        }
        $script:Results = @(Build-Bylaw @build -WarningVariable warnings -WarningAction SilentlyContinue)
        $script:BuildWarnings = @($warnings)
        $script:Produced = @(Get-ChildItem -LiteralPath $Out -Recurse -File | ForEach-Object {
                [System.IO.Path]::GetRelativePath($Out, $_.FullName).Replace('\', '/')
            })
    }

    It 'compiles without warnings, except BYL4010 for Append in EPAC' {
        # BYL4010 is expected: Append details are an array, which the EPAC schema doesn't allow.
        @($BuildWarnings | Where-Object { "$_" -notmatch '\] BYL4010: ' }) | Should -BeNullOrEmpty
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

    It 'has a golden <Relative> that is valid against the EPAC schema' -ForEach @($Golden | Where-Object Format -EQ 'Epac') -AllowNullOrEmptyForEach {
        $text = [System.IO.File]::ReadAllText($File)
        # Append details are an array, as Azure requires; the EPAC schema says object (BYL4010). Check
        # everything else against the schema.
        $node = [System.Text.Json.Nodes.JsonNode]::Parse($text)
        # An initiative is checked against EPAC's policy set definition schema (ADR-0035).
        if ($null -ne $node['properties']['policyDefinitions']) {
            Test-Json -Json $text -SchemaFile $SetSchema -ErrorAction SilentlyContinue | Should -BeTrue
            return
        }
        $then = $node['properties']['policyRule']['then']
        if ($then['details'] -is [System.Text.Json.Nodes.JsonArray]) {
            $then['effect'].ToString() | Should -BeIn @('Append', "[parameters('effect')]")
            $then['details'] = [System.Text.Json.Nodes.JsonObject]::new()
            $text = $node.ToJsonString()
        }
        Test-Json -Json $text -SchemaFile $Schema -ErrorAction SilentlyContinue | Should -BeTrue
    }

    It 'has a golden <Relative> with the plain definition structure' -ForEach @($Golden | Where-Object Format -EQ 'PlainJson') -AllowNullOrEmptyForEach {
        $text = [System.IO.File]::ReadAllText($File)
        # Key order from System.Text.Json: -AsHashtable only keeps it from PowerShell 7.3.
        $parsed = [System.Text.Json.JsonDocument]::Parse($text)
        try {
            @($parsed.RootElement.EnumerateObject() | ForEach-Object Name) | Should -Be @('name', 'properties')
        }
        finally {
            $parsed.Dispose()
        }
        $properties = ($text | ConvertFrom-Json -AsHashtable)['properties']
        # An initiative (ADR-0035): members, each with a full ID, and no rule.
        if ($properties.Contains('policyDefinitions')) {
            foreach ($key in 'displayName', 'policyType', 'policyDefinitions') {
                $properties.Contains($key) | Should -BeTrue -Because "plain initiatives need properties.$key"
            }
            $allowed = 'displayName', 'policyType', 'description', 'metadata', 'parameters', 'policyDefinitions', 'policyDefinitionGroups'
            @($properties.Keys | Where-Object { $_ -notin $allowed }) | Should -BeNullOrEmpty
            foreach ($member in $properties['policyDefinitions']) {
                $member['policyDefinitionId'] | Should -Match '/providers/Microsoft\.Authorization/policyDefinitions/[^/]+$'
                $member.Contains('policyDefinitionReferenceId') | Should -BeTrue
            }
            return
        }
        foreach ($key in 'displayName', 'policyType', 'mode', 'policyRule') {
            $properties.Contains($key) | Should -BeTrue -Because "plain definitions need properties.$key"
        }
        $allowed = 'displayName', 'policyType', 'mode', 'description', 'metadata', 'parameters', 'policyRule'
        @($properties.Keys | Where-Object { $_ -notin $allowed }) | Should -BeNullOrEmpty
        @($properties['policyRule'].Keys | Sort-Object) | Should -Be @('if', 'then')
        $properties['policyRule']['then'].Contains('effect') | Should -BeTrue
    }
}
