BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    function script:Read-TestSettingsFile([string] $Json) {
        $path = Join-Path $TestDrive 'read/bylaw.json'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $path)
        Set-Content -LiteralPath $path -Value $Json -NoNewline
        InModuleScope Bylaw -Parameters @{ Path = $path } { param($Path) Read-BylawSettingsFile -Path $Path }
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Find-BylawSettingsFile' {
    BeforeAll {
        # TestDrive/repo/.git, TestDrive/repo/bylaw.json, TestDrive/repo/a/b/policy.bylaw.ps1
        $script:Repo = Join-Path $TestDrive 'repo'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $Repo '.git'), (Join-Path $Repo 'a/b'), (Join-Path $Repo 'c')
        Set-Content -LiteralPath (Join-Path $Repo 'bylaw.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $Repo 'a/b/policy.bylaw.ps1') -Value ''
        Set-Content -LiteralPath (Join-Path $Repo 'c/bylaw.json') -Value '{}'
        # A bylaw.json above the repository root must not be found from inside another repository.
        $script:Other = Join-Path $TestDrive 'outer/inner'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $Other '.git')
        Set-Content -LiteralPath (Join-Path $TestDrive 'outer/bylaw.json') -Value '{}'
    }

    It 'finds bylaw.json in a parent folder' {
        InModuleScope Bylaw -Parameters @{ Start = (Join-Path $Repo 'a/b') } { param($Start) Find-BylawSettingsFile -StartPath $Start } |
            Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Repo 'bylaw.json')))
    }

    It 'starts from the folder of a file' {
        InModuleScope Bylaw -Parameters @{ Start = (Join-Path $Repo 'a/b/policy.bylaw.ps1') } { param($Start) Find-BylawSettingsFile -StartPath $Start } |
            Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Repo 'bylaw.json')))
    }

    It 'prefers the nearest bylaw.json' {
        InModuleScope Bylaw -Parameters @{ Start = (Join-Path $Repo 'c') } { param($Start) Find-BylawSettingsFile -StartPath $Start } |
            Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Repo 'c/bylaw.json')))
    }

    It 'stops at the folder that contains .git' {
        InModuleScope Bylaw -Parameters @{ Start = $Other } { param($Start) Find-BylawSettingsFile -StartPath $Start } | Should -BeNullOrEmpty
    }
}

Describe 'Read-BylawSettingsFile' {
    It 'returns the defaults without a settings file' {
        $result = InModuleScope Bylaw { Read-BylawSettingsFile -Path '' }
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Settings.LanguageVersion | Should -Be '1.0'
        $result.Settings.AliasCache | Should -BeNullOrEmpty
    }

    It 'reads languageVersion' {
        $result = Read-TestSettingsFile '{ "languageVersion": "1.0" }'
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Settings.LanguageVersion | Should -Be '1.0'
    }

    It 'resolves aliasCache relative to bylaw.json' {
        $result = Read-TestSettingsFile '{ "aliasCache": "data/aliases.json" }'
        $result.Settings.AliasCache | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'read/data/aliases.json')))
    }

    It 'resolves roleCache relative to bylaw.json' {
        $result = Read-TestSettingsFile '{ "roleCache": "data/roles.json" }'
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Settings.RoleCache | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'read/data/roles.json')))
    }

    It 'resolves initiativeOutputPath relative to bylaw.json, and reads definitionScope' {
        $result = Read-TestSettingsFile '{ "initiativeOutputPath": "Definitions/policySetDefinitions", "definitionScope": "/providers/Microsoft.Management/managementGroups/contoso" }'
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Settings.InitiativeOutputPath | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'read/Definitions/policySetDefinitions')))
        $result.Settings.DefinitionScope | Should -BeExactly '/providers/Microsoft.Management/managementGroups/contoso'
    }

    It 'accepts a subscription as definitionScope' {
        (Read-TestSettingsFile '{ "definitionScope": "/subscriptions/00000000-0000-0000-0000-000000000000" }').Diagnostics | Should -BeNullOrEmpty
    }

    It 'reports <Code> for <Case>' -ForEach @(
        @{ Code = 'BYL5001'; Case = 'invalid JSON'; Json = '{ "languageVersion": ' }
        @{ Code = 'BYL5001'; Case = 'a JSON array'; Json = '[]' }
        @{ Code = 'BYL5002'; Case = 'an unknown key'; Json = '{ "languageVersoin": "1.0" }' }
        @{ Code = 'BYL5002'; Case = 'a key in the wrong case'; Json = '{ "LanguageVersion": "1.0" }' }
        @{ Code = 'BYL5004'; Case = 'an unsupported language version'; Json = '{ "languageVersion": "2.0" }' }
        @{ Code = 'BYL5004'; Case = 'a numeric language version'; Json = '{ "languageVersion": 1.0 }' }
        @{ Code = 'BYL5005'; Case = 'an aliasCache that is not a string'; Json = '{ "aliasCache": 5 }' }
        @{ Code = 'BYL5005'; Case = 'an empty roleCache'; Json = '{ "roleCache": "" }' }
        @{ Code = 'BYL5005'; Case = 'an initiativeOutputPath that is not a string'; Json = '{ "initiativeOutputPath": true }' }
        @{ Code = 'BYL5006'; Case = 'a definitionScope that is a resource group'; Json = '{ "definitionScope": "/subscriptions/x/resourceGroups/rg" }' }
        @{ Code = 'BYL5006'; Case = 'a definitionScope that is not a string'; Json = '{ "definitionScope": 5 }' }
    ) {
        @((Read-TestSettingsFile $Json).Diagnostics.Code) | Should -Contain $Code
    }

    It 'suggests the closest key' {
        (Read-TestSettingsFile '{ "languageVersoin": "1.0" }').Diagnostics[0].Message | Should -BeLike "*Did you mean 'languageVersion'*"
    }

    It 'reports a missing settings file' {
        $result = InModuleScope Bylaw -Parameters @{ Path = (Join-Path $TestDrive 'missing/bylaw.json') } { param($Path) Read-BylawSettingsFile -Path $Path }
        @($result.Diagnostics.Code) | Should -Be @('BYL5003')
    }
}
