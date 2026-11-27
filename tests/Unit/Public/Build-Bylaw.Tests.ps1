BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    function script:Get-TestPolicyText {
        # A valid, EPAC-ready policy. Body replaces the Require block.
        param(
            [string] $Name = 'test-policy',
            [string] $Body = "Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }",
            [string] $Before = ''
        )
        @"
$Before
Policy '$Name' {
    Properties @{ DisplayName = 'Test policy'; Category = 'Storage'; Version = '1.0.0' }
    Resource 'Microsoft.Storage/storageAccounts' {
        $Body
    }
    Effect Deny
}
"@
    }

    function script:New-TestProject {
        # A project folder in TestDrive with a .git folder (so no settings file above it is found)
        # and the given files: @{ 'relative/path' = 'content' }.
        param([hashtable] $Files)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $root '.git')
        foreach ($relative in $Files.Keys) {
            $path = Join-Path $root $relative
            $null = New-Item -ItemType Directory -Force -Path (Split-Path $path)
            [System.IO.File]::WriteAllText($path, $Files[$relative])
        }
        $root
    }

    function script:Get-BuildError([scriptblock] $Build) {
        # The error record of a failed build.
        try {
            & $Build
        }
        catch {
            return $_
        }
        throw 'The build did not fail.'
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Build-Bylaw output' {
    BeforeAll {
        $script:Project = New-TestProject @{
            'src/storage/public.bylaw.ps1' = Get-TestPolicyText -Name 'storage-public'
            'src/top.bylaw.ps1'            = Get-TestPolicyText -Name 'top-policy'
            'src/storage/helper.ps1'       = 'throw "helper scripts are not compiled"'
        }
        $script:Out = Join-Path $Project 'out'
        $script:Results = @(Build-Bylaw -Path (Join-Path $Project 'src') -OutputPath $Out -PassThru)
    }

    It 'writes one file per policy, mirroring the source folders' {
        Test-Path -LiteralPath (Join-Path $Out 'storage/storage-public.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Out 'top-policy.json') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $Out -Recurse -File).Count | Should -Be 2
    }

    It 'keeps the case and spaces of a name in the definition and the file name (ADR-0010)' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'Deny-Storage minTLS' }
        $out = Join-Path $project 'out'
        $result = Build-Bylaw -Path $project -OutputPath $out -PassThru
        $result.Json | Should -BeLike '*"name": "Deny-Storage minTLS"*'
        [System.IO.Path]::GetFileName($result.OutputFile) | Should -BeExactly 'Deny-Storage minTLS.json'
        Test-Path -LiteralPath $result.OutputFile | Should -BeTrue
    }

    It 'does not report a deployment template inside -OutputPath as stale output (ADR-0031)' {
        $policy = @'
Policy 'deploy-policy' {
    Properties @{ DisplayName = 'x'; Category = 'Compute'; Version = '1.0.0'; Mode = 'Indexed' }
    Resource 'Microsoft.Compute/virtualMachines' { }
    DeployIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' -Role 'Contributor' {
        Deployment -TemplateFile ./templates/t.json
    }
}
'@
        $project = New-TestProject @{
            'a.bylaw.ps1'      = $policy
            'templates/t.json' = '{ "resources": [] }'
            'stale.json'       = '{}'
        }
        $null = Build-Bylaw -Path $project -OutputPath $project -WarningVariable warnings -WarningAction SilentlyContinue
        $text = $warnings -join "`n"
        $text | Should -BeLike '*stale.json BYL5030*'
        $text | Should -Not -BeLike '*t.json BYL5030*'
        Test-Path -LiteralPath (Join-Path $project 'deploy-policy.json') | Should -BeTrue
    }

    It 'ignores .ps1 files that are not *.bylaw.ps1' {
        $Results.Name | Should -Not -Contain 'helper'
    }

    It 'returns results in ordinal order of the relative path' {
        $Results.Name | Should -Be @('storage-public', 'top-policy')
    }

    It 'returns Name, SourceFile, SourceLine, OutputFile, Json and Warnings' {
        $result = $Results[0]
        $result.PSObject.TypeNames | Should -Contain 'Bylaw.BuildResult'
        $result.SourceFile | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Project 'src/storage/public.bylaw.ps1')))
        $result.SourceLine | Should -Be 2
        $result.OutputFile | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Out 'storage/storage-public.json')))
        $result.Json | Should -BeLike '*"name": "storage-public"*'
        , $result.Warnings | Should -BeOfType [string[]]
    }

    It 'writes the JSON as UTF-8 without BOM, exactly as returned' {
        $bytes = [System.IO.File]::ReadAllBytes($Results[0].OutputFile)
        $bytes[0] | Should -Not -Be 0xEF
        [System.Text.Encoding]::UTF8.GetString($bytes) | Should -BeExactly $Results[0].Json
    }

    It 'leaves an unchanged file alone' {
        $file = $Results[0].OutputFile
        $stamp = [datetime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        [System.IO.File]::SetLastWriteTimeUtc($file, $stamp)
        $null = Build-Bylaw -Path (Join-Path $Project 'src') -OutputPath $Out
        [System.IO.File]::GetLastWriteTimeUtc($file) | Should -Be $stamp
    }

    It 'warns about output files it did not produce, and keeps them' {
        $stale = Join-Path $Out 'storage/old-policy.json'
        Set-Content -LiteralPath $stale -Value '{}'
        $null = Build-Bylaw -Path (Join-Path $Project 'src') -OutputPath $Out -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join "`n") | Should -BeLike '*old-policy.json BYL5030*'
        Test-Path -LiteralPath $stale | Should -BeTrue
        Remove-Item -LiteralPath $stale
    }

    It 'writes nothing with -WhatIf' {
        $out = Join-Path $Project 'whatif'
        Build-Bylaw -Path (Join-Path $Project 'src') -OutputPath $out -WhatIf
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'compiles in memory with -PassThru and no -OutputPath' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'in-memory' }
        $result = Build-Bylaw -Path $project -PassThru
        $result.OutputFile | Should -BeNullOrEmpty
        $result.Json | Should -Not -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $project -Recurse -File -Filter '*.json').Count | Should -Be 0
    }

    It 'requires -OutputPath or -PassThru' {
        { Build-Bylaw -Path $Project } | Should -Throw '*Specify -OutputPath, or -PassThru*'
    }
}

Describe 'Build-Bylaw parallel compilation' {
    BeforeAll {
        # Later files finish first: the earlier a file sorts, the longer it sleeps.
        $files = @{}
        foreach ($index in 1..8) {
            $sleep = (9 - $index) * 40
            $files["p$index.bylaw.ps1"] = Get-TestPolicyText -Name "policy-$index" -Before "Start-Sleep -Milliseconds $sleep"
        }
        $files['p5.bylaw.ps1'] = Get-TestPolicyText -Name 'policy-5' -Body "Require 'r' { Field nope | Must -Be 'x' }"
        $script:ParallelProject = New-TestProject $files
        $files.Remove('p5.bylaw.ps1')
        $script:ParallelGood = New-TestProject $files
    }

    It 'produces the same results in the same order at any -ThrottleLimit' {
        $one = @(Build-Bylaw -Path $ParallelGood -PassThru -ThrottleLimit 1)
        $many = @(Build-Bylaw -Path $ParallelGood -PassThru -ThrottleLimit 8)
        $many.Name | Should -Be $one.Name
        $many.Json | Should -Be $one.Json
        $one.Name | Should -Be @(1, 2, 3, 4, 6, 7, 8 | ForEach-Object { "policy-$_" })
    }

    It 'reports errors in file order at any -ThrottleLimit' {
        $one = Get-BuildError { Build-Bylaw -Path $ParallelProject -PassThru -ThrottleLimit 1 }
        $many = Get-BuildError { Build-Bylaw -Path $ParallelProject -PassThru -ThrottleLimit 8 }
        $many.ErrorDetails.Message | Should -Be $one.ErrorDetails.Message
        $many.ErrorDetails.Message | Should -BeLike '*p5.bylaw.ps1*'
    }

    It 'rejects a -ThrottleLimit of <Value>' -ForEach @(@{ Value = 0 }, @{ Value = 65 }) {
        { Build-Bylaw -Path $ParallelGood -PassThru -ThrottleLimit $Value } | Should -Throw
    }
}

Describe 'Build-Bylaw discovery' {
    It 'accepts files and folders, several of each, and pipeline input' {
        $project = New-TestProject @{
            'one/a.bylaw.ps1'  = Get-TestPolicyText -Name 'policy-a'
            'two/b.bylaw.ps1'  = Get-TestPolicyText -Name 'policy-b'
            'three.bylaw.ps1'  = Get-TestPolicyText -Name 'policy-c'
        }
        $names = (Build-Bylaw -Path (Join-Path $project 'three.bylaw.ps1'), (Join-Path $project 'two') -PassThru).Name
        $names | Should -Be @('policy-c', 'policy-b')
        (Get-ChildItem -LiteralPath (Join-Path $project 'one') -Filter '*.bylaw.ps1' | Build-Bylaw -PassThru).Name | Should -Be @('policy-a')
    }

    It 'compiles a file only once when paths overlap' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'policy-a' }
        @(Build-Bylaw -Path $project, (Join-Path $project 'a.bylaw.ps1') -PassThru).Count | Should -Be 1
    }

    It 'compiles several policies from one file' {
        $text = (Get-TestPolicyText -Name 'first-policy') + (Get-TestPolicyText -Name 'second-policy')
        $project = New-TestProject @{ 'two.bylaw.ps1' = $text }
        $results = @(Build-Bylaw -Path $project -OutputPath (Join-Path $project 'out') -PassThru)
        $results.Name | Should -Be @('first-policy', 'second-policy')
        $results[1].SourceLine | Should -BeGreaterThan $results[0].SourceLine
    }

    It 'warns about a file with no Policy blocks' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'policy-a'; 'empty.bylaw.ps1' = '$x = 1' }
        $null = Build-Bylaw -Path $project -PassThru -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join "`n") | Should -BeLike '*empty.bylaw.ps1 BYL5021*'
    }

    It 'warns when no files are found' {
        $project = New-TestProject @{ 'readme.md' = 'x' }
        $result = Build-Bylaw -Path $project -PassThru -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        ($warnings -join "`n") | Should -BeLike '*No `*.bylaw.ps1 files found*'
    }

    It 'fails for a path that does not exist' {
        $record = Get-BuildError { Build-Bylaw -Path (Join-Path $TestDrive 'nowhere') -PassThru }
        $record.Exception.Diagnostics.Code | Should -Be @('BYL5040')
    }
}

Describe 'Build-Bylaw errors' {
    It 'reports errors from every file together and writes no output' {
        $project = New-TestProject @{
            'a-good.bylaw.ps1' = Get-TestPolicyText -Name 'good-policy'
            'b-bad.bylaw.ps1'  = Get-TestPolicyText -Name 'bad-policy' -Body "Require 'r' { Field publicNetworkAcess | Must -Be 'Disabled' }"
            'c-bad.bylaw.ps1'  = Get-TestPolicyText -Name 'Bad:Name'
        }
        $out = Join-Path $project 'out'
        $record = Get-BuildError { Build-Bylaw -Path $project -OutputPath $out }
        $record.FullyQualifiedErrorId | Should -BeLike 'BylawBuildFailed*'
        $record.Exception.Diagnostics.Code | Should -Be @('BYL2001', 'BYL3001')
        $record.ErrorDetails.Message | Should -BeLike 'Build failed with 2 errors:*'
        $record.ErrorDetails.Message | Should -BeLike '*b-bad.bylaw.ps1:5 `[Field`] BYL2001:*'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'reports duplicate names across files, ignoring case, with both locations' {
        $project = New-TestProject @{
            'a.bylaw.ps1' = Get-TestPolicyText -Name 'same-name'
            'b.bylaw.ps1' = Get-TestPolicyText -Name 'Same-Name'
        }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $diagnostic = $record.Exception.Diagnostics | Where-Object Code -EQ 'BYL5020'
        $diagnostic.Location.File | Should -BeLike '*b.bylaw.ps1'
        $diagnostic.Message | Should -BeLike '*a.bylaw.ps1:2*'
    }

    It 'reports names that differ only in case within one file' {
        $project = New-TestProject @{
            'a.bylaw.ps1' = (Get-TestPolicyText -Name 'Deny-Storage-minTLS') + (Get-TestPolicyText -Name 'deny-storage-mintls')
        }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        @($record.Exception.Diagnostics.Code) | Should -Be @('BYL5020')
    }

    It 'reports an error thrown outside Policy with its line' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = "`$x = 1`nthrow 'broken file'`n" }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $diagnostic = $record.Exception.Diagnostics | Select-Object -First 1
        $diagnostic.Code | Should -Be 'BYL5010'
        $diagnostic.Location.Line | Should -Be 2
        $diagnostic.Message | Should -BeLike '*broken file*'
    }

    It 'explains <Written> at the start of a block before the parse errors' -ForEach @(
        @{ Written = 'Param(Enabled)' }
        @{ Written = "Param ('Enabled')" }
        @{ Written = 'Param ("Enabled")' }
    ) {
        $text = "Policy 'p' {`n    Resource * {`n        When {`n            $Written | Must -Be `$true`n        }`n    }`n    Effect Audit`n}`n"
        $project = New-TestProject @{ 'a.bylaw.ps1' = $text }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $codes = @($record.Exception.Diagnostics | ForEach-Object Code)
        $codes | Should -Be @('BYL5013', 'BYL5010')
        $hint = $record.Exception.Diagnostics[0]
        $hint.Location.Line | Should -Be 4
        $hint.Message | Should -BeLike '*write Param Enabled without brackets, or (Param Enabled).'
    }

    It 'gives no Param hint for a parse error elsewhere, even with param blocks in helper functions' {
        $text = "function Get-Value { param([string] `$Name, `$Default) `$Default }`nfunction Get-Other {`n    param(`$x)`n    `$x`n}`n`$broken = (1 +`n"
        $project = New-TestProject @{ 'a.bylaw.ps1' = $text }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        @($record.Exception.Diagnostics | ForEach-Object Code) | Should -Be @('BYL5010')
    }

    It 'reports an error written outside Policy' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = (Get-TestPolicyText -Name 'policy-a' -Before "Write-Error 'something is wrong'") }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $record.Exception.Diagnostics.Code | Should -Be @('BYL5011')
        $record.Exception.Diagnostics[0].Message | Should -BeLike '*something is wrong*'
    }

    It 'reports a DSL error with the line in the source file' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'policy-a' -Body "Require 'r' {`n            Field publicNetworkAccess | Must -BeWrong 'x'`n        }" }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $location = $record.Exception.Diagnostics[0].Location
        $location.File | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $project 'a.bylaw.ps1')))
        $location.Line | Should -Be 6
    }
}

Describe 'Build-Bylaw isolation' {
    It 'runs each file in its own runspace, in its own folder' {
        $leaky = Get-TestPolicyText -Name 'policy-a' -Before "`$global:BylawLeak = 'a'; function global:Get-BylawLeak { }; `$shared = 'a'"
        $check = Get-TestPolicyText -Name 'policy-b' -Before @'
if ($global:BylawLeak -or $shared -or (Get-Command Get-BylawLeak -ErrorAction SilentlyContinue)) { throw 'state leaked from another file' }
if ((Get-Location).ProviderPath -ne $PSScriptRoot) { throw "working folder is $((Get-Location).ProviderPath)" }
'@
        $project = New-TestProject @{ 'a.bylaw.ps1' = $leaky; 'sub/b.bylaw.ps1' = $check }
        # One at a time, so file a has run before file b checks for its state.
        (Build-Bylaw -Path $project -PassThru -ThrottleLimit 1).Name | Should -Be @('policy-a', 'policy-b')
    }

    It 'runs each file in its own runspace when compiling several at once' {
        $files = @{}
        foreach ($index in 1..6) {
            $before = "if (`$global:BylawParallelLeak) { throw 'state leaked' }; `$global:BylawParallelLeak = $index; Start-Sleep -Milliseconds 50"
            $files["f$index.bylaw.ps1"] = Get-TestPolicyText -Name "policy-$index" -Before $before
        }
        $project = New-TestProject $files
        (Build-Bylaw -Path $project -PassThru -ThrottleLimit 3).Name | Should -Be @(1..6 | ForEach-Object { "policy-$_" })
    }

    It 'keeps working after PowerShell flushes its script cache' {
        # PowerShell clears its process-wide script cache when it grows past about 1000 entries,
        # so the next import parses Bylaw's classes again (see tests/Meta/Repository.Tests.ps1).
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'policy-a' }
        $null = Build-Bylaw -Path $project -PassThru
        foreach ($index in 1..1500) {
            $null = [scriptblock]::Create("'flush $index'")
        }
        (Build-Bylaw -Path $project -PassThru).Name | Should -Be 'policy-a'
        (Build-Bylaw -Path $project -PassThru).Name | Should -Be 'policy-a'
    }

    It 'leaves the caller session untouched' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Name 'policy-a' -Before "`$global:BylawCallerLeak = 'a'" }
        $before = (Get-Location).ProviderPath
        $null = Build-Bylaw -Path $project -PassThru
        Get-Variable -Name BylawCallerLeak -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-Location).ProviderPath | Should -Be $before
        Get-Item -LiteralPath 'function:Require' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Build-Bylaw settings and aliases' {
    It 'fails on invalid settings before compiling' {
        $project = New-TestProject @{ 'bylaw.json' = '{ "languageVersion": "9.9" }'; 'a.bylaw.ps1' = Get-TestPolicyText }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $record.Exception.Diagnostics.Code | Should -Be @('BYL5004')
    }

    It 'uses -Settings over a discovered bylaw.json' {
        $project = New-TestProject @{ 'bylaw.json' = '{ "bad": 1 }'; 'good.json' = '{ "languageVersion": "1.0" }'; 'a.bylaw.ps1' = Get-TestPolicyText }
        (Build-Bylaw -Path $project -Settings (Join-Path $project 'good.json') -PassThru).Name | Should -Be 'test-policy'
    }

    It 'uses the aliasCache from bylaw.json' {
        $snapshot = '{ "schemaVersion": 1, "generatedAt": "2026-01-01T00:00:00Z", "types": { "Microsoft.Storage/storageAccounts": { "aliases": { "Microsoft.Storage/storageAccounts/allowSharedKeyAccess": {} } } } }'
        $project = New-TestProject @{ 'bylaw.json' = '{ "aliasCache": "aliases.json" }'; 'aliases.json' = $snapshot; 'a.bylaw.ps1' = Get-TestPolicyText }
        # publicNetworkAccess is in the bundled snapshot but not in this one.
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $record.Exception.Diagnostics.Code | Should -Be @('BYL2001')
    }

    It 'fails when -AliasCachePath does not exist' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText }
        { Build-Bylaw -Path $project -PassThru -AliasCachePath (Join-Path $project 'missing.json') } | Should -Throw '*BYL2010*'
    }

    It 'reads the role map from <Source>' -ForEach @(
        @{ Source = '-RoleCachePath'; UseSettings = $false }
        @{ Source = 'bylaw.json roleCache'; UseSettings = $true }
    ) {
        $files = @{ 'a.bylaw.ps1' = Get-TestPolicyText; 'roles.json' = '{ "schemaVersion": 1, "roles": { "Reader": "acdd72a7-3385-48ef-bd42-f606fba81ae7" } }' }
        if ($UseSettings) {
            $files['bylaw.json'] = '{ "roleCache": "roles.json" }'
        }
        $project = New-TestProject $files
        $buildArguments = @{ Path = $project; PassThru = $true; Verbose = $true }
        if (-not $UseSettings) {
            $buildArguments['RoleCachePath'] = Join-Path $project 'roles.json'
        }
        $verbose = Build-Bylaw @buildArguments 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $verbose.Message | Should -Contain "Role map: $([System.IO.Path]::GetFullPath((Join-Path $project 'roles.json')))"
    }

    It 'fails before compiling when the role map from <Source> is missing or invalid' -ForEach @(
        @{ Source = '-RoleCachePath'; Files = @{}; PathArguments = @{ RoleCachePath = 'missing.json' }; Message = '*BYL2020*-RoleCachePath*' }
        @{ Source = 'bylaw.json'; Files = @{ 'bylaw.json' = '{ "roleCache": "missing.json" }' }; PathArguments = @{}; Message = "*BYL2020*bylaw.json 'roleCache'*" }
        @{ Source = 'an invalid file'; Files = @{ 'roles.json' = '{ "schemaVersion": 1 }' }; PathArguments = @{ RoleCachePath = 'roles.json' }; Message = '*BYL2020*not a Bylaw role map*' }
    ) {
        $project = New-TestProject (@{ 'a.bylaw.ps1' = Get-TestPolicyText } + $Files)
        $buildArguments = @{ Path = $project; PassThru = $true }
        foreach ($key in $PathArguments.Keys) {
            $buildArguments[$key] = Join-Path $project $PathArguments[$key]
        }
        { Build-Bylaw @buildArguments } | Should -Throw $Message
    }

    It 'turns unknown aliases into warnings with -AllowUnknownAlias' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText -Body "Require 'r' { Field notAnAlias | Must -Be 'x' }" }
        $result = Build-Bylaw -Path $project -PassThru -AllowUnknownAlias -WarningAction SilentlyContinue
        $result.Json | Should -Not -BeNullOrEmpty
        ($result.Warnings -join "`n") | Should -BeLike '*BYL2006*'
    }
}

Describe 'Build-Bylaw initiatives (ADR-0035)' {
    BeforeAll {
        $script:InitiativeText = @'
Initiative 'storage-baseline' {
    Properties @{ DisplayName = 'Storage baseline'; Category = 'Storage'; Version = '1.0.0' }
    PolicyDefinition 'test-policy'
}
'@
        $script:Scope = '/providers/Microsoft.Management/managementGroups/contoso'
    }

    It 'writes initiatives beside policies by default, mirroring the source folders' {
        $project = New-TestProject @{ 'src/storage/a.bylaw.ps1' = (Get-TestPolicyText) + "`n" + $InitiativeText }
        $out = Join-Path $project 'out'
        $results = @(Build-Bylaw -Path (Join-Path $project 'src') -OutputPath $out -PassThru)
        $results.Kind | Should -Be @('Policy', 'Initiative')
        $results.Name | Should -Be @('test-policy', 'storage-baseline')
        Test-Path -LiteralPath (Join-Path $out 'storage/storage-baseline.json') | Should -BeTrue
        $results[1].OutputFile | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $out 'storage/storage-baseline.json')))
        $results[1].Json | Should -BeLike '*"policyDefinitionName": "test-policy"*'
    }

    It 'writes initiatives to <Source>' -ForEach @(
        @{ Source = '-InitiativeOutputPath' }
        @{ Source = 'initiativeOutputPath in bylaw.json' }
    ) {
        $files = @{ 'a.bylaw.ps1' = (Get-TestPolicyText) + "`n" + $InitiativeText }
        if ($Source -like '*bylaw.json') {
            $files['bylaw.json'] = '{ "initiativeOutputPath": "Definitions/policySetDefinitions" }'
        }
        $project = New-TestProject $files
        $arguments = @{ Path = $project; OutputPath = (Join-Path $project 'Definitions/policyDefinitions') }
        if ($Source -eq '-InitiativeOutputPath') {
            $arguments.InitiativeOutputPath = Join-Path $project 'Definitions/policySetDefinitions'
        }
        $null = Build-Bylaw @arguments
        Test-Path -LiteralPath (Join-Path $project 'Definitions/policyDefinitions/test-policy.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $project 'Definitions/policySetDefinitions/storage-baseline.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $project 'Definitions/policyDefinitions/storage-baseline.json') | Should -BeFalse
    }

    It 'warns about stale files in both output folders' {
        $project = New-TestProject @{
            'a.bylaw.ps1'                          = (Get-TestPolicyText) + "`n" + $InitiativeText
            'policies/old-policy.json'             = '{}'
            'initiatives/nested/old-initiative.json' = '{}'
        }
        $null = Build-Bylaw -Path $project -OutputPath (Join-Path $project 'policies') -InitiativeOutputPath (Join-Path $project 'initiatives') -WarningVariable warnings -WarningAction SilentlyContinue
        $text = $warnings -join "`n"
        $text | Should -BeLike '*old-policy.json BYL5030*'
        $text | Should -BeLike '*old-initiative.json BYL5030*'
        @($warnings | Where-Object { "$_" -like '*storage-baseline.json*' }).Count | Should -Be 0
    }

    It 'reports a policy and an initiative with the same name, ignoring case (BYL5020)' {
        $project = New-TestProject @{
            'a.bylaw.ps1' = Get-TestPolicyText -Name 'storage-baseline'
            'b.bylaw.ps1' = $InitiativeText.Replace("PolicyDefinition 'test-policy'", "PolicyDefinition 'storage-baseline'").Replace("'storage-baseline' {", "'Storage-Baseline' {")
        }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru }
        $diagnostic = $record.Exception.Diagnostics | Where-Object Code -EQ 'BYL5020'
        $diagnostic.Message | Should -BeLike "Initiative name 'Storage-Baseline' is already used by the policy at *a.bylaw.ps1:2*"
    }

    It 'gives plain JSON members from the build an ID at <Source>' -ForEach @(
        @{ Source = '-DefinitionScope' }
        @{ Source = 'definitionScope in bylaw.json' }
    ) {
        $files = @{ 'a.bylaw.ps1' = (Get-TestPolicyText) + "`n" + $InitiativeText }
        $arguments = @{ PassThru = $true; Format = 'PlainJson' }
        if ($Source -eq '-DefinitionScope') {
            $arguments.DefinitionScope = $Scope
        }
        else {
            $files['bylaw.json'] = "{ ""definitionScope"": ""$Scope"" }"
        }
        $project = New-TestProject $files
        $result = Build-Bylaw -Path $project @arguments | Where-Object Kind -EQ 'Initiative'
        $result.Json | Should -BeLike "*""policyDefinitionId"": ""$Scope/providers/Microsoft.Authorization/policyDefinitions/test-policy""*"
    }

    It 'fails plain JSON with a member from the build and no definition scope (BYL4012)' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = (Get-TestPolicyText) + "`n" + $InitiativeText }
        $record = Get-BuildError { Build-Bylaw -Path $project -PassThru -Format PlainJson }
        @($record.Exception.Diagnostics.Code) | Should -Be @('BYL4012')
    }

    It 'rejects a -DefinitionScope that is not a management group or subscription (BYL5006)' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText }
        { Build-Bylaw -Path $project -PassThru -DefinitionScope '/subscriptions/x/resourceGroups/rg' } | Should -Throw '*BYL5006*'
    }

    It 'reports an initiative''s errors with its file and line, and writes nothing' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = (Get-TestPolicyText) + "`n" + $InitiativeText.Replace("PolicyDefinition 'test-policy'", "PolicyDefinition 'test-policy' -Group Missing") }
        $out = Join-Path $project 'out'
        $record = Get-BuildError { Build-Bylaw -Path $project -OutputPath $out }
        @($record.Exception.Diagnostics.Code) | Should -Be @('BYL3113')
        $record.ErrorDetails.Message | Should -BeLike '*a.bylaw.ps1:11 `[PolicyDefinition`] BYL3113*'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'does not warn about a file with only initiatives' {
        $project = New-TestProject @{ 'a.bylaw.ps1' = Get-TestPolicyText; 'b.bylaw.ps1' = $InitiativeText }
        $null = Build-Bylaw -Path $project -PassThru -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join "`n") | Should -Not -BeLike '*BYL5021*'
    }
}
