BeforeAll {
    $script:manifestPath = Join-Path $PSScriptRoot '../../src/Bylaw.psd1'
}

Describe 'Bylaw module manifest' {
    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'requires PowerShell 7.2 or later on Core' {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifest.PowerShellVersion | Should -Be '7.2'
        $manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'does not use wildcard exports' {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        foreach ($key in 'FunctionsToExport', 'CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
            $manifest[$key] | Should -Not -Contain '*' -Because "$key must list commands explicitly (ADR-0005)"
        }
    }
}

Describe 'Bylaw module import' {
    BeforeAll {
        $script:module = Import-Module -Name $manifestPath -Force -PassThru
    }

    AfterAll {
        Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
    }

    It 'imports without errors' {
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'Bylaw'
    }

    It 'exports only the commands listed in the manifest' {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $exported = @($module.ExportedCommands.Keys | Sort-Object)
        $expected = @($manifest.FunctionsToExport | Sort-Object)
        $exported | Should -Be $expected
    }
}
