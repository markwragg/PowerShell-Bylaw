BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Properties' {
    It 'maps every valid key' {
        $script = (Format-BylawTestPolicy).Replace(
            "Properties @{ DisplayName = 'Test policy' }",
            "Properties @{ displayname = 'D'; Description = 'Desc'; Category = 'Storage'; Version = '1.0.0'; Mode = 'Indexed'; Preview = `$true; Deprecated = `$false; Metadata = @{ owner = 'team' } }"
        )
        $result = Invoke-BylawTestScript -Script $script
        $result.Diagnostics | Should -BeNullOrEmpty
        $properties = $result.Policies[0].Properties
        $properties.DisplayName | Should -Be 'D'
        $properties.Description | Should -Be 'Desc'
        $properties.Category | Should -Be 'Storage'
        $properties.Version | Should -Be '1.0.0'
        $properties.Mode | Should -Be 'Indexed'
        $properties.Preview | Should -BeTrue
        $properties.Deprecated | Should -BeFalse
        $properties.Metadata.owner | Should -Be 'team'
        $properties.Location.Keyword | Should -Be 'Properties'
    }

    It 'rejects an unknown key and suggests the closest one' {
        $script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "DisplayNmae = 'Test policy'")
        $result = Invoke-BylawTestScript -Script $script
        $result.Codes | Should -Be @('BYL1011')
        $result.Diagnostics[0].Message | Should -BeLike "Unknown Properties key 'DisplayNmae'. Did you mean 'DisplayName'?*"
    }

    It 'rejects <Key> with the wrong type' -ForEach @(
        @{ Key = 'DisplayName'; Value = '42' }
        @{ Key = 'Preview'; Value = "'yes'" }
        @{ Key = 'Metadata'; Value = "'x'" }
    ) {
        $script = (Format-BylawTestPolicy).Replace("DisplayName = 'Test policy'", "$Key = $Value")
        $result = Invoke-BylawTestScript -Script $script
        $result.Codes | Should -Be @('BYL1012')
    }
}

Describe 'Parameter' {
    It 'infers String from the one-line storage form' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra 'Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny')
        $result.Diagnostics | Should -BeNullOrEmpty
        $parameter = $result.Policies[0].Parameters[0]
        $parameter.Name | Should -Be 'Effect'
        $parameter.Type | Should -Be 'String'
        $parameter.AllowedValues | Should -Be @('Audit', 'Deny', 'Disabled')
        $parameter.HasDefault | Should -BeTrue
        $parameter.DefaultValue | Should -Be 'Deny'
    }

    It 'infers <Expected> from a default of <Default>' -ForEach @(
        @{ Default = '$true'; Expected = 'Boolean' }
        @{ Default = '5'; Expected = 'Integer' }
        @{ Default = '1.5'; Expected = 'Float' }
        @{ Default = "@('a', 'b')"; Expected = 'Array' }
        @{ Default = '@{ a = 1 }'; Expected = 'Object' }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra "Parameter P -Default $Default")
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policies[0].Parameters[0].Type | Should -Be $Expected
    }

    It 'accepts the hashtable form with metadata and a JSON name' {
        $extra = "Parameter @{ Name = 'Locations'; Type = 'array'; DisplayName = 'Allowed locations'; JsonName = 'listOfAllowedLocations'; Metadata = @{ strongType = 'location' } }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra $extra)
        $result.Diagnostics | Should -BeNullOrEmpty
        $parameter = $result.Policies[0].Parameters[0]
        $parameter.Type | Should -Be 'Array'
        $parameter.DisplayName | Should -Be 'Allowed locations'
        $parameter.JsonName | Should -Be 'listOfAllowedLocations'
        $parameter.Metadata.strongType | Should -Be 'location'
        $parameter.HasDefault | Should -BeFalse
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown type'; Extra = 'Parameter P -Type Text -Default x' }
        @{ Case = 'a type that cannot be inferred'; Extra = 'Parameter P' }
        @{ Case = 'a duplicate name'; Extra = 'Parameter P -Default x; Parameter p -Default y' }
        @{ Case = 'an invalid name'; Extra = "Parameter 'my-param' -Default x" }
        @{ Case = 'mixed forms'; Extra = "Parameter @{ Name = 'P'; Default = 'x' } -Type String" }
        @{ Case = 'an unknown hashtable key'; Extra = "Parameter @{ Name = 'P'; Default = 'x'; Strongtype = 'location' }" }
        @{ Case = 'a hashtable without Name'; Extra = "Parameter @{ Default = 'x' }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra $Extra)
        $result.Codes | Should -Contain 'BYL1015'
    }
}

Describe 'Effect, Param and Expr' {
    It 'takes a literal effect' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy)
        $result.Policies[0].Effect.Value.Value | Should -Be 'Deny'
    }

    It 'takes a parameter reference' {
        $script = (Format-BylawTestPolicy -Extra 'Parameter Effect -AllowedValues Audit, Deny -Default Deny').Replace('Effect Deny', 'Effect (Param Effect)')
        $result = Invoke-BylawTestScript -Script $script
        $result.Diagnostics | Should -BeNullOrEmpty
        $value = $result.Policies[0].Effect.Value
        InModuleScope Bylaw -Parameters @{ Value = $value } {
            param($Value)
            $Value | Should -BeOfType ([BylawParamRef])
        }
        $value.Name | Should -Be 'Effect'
        $value.Location.Keyword | Should -Be 'Param'
    }

    It 'rejects a non-string effect' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect 42')
        $result.Codes | Should -Be @('BYL1019')
    }

    It 'keeps Expr text verbatim' {
        $requirements = "Require 'r' { Field location | Must -Be (Expr `"[resourceGroup().location]`") }"
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
        $result.Policies[0].Resource.Requirements[0].Children[0].Value.Text | Should -BeExactly '[resourceGroup().location]'
    }
}
