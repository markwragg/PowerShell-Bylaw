# The diagnostics catalogue in docs/diagnostics (ADR-0037): one data file per range, listing exactly
# the codes src emits, each with what it means and how to fix it.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '../../build/Docs.ps1')
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $emitted = @(Get-SourceDiagnostic -SourceRoot (Join-Path $root 'src'))
    $catalogue = @(Get-DiagnosticCatalogue -Path (Join-Path $root 'docs/diagnostics'))
    $script:Ranges = foreach ($prefix in @($emitted.Code | ForEach-Object { $_.Substring(0, 4) } | Sort-Object -Unique)) {
        $range = "${prefix}xxx"
        @{
            Range     = $range
            Catalogue = $catalogue | Where-Object { $_.Range -eq $range } | Select-Object -First 1
            Emitted   = @($emitted | Where-Object { $_.Code.StartsWith($prefix) })
        }
    }
    $script:Entries = foreach ($range in $catalogue) {
        foreach ($entry in $range.Diagnostics) {
            @{ Code = $entry.Code; Entry = $entry; Range = $range.Range }
        }
    }
}

BeforeAll {
    Set-StrictMode -Version Latest
    $script:AdrPath = Join-Path $PSScriptRoot '../../docs/adr'
}

Describe 'Diagnostics catalogue for <Range>' -ForEach $Ranges {
    It 'has a catalogue file' {
        $Catalogue | Should -Not -BeNullOrEmpty -Because "docs/diagnostics/$Range.psd1 should document the $Range codes"
        $Catalogue.File | Should -Be "$Range.psd1"
        $Catalogue.Title | Should -Not -BeNullOrEmpty
        $Catalogue.Description | Should -Not -BeNullOrEmpty
    }

    It 'has an entry for every code src emits, and none it does not' {
        $documented = @($Catalogue.Diagnostics.Code)
        $codes = @($Emitted.Code | Sort-Object -Unique)
        @($codes | Where-Object { $_ -notin $documented }) | Should -BeNullOrEmpty -Because 'every code needs an entry'
        @($documented | Where-Object { $_ -notin $codes }) | Should -BeNullOrEmpty -Because 'an entry for a code src no longer emits is stale'
    }

    It 'lists each code once, in order' {
        $documented = @($Catalogue.Diagnostics.Code)
        $documented | Should -Be @($documented | Sort-Object -Unique)
    }

    It 'gives each code the severity src reports it with' {
        foreach ($entry in $Catalogue.Diagnostics) {
            $known = @($Emitted | Where-Object { $_.Code -eq $entry.Code -and $_.Severity } | ForEach-Object Severity | Sort-Object -Unique)
            foreach ($severity in $known) {
                $severity | Should -Be $entry.Severity -Because "$($entry.Code) is reported as $severity"
            }
        }
    }
}

Describe 'Catalogue entry <Code>' -ForEach $Entries {
    It 'has a severity, a title, an explanation and a fix' {
        $Entry.Severity | Should -BeIn @('Error', 'Warning')
        foreach ($key in 'Title', 'Explanation', 'Fix') {
            $Entry.ContainsKey($key) | Should -BeTrue -Because "$Code needs $key"
            "$($Entry[$key])".Trim() | Should -Not -BeNullOrEmpty -Because "$Code needs $key"
        }
        $Code | Should -Match "^$($Range.Substring(0, 4))\d{3}$"
        @($Entry.Keys | Where-Object { $_ -notin 'Code', 'Severity', 'Title', 'Explanation', 'Fix', 'Example', 'Adr' }) | Should -BeNullOrEmpty
    }

    It 'links an ADR that exists' {
        if (-not $Entry.ContainsKey('Adr')) {
            return
        }
        $Entry.Adr | Should -Match '^\d{4}$'
        @(Get-ChildItem -Path $AdrPath -Filter "$($Entry.Adr)-*.md").Count | Should -Be 1
    }
}
