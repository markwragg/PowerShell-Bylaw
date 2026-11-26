[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope parameters are used inside Mock and Should -Throw scriptblocks, which PSScriptAnalyzer does not follow.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Bundled alias snapshot' {
    BeforeAll {
        $script:bundledPath = Join-Path $PSScriptRoot '../../../src/Data/aliases.json'
    }

    It 'loads and contains the aliases the examples use' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $snapshot = Get-BylawAliasSnapshot -Path $Path
            $snapshot.GetTypeName('microsoft.storage/storageaccounts') | Should -BeExactly 'Microsoft.Storage/storageAccounts'
            $aliases = $snapshot.GetAliases('Microsoft.Storage/storageAccounts')
            $aliases.ContainsKey('Microsoft.Storage/storageAccounts/publicNetworkAccess') | Should -BeTrue
            $aliases.ContainsKey('Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value') | Should -BeTrue
            $snapshot.FindAlias('Microsoft.Compute/imagePublisher') | Should -BeExactly 'Microsoft.Compute/imagePublisher'
        }
    }

    It 'knows which aliases are Modifiable, ignoring case (ADR-0024)' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $snapshot = Get-BylawAliasSnapshot -Path $Path
            $snapshot.IsModifiable('microsoft.storage/storageaccounts/minimumtlsversion') | Should -BeTrue
            $snapshot.IsModifiable('Microsoft.Storage/storageAccounts/accessTier') | Should -BeFalse
            $snapshot.IsModifiable('Microsoft.Storage/storageAccounts/notAnAlias') | Should -BeFalse
        }
    }

    It 'passes the Modifiable aliases through the plain snapshot data' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $data = Read-BylawAliasSnapshotData -Path $Path
            $data.Modifiable | Should -Contain 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
            (New-BylawAliasSnapshot -Data $data).IsModifiable('Microsoft.Storage/storageAccounts/publicNetworkAccess') | Should -BeTrue
        }
    }

    It 'is in canonical form, so a refresh gives minimal diffs' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $text = [System.IO.File]::ReadAllText($Path)
            $roundTrip = ConvertTo-BylawJson -InputObject (ConvertFrom-BylawJson -Json $text)
            $roundTrip | Should -BeExactly $text
        }
    }
}

Describe 'Get-BylawAliasSnapshot' {
    It 'rejects <Case>' -ForEach @(
        @{ Case = 'invalid JSON'; Content = '{ not json'; Pattern = '*is not valid JSON*' }
        @{ Case = 'another schema version'; Content = '{ "schemaVersion": 2, "types": {} }'; Pattern = '*is not a Bylaw alias snapshot*' }
        @{ Case = 'a file without types'; Content = '{ "schemaVersion": 1 }'; Pattern = '*is not a Bylaw alias snapshot*' }
    ) {
        $path = Join-Path $TestDrive "bad-$([guid]::NewGuid()).json"
        Set-Content -Path $path -Value $Content -Encoding utf8NoBOM
        InModuleScope Bylaw -Parameters @{ Path = $path; Pattern = $Pattern } {
            param($Path, $Pattern)
            { Get-BylawAliasSnapshot -Path $Path } | Should -Throw $Pattern
        }
    }

    It 'reports a missing file' {
        InModuleScope Bylaw -Parameters @{ Path = (Join-Path $TestDrive 'missing.json') } {
            param($Path)
            { Get-BylawAliasSnapshot -Path $Path } | Should -Throw '*BYL2010*was not found*'
        }
    }

    It 'caches by path until the file changes' {
        $path = Join-Path $TestDrive 'cached.json'
        Set-Content -Path $path -Value '{ "schemaVersion": 1, "types": { "A.B/c": { "aliases": {} } } }' -Encoding utf8NoBOM
        InModuleScope Bylaw -Parameters @{ Path = $path } {
            param($Path)
            $first = Get-BylawAliasSnapshot -Path $Path
            $second = Get-BylawAliasSnapshot -Path $Path
            [object]::ReferenceEquals($first, $second) | Should -BeTrue

            Set-Content -Path $Path -Value '{ "schemaVersion": 1, "types": { "A.B/d": { "aliases": {} } } }' -Encoding utf8NoBOM
            [System.IO.File]::SetLastWriteTimeUtc($Path, [datetime]::UtcNow.AddMinutes(1))
            $third = Get-BylawAliasSnapshot -Path $Path
            $third.GetTypeName('A.B/d') | Should -Be 'A.B/d'
        }
    }
}

Describe 'Resolve-BylawAliasSnapshotPath' {
    BeforeAll {
        $script:explicit = Join-Path $TestDrive 'explicit.json'
        $script:settings = Join-Path $TestDrive 'settings.json'
        $script:user = Join-Path $TestDrive 'user.json'
        foreach ($path in $explicit, $settings, $user) {
            Set-Content -Path $path -Value '{}' -Encoding utf8NoBOM
        }
    }

    It 'prefers -AliasCachePath, then bylaw.json, then the user cache, then the bundled file' {
        InModuleScope Bylaw -Parameters @{ Explicit = $explicit; Settings = $settings; User = $user; Missing = (Join-Path $TestDrive 'no-user.json') } {
            param($Explicit, $Settings, $User, $Missing)
            Mock Get-BylawUserAliasCachePath { $User }
            Resolve-BylawAliasSnapshotPath -AliasCachePath $Explicit -SettingsAliasCache $Settings | Should -Be $Explicit
            Resolve-BylawAliasSnapshotPath -SettingsAliasCache $Settings | Should -Be $Settings
            Resolve-BylawAliasSnapshotPath | Should -Be $User

            Mock Get-BylawUserAliasCachePath { $Missing }
            Resolve-BylawAliasSnapshotPath | Should -Be (Get-BylawBundledAliasSnapshotPath)
        }
    }

    It 'fails when an explicit path does not exist' {
        InModuleScope Bylaw -Parameters @{ Missing = (Join-Path $TestDrive 'nope.json') } {
            param($Missing)
            { Resolve-BylawAliasSnapshotPath -AliasCachePath $Missing } | Should -Throw '*BYL2010*-AliasCachePath*'
            { Resolve-BylawAliasSnapshotPath -SettingsAliasCache $Missing } | Should -Throw "*BYL2010*bylaw.json 'aliasCache'*"
        }
    }
}

Describe 'Update-BylawAliasCache' {
    BeforeAll {
        $script:fakeProviders = @(
            [pscustomobject]@{
                Namespace    = 'Microsoft.Storage'
                ResourceType = 'storageAccounts'
                Aliases      = @(
                    [pscustomobject]@{ Name = 'Microsoft.Storage/storageAccounts/publicNetworkAccess'; DefaultMetadata = [pscustomobject]@{ Type = 'String'; Attributes = 'Modifiable' } }
                    [pscustomobject]@{ Name = 'Microsoft.Storage/storageAccounts/kind2'; DefaultMetadata = [pscustomobject]@{ Type = 'NotSpecified'; Attributes = 'None' } }
                    [pscustomobject]@{ Name = 'Microsoft.Storage/storageAccounts/allowSharedKeyAccess'; DefaultMetadata = $null }
                )
            }
            [pscustomobject]@{ Namespace = 'Microsoft.StorageSync'; ResourceType = 'storageSyncServices'; Aliases = @([pscustomobject]@{ Name = 'Microsoft.StorageSync/storageSyncServices/x'; DefaultMetadata = $null }) }
            [pscustomobject]@{ Namespace = 'Microsoft.Storage'; ResourceType = 'storageAccounts/blobServices'; Aliases = @() }
        )
    }

    It 'is exported' {
        Get-Command Update-BylawAliasCache -Module Bylaw | Should -Not -BeNullOrEmpty
    }

    It 'writes a canonical snapshot for the requested types only' {
        $path = Join-Path $TestDrive 'refreshed.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Providers = $fakeProviders } {
            param($Path, $Providers)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzPolicyAlias { $Providers }

            $summary = Update-BylawAliasCache -ResourceType 'microsoft.storage/storageaccounts' -OutputPath $Path -PassThru
            $summary.TypeCount | Should -Be 1
            $summary.AliasCount | Should -Be 3
            Should -Invoke Get-BylawAzPolicyAlias -Times 1 -ParameterFilter { $NamespaceMatch -eq 'Microsoft.Storage' }

            $data = ConvertFrom-BylawJson -Json (Get-Content -Path $Path -Raw)
            $data.schemaVersion | Should -Be 1
            $data.generatedAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
            @($data.types.Keys) | Should -Be @('Microsoft.Storage/storageAccounts')
            $aliases = $data.types['Microsoft.Storage/storageAccounts'].aliases
            $aliases['Microsoft.Storage/storageAccounts/publicNetworkAccess'].modifiable | Should -BeTrue
            $aliases['Microsoft.Storage/storageAccounts/publicNetworkAccess'].type | Should -Be 'String'
            $aliases['Microsoft.Storage/storageAccounts/kind2'].Count | Should -Be 0
            $aliases['Microsoft.Storage/storageAccounts/allowSharedKeyAccess'].Count | Should -Be 0

            # Loadable by the compiler.
            (Get-BylawAliasSnapshot -Path $Path).GetTypeName('Microsoft.Storage/storageAccounts') | Should -Not -BeNullOrEmpty
        }
    }

    It 'filters by namespace exactly' {
        $path = Join-Path $TestDrive 'namespace.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Providers = $fakeProviders } {
            param($Path, $Providers)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzPolicyAlias { $Providers }
            $summary = Update-BylawAliasCache -Namespace 'Microsoft.Storage' -OutputPath $Path -PassThru
            $summary.TypeCount | Should -Be 1 -Because 'Microsoft.StorageSync is not Microsoft.Storage, and types without aliases are skipped'
        }
    }

    It 'writes nothing with -WhatIf' {
        $path = Join-Path $TestDrive 'whatif.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Providers = $fakeProviders } {
            param($Path, $Providers)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzPolicyAlias { $Providers }
            Update-BylawAliasCache -OutputPath $Path -WhatIf
            Test-Path -Path $Path | Should -BeFalse
        }
    }

    It 'fails without writing when nothing matches' {
        $path = Join-Path $TestDrive 'empty.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Providers = $fakeProviders } {
            param($Path, $Providers)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzPolicyAlias { $Providers }
            { Update-BylawAliasCache -ResourceType 'Microsoft.Nope/things' -OutputPath $Path } | Should -Throw '*returned no aliases*'
            Test-Path -Path $Path | Should -BeFalse
        }
    }

    It 'stops with a clear message when there is no Azure context' {
        InModuleScope Bylaw {
            Mock Assert-BylawAzContext { throw [System.InvalidOperationException]::new('Update-BylawAliasCache needs a signed-in Azure context. Run Connect-AzAccount first.') }
            Mock Get-BylawAzPolicyAlias {}
            { Update-BylawAliasCache -OutputPath (Join-Path $TestDrive 'x.json') } | Should -Throw '*Connect-AzAccount*'
            Should -Invoke Get-BylawAzPolicyAlias -Times 0
        }
    }
}
