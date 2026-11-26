BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Format-EffectPolicy {
        # A policy on storage accounts with the given effect keyword in place of Effect.
        param(
            [string] $Effect = 'DenyAction Delete',
            [string] $Body = "When { Tag protect | Must -Be 'yes' }",
            [string] $Extra = '',
            [string] $Type = 'Microsoft.Storage/storageAccounts',
            [string] $Properties = "DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Storage'; Version = '1.0.0'"
        )
        @"
Policy 'test-policy' {
    Properties @{ $Properties }
    $Extra
    Resource '$Type' {
        $Body
    }
    $Effect
}
"@
    }

    function Invoke-EffectCompile {
        param([string] $Effect, [string] $Body, [string] $Extra, [string] $Type, [string] $Properties, [switch] $AllowUnknownAlias)
        $arguments = @{}
        foreach ($name in 'Effect', 'Body', 'Extra', 'Type', 'Properties') {
            if ($PSBoundParameters.ContainsKey($name)) {
                $arguments[$name] = $PSBoundParameters[$name]
            }
        }
        Invoke-BylawTestCompile -Script (Format-EffectPolicy @arguments) -AllowUnknownAlias:$AllowUnknownAlias
    }

    function Get-Then {
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['then']
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }

    function Get-EpacEffectParameter {
        param([Parameter(Mandatory)] $Result)
        $Result.Emitted.Diagnostics | Should -BeNullOrEmpty
        (ConvertFrom-Json -InputObject $Result.Emitted.Text -AsHashtable).properties.parameters.effect
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'DenyAction (ADR-0028)' {
    Context 'emitted rule' {
        It 'emits the effect and the action, with no cascade behaviour by default' {
            $then = Get-Then (Invoke-EffectCompile)
            $then['effect'] | Should -BeExactly 'DenyAction'
            $then['details'].Keys | Should -Be @('actionNames')
            , $then['details']['actionNames'] | Should -BeOfType [object[]]
            $then['details']['actionNames'] | Should -BeExactly @('delete')
        }

        It 'accepts the action <Action> in any case' -ForEach @(
            @{ Action = 'Delete' }, @{ Action = 'delete' }, @{ Action = 'DELETE' }
        ) {
            (Get-Then (Invoke-EffectCompile -Effect "DenyAction $Action"))['details']['actionNames'] | Should -BeExactly @('delete')
        }

        It 'emits -CascadeBehavior <Written> as <Emitted>' -ForEach @(
            @{ Written = 'Deny'; Emitted = 'deny' }
            @{ Written = 'allow'; Emitted = 'allow' }
            @{ Written = 'ALLOW'; Emitted = 'allow' }
        ) {
            $details = (Get-Then (Invoke-EffectCompile -Effect "DenyAction Delete -CascadeBehavior $Written"))['details']
            $details.Keys | Should -Be @('actionNames', 'cascadeBehaviors')
            $details['cascadeBehaviors'].Keys | Should -Be @('resourceGroup')
            $details['cascadeBehaviors']['resourceGroup'] | Should -BeExactly $Emitted
        }

        It 'emits an effect parameter from -Effect' {
            $then = Get-Then (Invoke-EffectCompile -Effect 'DenyAction Delete -Effect (Param Effect)' -Extra 'Parameter Effect -AllowedValues DenyAction, Disabled -Default DenyAction')
            $then['effect'] | Should -BeExactly "[parameters('effect')]"
        }

        It 'generates an EPAC effect parameter that allows DenyAction and Disabled' {
            $parameter = Get-EpacEffectParameter (Invoke-EffectCompile)
            $parameter['allowedValues'] | Should -BeExactly @('DenyAction', 'Disabled')
            $parameter['defaultValue'] | Should -BeExactly 'DenyAction'
        }

        It 'conforms to the EPAC schema' {
            $result = Invoke-EffectCompile -Effect 'DenyAction Delete -CascadeBehavior Deny'
            Test-Json -Json $result.Emitted.Text -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json') | Should -BeTrue
        }

        It 'does not warn that there is no Require block' {
            (Invoke-EffectCompile).Codes | Should -Not -Contain 'BYL3041'
        }
    }

    Context 'errors and warnings' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1033'; Case = 'no action'; Effect = 'DenyAction' }
            @{ Code = 'BYL1033'; Case = 'an action other than Delete'; Effect = 'DenyAction Write' }
            @{ Code = 'BYL1034'; Case = 'an invalid -CascadeBehavior'; Effect = 'DenyAction Delete -CascadeBehavior Block' }
            @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Effect = 'DenyAction Delete -Effect Disabled' }
            @{ Code = 'BYL1026'; Case = 'Effect and DenyAction'; Effect = 'Effect Deny; DenyAction Delete' }
            @{ Code = 'BYL1026'; Case = 'DenyAction and Manual'; Effect = 'DenyAction Delete; Manual' }
            @{ Code = 'BYL1004'; Case = 'two DenyAction'; Effect = 'DenyAction Delete; DenyAction Delete' }
            @{ Code = 'BYL1002'; Case = 'DenyAction inside Resource'; Effect = 'Effect Deny'; Body = 'DenyAction Delete' }
        ) {
            $arguments = @{ Effect = $Effect }
            if ($_.ContainsKey('Body')) {
                $arguments.Body = $_.Body
            }
            $result = Invoke-BylawTestScript -Script (Format-EffectPolicy @arguments)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'explains that Delete is the only action' {
            $result = Invoke-BylawTestScript -Script (Format-EffectPolicy -Effect 'DenyAction Write')
            Get-Message $result 'BYL1033' | Should -Be "'Write' is not an action DenyAction can block. Delete is the only action Azure supports: DenyAction Delete."
        }

        It 'names the keyword that already set the effect' {
            $result = Invoke-BylawTestScript -Script (Format-EffectPolicy -Effect 'Effect Deny; DenyAction Delete')
            Get-Message $result 'BYL1026' | Should -BeLike '*Effect already sets it at line 7. DenyAction sets the effect itself; use DenyAction -Effect (Param Effect)*'
        }

        It 'reports BYL3073 for -CascadeBehavior with Mode <Mode>' -ForEach @(
            @{ Mode = 'All'; Properties = "DisplayName = 'x'; Mode = 'All'" }
            @{ Mode = 'All (the default)'; Properties = "DisplayName = 'x'" }
        ) {
            $result = Invoke-EffectCompile -Effect 'DenyAction Delete -CascadeBehavior Deny' -Properties $Properties
            Get-Message $result 'BYL3073' | Should -BeLike "*only supported with Mode = 'Indexed' (Mode is All)*"
        }

        It 'accepts -CascadeBehavior with Mode indexed in any case' {
            $result = Invoke-EffectCompile -Effect 'DenyAction Delete -CascadeBehavior Deny' -Properties "DisplayName = 'x'; Mode = 'indexed'"
            $result.Errors | Should -BeNullOrEmpty
        }

        It 'warns (BYL3074) that DenyAction never applies to <Type>' -ForEach @(
            @{ Type = 'Microsoft.Authorization/policyAssignments' }
            @{ Type = 'Microsoft.Authorization/denyAssignments' }
            @{ Type = 'Microsoft.Blueprint/blueprintAssignments' }
            @{ Type = 'Microsoft.Resources/deploymentStacks' }
            @{ Type = 'Microsoft.Resources/subscriptions' }
            @{ Type = 'microsoft.authorization/locks' }
        ) {
            $result = Invoke-EffectCompile -Type $Type -Body '' -AllowUnknownAlias
            $diagnostic = $result.Diagnostics | Where-Object Code -EQ 'BYL3074'
            $diagnostic.Severity.ToString() | Should -Be 'Warning'
            $diagnostic.Message | Should -BeLike '*never applies to*'
        }

        It 'reports BYL3072 for an effect parameter that allows <Value>' -ForEach @(
            @{ Value = 'Deny' }, @{ Value = 'Audit' }, @{ Value = 'Manual' }
        ) {
            $result = Invoke-EffectCompile -Effect 'DenyAction Delete -Effect (Param Effect)' -Extra "Parameter Effect -AllowedValues DenyAction, $Value -Default DenyAction"
            Get-Message $result 'BYL3072' | Should -Be "Effect parameter 'Effect' of a DenyAction policy allows '$Value'. Allowed values: DenyAction, Disabled."
        }

        It 'suggests the allowed values for an undeclared effect parameter' {
            $result = Invoke-EffectCompile -Effect 'DenyAction Delete -Effect (Param Effect)'
            Get-Message $result 'BYL3020' | Should -BeLike '*-AllowedValues DenyAction, Disabled -Default DenyAction*'
        }
    }
}

Describe 'Manual (ADR-0028)' {
    It 'emits the effect with no details by default' {
        $then = Get-Then (Invoke-EffectCompile -Effect 'Manual' -Body '')
        $then['effect'] | Should -BeExactly 'Manual'
        $then.Keys | Should -Be @('effect')
    }

    It 'emits -DefaultState <Written> as <Emitted>' -ForEach @(
        @{ Written = 'Unknown'; Emitted = 'Unknown' }
        @{ Written = 'compliant'; Emitted = 'Compliant' }
        @{ Written = 'NonCompliant'; Emitted = 'Non-compliant' }
    ) {
        $then = Get-Then (Invoke-EffectCompile -Effect "Manual -DefaultState $Written" -Body '')
        $then['details'].Keys | Should -Be @('defaultState')
        $then['details']['defaultState'] | Should -BeExactly $Emitted
    }

    It 'generates an EPAC effect parameter that allows Manual and Disabled' {
        $parameter = Get-EpacEffectParameter (Invoke-EffectCompile -Effect 'Manual' -Body '')
        $parameter['allowedValues'] | Should -BeExactly @('Manual', 'Disabled')
        $parameter['defaultValue'] | Should -BeExactly 'Manual'
    }

    It 'emits an effect parameter from -Effect' {
        $then = Get-Then (Invoke-EffectCompile -Effect 'Manual -Effect (Param Effect)' -Body '' -Extra 'Parameter Effect -AllowedValues Manual, Disabled -Default Manual')
        $then['effect'] | Should -BeExactly "[parameters('effect')]"
    }

    It 'conforms to the EPAC schema' {
        $result = Invoke-EffectCompile -Effect 'Manual -DefaultState NonCompliant' -Body ''
        Test-Json -Json $result.Emitted.Text -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json') | Should -BeTrue
    }

    It 'does not warn that there is no Require block' {
        (Invoke-EffectCompile -Effect 'Manual' -Body '').Codes | Should -Not -Contain 'BYL3041'
    }

    It 'reports <Code> for <Case>' -ForEach @(
        @{ Code = 'BYL1035'; Case = 'an invalid -DefaultState'; Effect = 'Manual -DefaultState Exempt' }
        @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Effect = 'Manual -Effect Disabled' }
        @{ Code = 'BYL1026'; Case = 'Manual and Modify'; Effect = "Manual; Modify -Role 'Tag Contributor' { Tag A | AddOrReplace 'a' }" }
        @{ Code = 'BYL1004'; Case = 'two Manual'; Effect = 'Manual; Manual' }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-EffectPolicy -Effect $Effect -Body '')
        $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
    }

    It 'explains how to write Non-compliant' {
        $result = Invoke-BylawTestScript -Script (Format-EffectPolicy -Effect 'Manual -DefaultState Non-compliant' -Body '')
        Get-Message $result 'BYL1035' | Should -BeLike "*Write NonCompliant; it's emitted as 'Non-compliant'."
    }

    It 'reports BYL3072 for an effect parameter that allows Audit' {
        $result = Invoke-EffectCompile -Effect 'Manual -Effect (Param Effect)' -Body '' -Extra 'Parameter Effect -AllowedValues Manual, Audit -Default Manual'
        Get-Message $result 'BYL3072' | Should -Be "Effect parameter 'Effect' of a Manual policy allows 'Audit'. Allowed values: Manual, Disabled."
    }
}

Describe 'Effect with a keyword effect name' {
    It 'points Effect <Name> to the <Name> keyword' -ForEach @(
        @{ Name = 'DenyAction' }, @{ Name = 'Manual' }
    ) {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Effect $Name)
        Get-Message $result 'BYL3030' | Should -BeLike "*$Name has its own keyword, which takes the place of Effect*"
    }

    It 'still rejects DenyAction as an allowed value of an Effect parameter' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Effect '(Param Effect)' -Extra 'Parameter Effect -AllowedValues Deny, DenyAction -Default Deny')
        $result.Codes | Should -Contain 'BYL3033'
    }

    It 'reports no effect when the policy has none' {
        $result = Invoke-BylawTestScript -Script (Format-EffectPolicy -Effect '')
        Get-Message $result 'BYL1006' | Should -BeLike '*DenyAction Delete, Manual*'
    }
}
