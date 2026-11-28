# The wiki pages from build/Docs.ps1 (ADR-0037): every command and keyword gets a complete page, and
# syncing to a wiki clone never touches a page the build didn't generate.

BeforeDiscovery {
    $manifest = Join-Path $PSScriptRoot '../../src/Bylaw.psd1'
    $module = Import-Module -Name $manifest -Force -PassThru
    $script:Commands = @($module.ExportedFunctions.Keys | Sort-Object | ForEach-Object { @{ Name = $_ } })
    $script:Keywords = @(& $module { $script:BylawKeywordNames } | Sort-Object | ForEach-Object { @{ Name = $_ } })
    Remove-Module -Name Bylaw -Force
}

BeforeAll {
    Set-StrictMode -Version Latest
    $requirements = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../../build/requirements.psd1')
    Import-Module -Name platyPS -RequiredVersion $requirements['platyPS'] -Force
    . (Join-Path $PSScriptRoot '../../build/Docs.ps1')
    $script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../src')).Path
    $script:Out = Join-Path $TestDrive 'wiki'
    $script:Pages = @(New-WikiPageSet -SourceRoot $SourceRoot -OutputPath $Out)

    function Get-Page([string] $Name) {
        [System.IO.File]::ReadAllText((Join-Path $Out "$Name.md"))
    }

    function Get-Section([string] $Text, [string] $Heading) {
        # The text under a level-2 heading, up to the next one.
        $match = [regex]::Match($Text, "(?ms)^## $([regex]::Escape($Heading))\s*\n(?<body>.*?)(?=^## |\z)")
        if ($match.Success) { $match.Groups['body'].Value.Trim() } else { $null }
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Command pages' {
    It '<Name> has a synopsis, a syntax, an example and no placeholders' -ForEach $Commands {
        $page = Get-Page $Name
        Get-Section $page 'SYNOPSIS' | Should -Not -BeNullOrEmpty
        Get-Section $page 'SYNTAX' | Should -Match "$([regex]::Escape($Name)) "
        Get-Section $page 'EXAMPLES' | Should -Match '### EXAMPLE 1'
        $page | Should -Not -Match '\{\{'
        $page | Should -Not -Match 'ProgressAction' -Because 'PlatyPS 0.12 lists the common parameter as the command''s own'
        $page | Should -Not -Match "`r"
    }
}

Describe 'Keyword pages' {
    It '<Name> has a synopsis, where it is used, an example and every parameter described' -ForEach $Keywords {
        $page = Get-Page $Name
        $page | Should -Match "^# $([regex]::Escape($Name))\n"
        Get-Section $page 'SYNOPSIS' | Should -Not -BeNullOrEmpty
        Get-Section $page 'SYNTAX' | Should -Match "$([regex]::Escape($Name))"
        Get-Section $page 'USED IN' | Should -Not -BeNullOrEmpty
        Get-Section $page 'EXAMPLES' | Should -Match '(?s)### Example 1\n```powershell\n\S'
        foreach ($parameter in [regex]::Matches($page, '(?m)^### -(?<name>\S+)\n(?<description>[^\n]*)')) {
            $parameter.Groups['description'].Value.Trim() | Should -Not -BeNullOrEmpty -Because "-$($parameter.Groups['name'].Value) needs a description in $Name's help"
        }
        $page | Should -Not -Match "`r"
    }

    It 'lists only keywords in the usage fallback, and none the source already gives' {
        $fromSource = Get-KeywordUsage -SourceRoot $SourceRoot -SourceOnly
        foreach ($name in $KeywordUsageFallback.Keys) {
            $name | Should -BeIn $Keywords.Name
            $fromSource.ContainsKey($name) | Should -BeFalse -Because "Test-BylawParent already says where '$name' is used"
        }
    }
}

Describe 'Diagnostics pages' {
    It 'has an index that links every range page' {
        $ranges = @($Pages | Where-Object { $_ -like 'Diagnostics-BYL*' })
        $ranges | Should -Not -BeNullOrEmpty
        $index = Get-Page 'Diagnostics'
        foreach ($range in $ranges) {
            $index | Should -Match "\]\($([regex]::Escape($range))\) \|"
        }
    }

    It 'has a section for every code in <_>, linked from its table' -ForEach @('BYL1xxx', 'BYL2xxx', 'BYL3xxx', 'BYL4xxx', 'BYL5xxx') {
        $page = Get-Page "Diagnostics-$_"
        $codes = [regex]::Matches($page, '(?m)^## (BYL\d{4})$') | ForEach-Object { $_.Groups[1].Value }
        $codes | Should -Not -BeNullOrEmpty
        foreach ($code in $codes) {
            $page | Should -Match "\| \[$code\]\(#$($code.ToLowerInvariant())\) \|"
        }
    }
}

Describe 'The sidebar' {
    It 'links Home and every generated page' {
        $sidebar = Get-Page '_Sidebar'
        $sidebar | Should -Match '\[\[Home\]\]'
        foreach ($page in $Pages | Where-Object { $_ -ne '_Sidebar' }) {
            $sidebar | Should -Match "\[\[([^\]|]*\|)?$([regex]::Escape($page))\]\]"
        }
    }

    It 'returns a page name for every file written' {
        @(Get-ChildItem -Path $Out -Filter '*.md' | ForEach-Object BaseName | Sort-Object) | Should -Be @($Pages | Sort-Object)
    }
}

Describe 'Sync-WikiPageSet' {
    BeforeEach {
        $script:Generated = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Wiki = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $Generated, $Wiki
        Set-Content -Path (Join-Path $Generated 'Field.md') -Value 'field'
        Set-Content -Path (Join-Path $Generated '_Sidebar.md') -Value 'sidebar'
        Set-Content -Path (Join-Path $Wiki 'Home.md') -Value 'written by hand'
    }

    It 'writes the pages and the list of generated pages, leaving other pages alone' {
        Sync-WikiPageSet -GeneratedPath $Generated -WikiPath $Wiki | Should -Be @('_Sidebar', 'Field')
        Get-Content (Join-Path $Wiki 'Field.md') | Should -Be 'field'
        Get-Content (Join-Path $Wiki 'Home.md') | Should -Be 'written by hand'
        @(Get-Content (Join-Path $Wiki '.bylaw-generated-pages')) | Should -Be @('_Sidebar', 'Field')
    }

    It 'replaces its own pages and removes the ones it no longer generates' {
        Set-Content -Path (Join-Path $Wiki 'Field.md') -Value 'old'
        Set-Content -Path (Join-Path $Wiki 'Gone.md') -Value 'old'
        Set-Content -Path (Join-Path $Wiki '.bylaw-generated-pages') -Value 'Field', 'Gone', '_Sidebar'
        $null = Sync-WikiPageSet -GeneratedPath $Generated -WikiPath $Wiki
        Get-Content (Join-Path $Wiki 'Field.md') | Should -Be 'field'
        Test-Path (Join-Path $Wiki 'Gone.md') | Should -BeFalse
        Test-Path (Join-Path $Wiki 'Home.md') | Should -BeTrue
    }

    It 'refuses to replace a page it did not generate' {
        Set-Content -Path (Join-Path $Wiki 'Field.md') -Value 'written by hand'
        { Sync-WikiPageSet -GeneratedPath $Generated -WikiPath $Wiki } | Should -Throw "*didn't generate: Field*"
        Get-Content (Join-Path $Wiki 'Field.md') | Should -Be 'written by hand'
    }
}
