[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'InModuleScope parameters are used inside Mock and Should -Throw scriptblocks, which PSScriptAnalyzer does not follow.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    function New-TestRoleMap {
        # Writes a role map file to TestDrive and returns its path.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper that writes to TestDrive only.')]
        param([Parameter(Mandatory)] [string] $Json, [string] $Name = 'roles.json')
        $path = Join-Path $TestDrive $Name
        Set-Content -Path $path -Value $Json -Encoding utf8NoBOM
        $path
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Bundled role map' {
    BeforeAll {
        $script:bundledPath = Join-Path $PSScriptRoot '../../../src/Data/roles.json'
    }

    It 'maps the starter roles, checked against Learn, to their GUIDs' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $roles = (Read-BylawRoleMapData -Path $Path).Roles
            $roles['Contributor'] | Should -Be 'b24988ac-6180-42a0-ab88-20f7382dd24c'
            $roles['Tag Contributor'] | Should -Be '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
            $roles['Storage Account Contributor'] | Should -Be '17d1049b-9a84-46fb-8f53-869881c3d3ab'
            $roles.Count | Should -Be 8
        }
    }

    It 'is in canonical form, sorted by name' {
        InModuleScope Bylaw -Parameters @{ Path = $bundledPath } {
            param($Path)
            $text = [System.IO.File]::ReadAllText($Path)
            $data = ConvertFrom-BylawJson -Json $text
            ConvertTo-BylawJson -InputObject $data | Should -BeExactly $text
            $names = @($data.roles.Keys)
            $names | Should -Be @($names | Sort-Object -Culture ([cultureinfo]::InvariantCulture))
        }
    }
}

Describe 'Read-BylawRoleMapData' {
    It 'looks up role names ignoring case' {
        $path = New-TestRoleMap '{ "schemaVersion": 1, "generatedAt": "2026-01-01T00:00:00Z", "roles": { "Tag Contributor": "4a9ae827-6dc8-4573-8ac7-8239d42aa03f" } }'
        InModuleScope Bylaw -Parameters @{ Path = $path } {
            param($Path)
            $data = Read-BylawRoleMapData -Path $Path
            $data.Roles['tag contributor'] | Should -Be '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
            $data.GeneratedAt | Should -Be '2026-01-01T00:00:00Z'
            $data.Path | Should -Be ([System.IO.Path]::GetFullPath($Path))
        }
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'invalid JSON'; Json = '{ not json'; Message = '*not valid JSON*' }
        @{ Case = 'a missing schemaVersion'; Json = '{ "roles": {} }'; Message = '*not a Bylaw role map*' }
        @{ Case = 'another schemaVersion'; Json = '{ "schemaVersion": 2, "roles": {} }'; Message = '*not a Bylaw role map*' }
        @{ Case = 'roles that are not an object'; Json = '{ "schemaVersion": 1, "roles": [] }'; Message = '*not a Bylaw role map*' }
        @{ Case = 'a role ID that is not a GUID'; Json = '{ "schemaVersion": 1, "roles": { "Reader": "nope" } }'; Message = "*role 'Reader'*not a GUID*" }
    ) {
        $path = New-TestRoleMap $Json -Name "bad-$([guid]::NewGuid()).json"
        InModuleScope Bylaw -Parameters @{ Path = $path; Message = $Message } {
            param($Path, $Message)
            { Read-BylawRoleMapData -Path $Path } | Should -Throw "BYL2020: $Message"
        }
    }

    It 'fails for a file that does not exist' {
        InModuleScope Bylaw -Parameters @{ Path = (Join-Path $TestDrive 'nope.json') } {
            param($Path)
            { Read-BylawRoleMapData -Path $Path } | Should -Throw '*BYL2020*was not found*'
        }
    }
}

Describe 'Resolve-BylawRoleMapPath' {
    BeforeAll {
        $script:explicit = New-TestRoleMap '{ "schemaVersion": 1, "roles": {} }' -Name 'explicit.json'
        $script:settings = New-TestRoleMap '{ "schemaVersion": 1, "roles": {} }' -Name 'settings.json'
        $script:user = New-TestRoleMap '{ "schemaVersion": 1, "roles": {} }' -Name 'user.json'
    }

    It 'prefers -RoleCachePath, then bylaw.json, then the user cache, then the bundled file' {
        InModuleScope Bylaw -Parameters @{ Explicit = $explicit; Settings = $settings; User = $user; Missing = (Join-Path $TestDrive 'no-user.json') } {
            param($Explicit, $Settings, $User, $Missing)
            Mock Get-BylawUserRoleCachePath { $User }
            Resolve-BylawRoleMapPath -RoleCachePath $Explicit -SettingsRoleCache $Settings | Should -Be $Explicit
            Resolve-BylawRoleMapPath -SettingsRoleCache $Settings | Should -Be $Settings
            Resolve-BylawRoleMapPath | Should -Be $User

            Mock Get-BylawUserRoleCachePath { $Missing }
            Resolve-BylawRoleMapPath | Should -Be (Get-BylawBundledRoleMapPath)
        }
    }

    It 'fails when an explicit path does not exist' {
        InModuleScope Bylaw -Parameters @{ Missing = (Join-Path $TestDrive 'nope.json') } {
            param($Missing)
            { Resolve-BylawRoleMapPath -RoleCachePath $Missing } | Should -Throw '*BYL2020*-RoleCachePath*'
            { Resolve-BylawRoleMapPath -SettingsRoleCache $Missing } | Should -Throw "*BYL2020*bylaw.json 'roleCache'*"
        }
    }
}

Describe 'Resolve-BylawRoleDefinitionId (ADR-0022)' {
    BeforeAll {
        $script:mapPath = New-TestRoleMap '{ "schemaVersion": 1, "roles": { "Contributor": "b24988ac-6180-42a0-ab88-20f7382dd24c", "Tag Contributor": "4a9ae827-6dc8-4573-8ac7-8239d42aa03f" } }' -Name 'resolve.json'
    }

    It 'resolves <Role> to <Id>' -ForEach @(
        @{ Role = 'Contributor'; Id = '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c' }
        @{ Role = 'tag contributor'; Id = '/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f' }
        @{ Role = '11111111-2222-3333-4444-555555555555'; Id = '/providers/Microsoft.Authorization/roleDefinitions/11111111-2222-3333-4444-555555555555' }
        @{ Role = '/providers/Microsoft.Authorization/roleDefinitions/11111111-2222-3333-4444-555555555555'; Id = '/providers/Microsoft.Authorization/roleDefinitions/11111111-2222-3333-4444-555555555555' }
        @{ Role = '/providers/microsoft.authorization/roleDefinitions/11111111-2222-3333-4444-555555555555'; Id = '/providers/microsoft.authorization/roleDefinitions/11111111-2222-3333-4444-555555555555' }
    ) {
        InModuleScope Bylaw -Parameters @{ Path = $mapPath; Role = $Role; Id = $Id } {
            param($Path, $Role, $Id)
            $result = Resolve-BylawRoleDefinitionId -Role $Role -RoleData (Read-BylawRoleMapData -Path $Path)
            $result.Id | Should -BeExactly $Id
            $result.Message | Should -BeNullOrEmpty
        }
    }

    It 'suggests the closest name for an unknown role' {
        InModuleScope Bylaw -Parameters @{ Path = $mapPath } {
            param($Path)
            $result = Resolve-BylawRoleDefinitionId -Role 'Tag Contributer' -RoleData (Read-BylawRoleMapData -Path $Path)
            $result.Id | Should -Be ''
            $result.Message | Should -BeLike "Role 'Tag Contributer' is not a built-in role*Did you mean 'Tag Contributor'?*by its GUID or full role definition ID*Update-BylawRoleCache*"
        }
    }

    It 'rejects <Case> without a suggestion' -ForEach @(
        @{ Case = 'an empty name'; Role = '' }
        @{ Case = 'a subscription-scoped ID'; Role = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/11111111-2222-3333-4444-555555555555' }
        @{ Case = 'a GUID with braces'; Role = '{11111111-2222-3333-4444-555555555555}' }
    ) {
        InModuleScope Bylaw -Parameters @{ Path = $mapPath; Role = $Role } {
            param($Path, $Role)
            $result = Resolve-BylawRoleDefinitionId -Role $Role -RoleData (Read-BylawRoleMapData -Path $Path)
            $result.Id | Should -Be ''
            $result.Message | Should -Not -BeLike '*Did you mean*'
        }
    }
}

Describe 'Update-BylawRoleCache' {
    BeforeAll {
        $script:fakeRoles = @(
            [pscustomobject]@{ Name = 'Tag Contributor'; Id = '4A9AE827-6DC8-4573-8AC7-8239D42AA03F'; IsCustom = $false }
            [pscustomobject]@{ Name = 'Contributor'; Id = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; IsCustom = $false }
            [pscustomobject]@{ Name = 'Broken'; Id = 'not-a-guid'; IsCustom = $false }
        )
    }

    It 'is exported' {
        Get-Command Update-BylawRoleCache -Module Bylaw | Should -Not -BeNullOrEmpty
    }

    It 'writes a canonical map sorted by name, with lower-case GUIDs' {
        $path = Join-Path $TestDrive 'refreshed-roles.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Roles = $fakeRoles } {
            param($Path, $Roles)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzBuiltInRole { $Roles }

            $summary = Update-BylawRoleCache -OutputPath $Path -PassThru
            $summary.RoleCount | Should -Be 2
            Should -Invoke Assert-BylawAzContext -Times 1 -ParameterFilter { $Command -eq 'Update-BylawRoleCache' }

            $text = [System.IO.File]::ReadAllText($Path)
            $data = ConvertFrom-BylawJson -Json $text
            $data.schemaVersion | Should -Be 1
            $data.generatedAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
            @($data.roles.Keys) | Should -Be @('Contributor', 'Tag Contributor')
            $data.roles['Tag Contributor'] | Should -BeExactly '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
            ConvertTo-BylawJson -InputObject $data | Should -BeExactly $text

            # Loadable by the compiler.
            (Read-BylawRoleMapData -Path $Path).Roles.Count | Should -Be 2
        }
    }

    It 'keeps the first of two roles with the same name, with a warning' {
        $path = Join-Path $TestDrive 'duplicate-roles.json'
        InModuleScope Bylaw -Parameters @{ Path = $path } {
            param($Path)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzBuiltInRole {
                [pscustomobject]@{ Name = 'Reader'; Id = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; IsCustom = $false }
                [pscustomobject]@{ Name = 'Reader'; Id = '11111111-2222-3333-4444-555555555555'; IsCustom = $false }
            }
            Update-BylawRoleCache -OutputPath $Path -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -Be 1
            (Read-BylawRoleMapData -Path $Path).Roles['Reader'] | Should -Be 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
        }
    }

    It 'writes nothing with -WhatIf' {
        $path = Join-Path $TestDrive 'whatif-roles.json'
        InModuleScope Bylaw -Parameters @{ Path = $path; Roles = $fakeRoles } {
            param($Path, $Roles)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzBuiltInRole { $Roles }
            Update-BylawRoleCache -OutputPath $Path -WhatIf
            Test-Path -Path $Path | Should -BeFalse
        }
    }

    It 'fails without writing when Azure returns no roles' {
        $path = Join-Path $TestDrive 'empty-roles.json'
        InModuleScope Bylaw -Parameters @{ Path = $path } {
            param($Path)
            Mock Assert-BylawAzContext {}
            Mock Get-BylawAzBuiltInRole {}
            { Update-BylawRoleCache -OutputPath $Path } | Should -Throw '*returned no built-in roles*'
            Test-Path -Path $Path | Should -BeFalse
        }
    }

    It 'stops with a clear message when there is no Azure context' {
        InModuleScope Bylaw {
            Mock Assert-BylawAzContext { throw [System.InvalidOperationException]::new('Update-BylawRoleCache needs a signed-in Azure context. Run Connect-AzAccount first.') }
            Mock Get-BylawAzBuiltInRole {}
            { Update-BylawRoleCache -OutputPath (Join-Path $TestDrive 'x.json') } | Should -Throw '*Connect-AzAccount*'
            Should -Invoke Get-BylawAzBuiltInRole -Times 0
        }
    }
}
