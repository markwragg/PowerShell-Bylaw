BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    $script:Scope = '/providers/Microsoft.Management/managementGroups/contoso'
    $script:InheritTag = '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54'

    function script:Get-PolicyText {
        # A storage policy with a required parameter (Tier), an Array parameter, and the given effect.
        param(
            [string] $Name = 'storage-tier',
            [string] $Effect = '(Param Effect)',
            [string] $Version = '1.2.0'
        )
        $versionText = if ($Version) { "; Version = '$Version'" } else { '' }
        $effectParameter = if ($Effect -eq '(Param Effect)') { 'Parameter Effect -AllowedValues Audit, Disabled -Default Audit' } else { '' }
        @"
Policy '$Name' {
    Properties @{ DisplayName = 'Storage tier'; Category = 'Storage'; Mode = 'Indexed'$versionText }
    $effectParameter
    Parameter Tier -AllowedValues Hot, Cool
    Parameter Locations -Type Array -Default @('uksouth')
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'r' {
            Field accessTier | Must -Be (Param Tier)
            Field location | Must -BeIn (Param Locations)
        }
    }
    Effect $Effect
}
"@
    }

    function script:Get-InitiativeText {
        param([string] $Body, [string] $Extra = '')
        @"
Initiative 'storage-baseline' {
    Properties @{ DisplayName = 'Storage baseline'; Category = 'Storage'; Version = '1.0.0' }
    $Extra
    $Body
}
"@
    }

    function script:New-TestProject {
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

    function script:Invoke-MemberBuild {
        # Builds a policy file and an initiative file. Returns the error diagnostics, the warnings,
        # and the results when the build succeeds.
        param(
            [string] $Body,
            [string] $Extra = '',
            [string] $Policy = (Get-PolicyText),
            [string] $Format = 'Epac'
        )
        $project = New-TestProject @{ 'a-policy.bylaw.ps1' = $Policy; 'b-initiative.bylaw.ps1' = (Get-InitiativeText -Body $Body -Extra $Extra) }
        $arguments = @{ Path = $project; PassThru = $true; Format = $Format; DefinitionScope = $Scope }
        $warnings = $null
        try {
            $results = @(Build-Bylaw @arguments -WarningVariable warnings -WarningAction SilentlyContinue)
            [pscustomobject]@{ Errors = @(); Codes = @(); Warnings = @($warnings | ForEach-Object { "$_" }); Results = $results }
        }
        catch {
            $diagnostics = @($_.Exception.Diagnostics)
            [pscustomobject]@{ Errors = $diagnostics; Codes = @($diagnostics | ForEach-Object Code); Warnings = @($warnings | ForEach-Object { "$_" }); Results = @() }
        }
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Initiative member checks (ADR-0034)' {
    It 'accepts a member from another file whose parameters fit' {
        $result = Invoke-MemberBuild -Extra 'Parameter Tier -AllowedValues Hot -Default Hot; Parameter Effect -AllowedValues Audit, Disabled -Default Audit' -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = Param Tier; effect = Param Effect }"
        $result.Errors | Should -BeNullOrEmpty
        $result.Warnings | Should -BeNullOrEmpty
        $result.Results.Kind | Should -Be @('Policy', 'Initiative')
    }

    It 'matches passed names against the policy''s parameters ignoring case' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Parameters @{ TIER = 'Hot' }"
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'reports BYL3120 for a policy that is not in the build, with the closest name' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tiers' -Parameters @{ tier = 'Hot' }"
        $result.Codes | Should -Be @('BYL3120')
        $result.Errors[0].Message | Should -BeLike "*includes policy 'storage-tiers', which isn't in this build. Did you mean 'storage-tier'?*"
        $result.Errors[0].Location.File | Should -BeLike '*b-initiative.bylaw.ps1'
        $result.Errors[0].Location.Line | Should -Be 4
    }

    It 'warns (BYL3127) when the name differs from the policy''s only in case' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'Storage-Tier' -Parameters @{ tier = 'Hot' }"
        $result.Errors | Should -BeNullOrEmpty
        ($result.Warnings -join "`n") | Should -BeLike "*BYL3127: PolicyDefinition 'Storage-Tier' is emitted as written, but the policy is named 'storage-tier'*"
        ($result.Results | Where-Object Kind -EQ 'Initiative').Warnings -join "`n" | Should -BeLike '*BYL3127*'
    }

    It 'reports BYL3121 for a value passed to a parameter the policy does not have' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = 'Hot'; tiers = 'Cool' }"
        $result.Codes | Should -Be @('BYL3121')
        $result.Errors[0].Message | Should -BeLike "*passes 'tiers', which is not a parameter of policy 'storage-tier'. Its parameters: effect, tier, locations."
    }

    It 'reports BYL3122 for a required parameter that is not passed' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier'"
        $result.Codes | Should -Be @('BYL3122')
        $result.Errors[0].Message | Should -BeLike "*doesn't pass 'tier', which policy 'storage-tier' requires: it has no default*"
    }

    It 'reports BYL3123 for a literal that <Case>' -ForEach @(
        @{ Case = 'is not an allowed value'; Value = "tier = 'Archive'"; Message = "*passes 'Archive' to 'tier', which allows only Hot, Cool." }
        @{ Case = 'is of the wrong type'; Value = "tier = 'Hot'; locations = 5"; Message = "*passes '5' to 'locations', which is of type Array." }
        @{ Case = 'is an Effect the member doesn''t allow'; Value = "tier = 'Hot'; effect = 'Deny'"; Message = "*passes 'Deny' to 'effect', which allows only Audit, Disabled." }
    ) {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Parameters @{ $Value }"
        $result.Codes | Should -Be @('BYL3123')
        $result.Errors[0].Message | Should -BeLike $Message
    }

    It 'reports BYL3124 for an initiative parameter of another type' {
        $result = Invoke-MemberBuild -Extra 'Parameter Locations -Default uksouth' -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = 'Hot'; locations = Param Locations }"
        $result.Codes | Should -Be @('BYL3124')
        $result.Errors[0].Message | Should -BeLike "*passes initiative parameter 'locations', of type String, to 'locations', which is of type Array."
    }

    It 'reports BYL3125 for an initiative parameter whose <Case>' -ForEach @(
        @{ Case = 'default is not allowed'; Extra = 'Parameter Tier -Default Archive'; Message = "*whose default 'Archive' isn't one of the values 'tier' allows (Hot, Cool)*" }
        @{ Case = 'allowed values go beyond the member''s'; Extra = 'Parameter Tier -AllowedValues Hot, Cool, Archive -Default Hot'; Message = "*which allows 'Archive', to 'tier', which doesn't (Hot, Cool)*" }
    ) {
        $result = Invoke-MemberBuild -Extra $Extra -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = Param Tier }"
        $result.Codes | Should -Contain 'BYL3125'
        (@($result.Errors | Where-Object Code -EQ 'BYL3125').Message -join "`n") | Should -BeLike $Message
    }

    It 'warns (BYL3128) for an initiative parameter with no allowed values, passed to one with them' {
        $result = Invoke-MemberBuild -Extra 'Parameter Tier -Default Hot' -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = Param Tier }"
        $result.Errors | Should -BeNullOrEmpty
        ($result.Warnings -join "`n") | Should -BeLike "*BYL3128: *initiative parameter 'tier', which allows any value, to 'tier', which allows only Hot, Cool*"
    }

    It 'does not check an Arm or ResourceGroupTag value' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = (Arm `"[if(true(), 'Hot', 'Cool')]`"); locations = (ResourceGroupTag Region) }"
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'checks -Version <Version> against version 1.2.0 as <Expected>' -ForEach @(
        @{ Version = '1.*.*'; Expected = 'a match' }
        @{ Version = '1.2.*'; Expected = 'a match' }
        @{ Version = '1.2.0'; Expected = 'a match' }
        @{ Version = '1.3.*'; Expected = 'BYL3126' }
        @{ Version = '2.*.*'; Expected = 'BYL3126' }
    ) {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Version '$Version' -Parameters @{ tier = 'Hot' }"
        if ($Expected -eq 'a match') {
            $result.Errors | Should -BeNullOrEmpty
        }
        else {
            $result.Codes | Should -Be @($Expected)
        }
    }

    It 'warns (BYL3129) that Azure matches -Version against a version Bylaw does not emit' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition 'storage-tier' -Version '1.*.*' -Parameters @{ tier = 'Hot' }"
        $result.Errors | Should -BeNullOrEmpty
        ($result.Warnings -join "`n") | Should -BeLike "*BYL3129: PolicyDefinition 'storage-tier' pins version 1.*.*, but Azure matches definitionVersion against a definition's top-level version property*"
    }

    It 'does not warn about -Version on a member by -Id' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition -Id '$InheritTag' -ReferenceId InheritTag -Version '1.*.*'"
        ($result.Warnings -join "`n") | Should -Not -BeLike '*BYL3129*'
    }

    It 'reports BYL3126 for -Version on a policy with no Version' {
        $result = Invoke-MemberBuild -Policy (Get-PolicyText -Version '') -Format PlainJson -Body "PolicyDefinition 'storage-tier' -Version '1.*.*' -Parameters @{ tier = 'Hot' }"
        $result.Codes | Should -Be @('BYL3126')
        $result.Errors[0].Message | Should -BeLike "*has no Version*"
    }

    It 'checks against the emitted parameters: <Format> <Outcome> for effect on a literal-effect policy' -ForEach @(
        @{ Format = 'Epac'; Outcome = 'accepts a value' }
        @{ Format = 'PlainJson'; Outcome = 'reports BYL3121' }
    ) {
        $result = Invoke-MemberBuild -Policy (Get-PolicyText -Effect 'Deny') -Format $Format -Body "PolicyDefinition 'storage-tier' -Parameters @{ tier = 'Hot'; effect = 'Audit' }"
        if ($Format -eq 'Epac') {
            $result.Errors | Should -BeNullOrEmpty
        }
        else {
            $result.Codes | Should -Be @('BYL3121')
        }
    }

    It 'does not check a member by -Id' {
        $result = Invoke-MemberBuild -Body "PolicyDefinition -Id '$InheritTag' -ReferenceId InheritTag -Parameters @{ notAParameter = 1 }"
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'checks every member, in every initiative of the build' {
        $body = "PolicyDefinition 'storage-tier' -Parameters @{ tier = 'Hot' }; PolicyDefinition 'missing-one' -ReferenceId m1; PolicyDefinition 'storage-tier' -ReferenceId t2"
        $result = Invoke-MemberBuild -Body $body
        $result.Codes | Should -Be @('BYL3120', 'BYL3122')
    }

    It 'skips the checks when a file has errors, so they add no noise' {
        $result = Invoke-MemberBuild -Policy (Get-PolicyText).Replace('Field accessTier', 'Field accessTeir') -Body "PolicyDefinition 'storage-tier'"
        $result.Codes | Should -Be @('BYL2001')
    }
}
