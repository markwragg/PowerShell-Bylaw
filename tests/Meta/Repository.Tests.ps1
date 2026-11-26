BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.nupkg')

    # Tracked and untracked-but-not-ignored files, so new files are checked before they are committed.
    $relativePaths = @(git -C $repoRoot ls-files --cached --others --exclude-standard)
    $script:textFiles = foreach ($relative in $relativePaths) {
        $fullPath = Join-Path $repoRoot $relative
        if ((Test-Path $fullPath -PathType Leaf) -and ([System.IO.Path]::GetExtension($relative) -notin $binaryExtensions)) {
            @{ Path = $relative; FullPath = $fullPath }
        }
    }
    $script:powerShellFiles = @($textFiles | Where-Object { $_.Path -match '\.ps(m|d)?1$' })
    $script:markdownFiles = @($textFiles | Where-Object { $_.Path -match '\.md$' })
    $script:sourceFiles = @($powerShellFiles | Where-Object { $_.Path -like 'src/*' })
}

Describe 'Bylaw classes in type names' {
    # PowerShell caches type names such as List[BylawDiagnostic] per process. When Bylaw's classes
    # are defined again (after PowerShell flushes its script cache, or on re-import), those
    # cached names keep pointing at the old classes, and Build-Bylaw fails with errors such as
    # 'Cannot find an overload for "Add"'. Use List[object] and [object[]] instead (ADR-0006).
    It '<Path> does not use a Bylaw class inside a generic or array type' -ForEach $sourceFiles {
        $text = [System.IO.File]::ReadAllText($FullPath)
        $found = @([regex]::Matches($text, '\[[\w.]+\[[^\]]*Bylaw\w+[^\]]*\]\]|Bylaw\w+\[\]') | ForEach-Object Value)
        $found | Should -BeNullOrEmpty
    }
}

Describe 'Repository text files' {
    It '<Path> uses LF line endings' -ForEach $textFiles {
        $bytes = [System.IO.File]::ReadAllBytes($FullPath)
        $bytes -contains 13 | Should -BeFalse -Because 'all text is stored with LF (ADR-0009)'
    }

    It '<Path> has no UTF-8 BOM' -ForEach $textFiles {
        $bytes = [System.IO.File]::ReadAllBytes($FullPath)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $hasBom | Should -BeFalse
    }
}

Describe 'README' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $readme = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
        $script:readmePowerShell = @([regex]::Matches($readme, '(?ms)^```powershell\n(.*?)^```') | ForEach-Object { $_.Groups[1].Value })
        $script:readmeJson = @([regex]::Matches($readme, '(?ms)^```json\n(.*?)^```') | ForEach-Object { $_.Groups[1].Value })
        $script:storageSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'examples/storage/public-network-access.bylaw.ps1'))
        $script:storageGolden = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'examples/storage/storage-deny-public-network-access.json'))
    }

    It 'shows the storage example exactly as it is in examples/' {
        $block = @($readmePowerShell | Where-Object { $_ -match "^Policy 'storage-deny-public-network-access'" })
        $block.Count | Should -Be 1
        $storageSource.Contains($block[0]) | Should -BeTrue -Because 'the before and after in README.md must match examples/storage/public-network-access.bylaw.ps1'
    }

    It 'shows the storage output exactly as the golden file' {
        $block = @($readmeJson | Where-Object { $_ -match '"name": "storage-deny-public-network-access"' })
        $block.Count | Should -Be 1
        $block[0] | Should -BeExactly $storageGolden -Because 'the before and after in README.md must match the golden file'
    }
}

Describe 'No backtick line continuation' {
    It '<Path> has no line continuations' -ForEach $powerShellFiles {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref] $tokens, [ref] $errors)
        $continuations = @($tokens | Where-Object Kind -EQ 'LineContinuation')
        $lines = ($continuations | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $continuations.Count | Should -Be 0 -Because "backtick line continuation is banned (found on line(s) $lines)"
    }

    It '<Path> has no line continuations in PowerShell code blocks' -ForEach $markdownFiles {
        $text = [System.IO.File]::ReadAllText($FullPath)
        $blocks = [regex]::Matches($text, '(?ms)^```(?:powershell|pwsh|ps1|ps)\s*\n(.*?)^```')
        $offenders = foreach ($block in $blocks) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value, [ref] $tokens, [ref] $errors)
            $tokens | Where-Object Kind -EQ 'LineContinuation'
        }
        @($offenders).Count | Should -Be 0 -Because 'backtick line continuation is banned in docs and examples too'
    }
}
