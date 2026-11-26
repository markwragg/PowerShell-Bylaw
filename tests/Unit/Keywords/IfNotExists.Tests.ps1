BeforeDiscovery {
    # The -ForEach data below is built during discovery, so these are needed then too.
    $script:Extension = 'Microsoft.Compute/virtualMachines/extensions'

    function script:Format-AineBlock {
        # An AuditIfNotExists block with one Require holding the given statements.
        param([string] $Statements, [string] $Parameters = '')
        "AuditIfNotExists -Type '$Extension' $Parameters { Require 'r' { $Statements } }"
    }
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Extension = 'Microsoft.Compute/virtualMachines/extensions'

    function Format-AinePolicy {
        # A Windows VM policy with the given AuditIfNotExists block.
        param(
            [string] $Effect = "AuditIfNotExists -Type '$Extension' { Require 'Antimalware' { Field publisher | Must -Be 'Microsoft.Azure.Security' } }",
            [string] $Body = "When { Field storageProfile.osDisk.osType | Must -Be 'Windows' }",
            [string] $Extra = '',
            [string] $Type = 'Microsoft.Compute/virtualMachines',
            [string] $Properties = "DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Compute'; Version = '1.0.0'"
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

    function Invoke-AineCompile {
        param([string] $Effect, [string] $Body, [string] $Extra, [string] $Type, [string] $Properties, [switch] $AllowUnknownAlias)
        $arguments = @{}
        foreach ($name in 'Effect', 'Body', 'Extra', 'Type', 'Properties') {
            if ($PSBoundParameters.ContainsKey($name)) {
                $arguments[$name] = $PSBoundParameters[$name]
            }
        }
        Invoke-BylawTestCompile -Script (Format-AinePolicy @arguments) -AllowUnknownAlias:$AllowUnknownAlias
    }

    function Get-AineDetail {
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['then']['details']
    }

    function Get-ExistenceText {
        # The existence condition in the compact notation of Format-BylawTestCondition.
        param([Parameter(Mandatory)] $Result)
        Format-BylawTestCondition -Condition (Get-AineDetail $Result)['existenceCondition']
    }

    function Format-AineBlock {
        # An AuditIfNotExists block with one Require holding the given statements.
        param([string] $Statements, [string] $Parameters = '')
        "AuditIfNotExists -Type '$Extension' $Parameters { Require 'r' { $Statements } }"
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'AuditIfNotExists (ADR-0030)' {
    Context 'emitted rule' {
        It 'emits the effect, the related type and the existence condition, and leaves the if alone' {
            $result = Invoke-AineCompile
            $then = $result.RuleObject['then']
            $then['effect'] | Should -BeExactly 'AuditIfNotExists'
            $details = Get-AineDetail $result
            $details.Keys | Should -Be @('type', 'existenceCondition')
            $details['type'] | Should -BeExactly $Extension
            $details['existenceCondition']['field'] | Should -BeExactly "$Extension/publisher"
            $details['existenceCondition']['equals'] | Should -BeExactly 'Microsoft.Azure.Security'
            Format-BylawTestCondition -Condition $result.RuleObject['if'] | Should -Be 'allOf[equals, equals]'
        }

        It 'emits only the type when there is no block' {
            $details = Get-AineDetail (Invoke-AineCompile -Effect "AuditIfNotExists -Type '$Extension'")
            $details.Keys | Should -Be @('type')
        }

        It 'emits the type in the alias snapshot''s casing' {
            $details = Get-AineDetail (Invoke-AineCompile -Effect "AuditIfNotExists -Type 'microsoft.compute/VIRTUALMACHINES/extensions'")
            $details['type'] | Should -BeExactly $Extension
        }

        It 'emits the details in Learn''s order' {
            $effect = "AuditIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' -Name (Param SettingName) -ResourceGroupName (Arm `"[resourceGroup().name]`") -ExistenceScope subscription -EvaluationDelay AfterProvisioning { Require 'r' { Field workspaceId | Must -Exist } }"
            $details = Get-AineDetail (Invoke-AineCompile -Effect $effect -Extra 'Parameter SettingName -Default setByPolicy')
            $details.Keys | Should -Be @('type', 'name', 'resourceGroupName', 'existenceScope', 'evaluationDelay', 'existenceCondition')
            $details['type'] | Should -BeExactly 'microsoft.insights/diagnosticSettings'
            $details['name'] | Should -BeExactly "[parameters('settingName')]"
            $details['resourceGroupName'] | Should -BeExactly '[resourceGroup().name]'
            $details['existenceScope'] | Should -BeExactly 'Subscription'
            $details['evaluationDelay'] | Should -BeExactly 'AfterProvisioning'
        }

        It 'accepts -EvaluationDelay <Written> as <Emitted>' -ForEach @(
            @{ Written = 'afterprovisioningsuccess'; Emitted = 'AfterProvisioningSuccess' }
            @{ Written = 'AfterProvisioningFailure'; Emitted = 'AfterProvisioningFailure' }
            @{ Written = 'pt30m'; Emitted = 'PT30M' }
            @{ Written = 'PT0M'; Emitted = 'PT0M' }
            @{ Written = 'PT6H'; Emitted = 'PT6H' }
            @{ Written = 'PT1H30M'; Emitted = 'PT1H30M' }
        ) {
            $details = Get-AineDetail (Invoke-AineCompile -Effect "AuditIfNotExists -Type '$Extension' -EvaluationDelay $Written")
            $details['evaluationDelay'] | Should -BeExactly $Emitted
        }

        It 'resolves short field names against -Type' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Field 'Microsoft.Compute/virtualMachines/extensions/type' | Must -Be 'IaaSAntimalware'; Field typeHandlerVersion | Must -BeLike '1.*'")
            $text = $result.RuleJson
            $text | Should -BeLike "*`"field`": `"$Extension/type`"*"
            $text | Should -BeLike "*`"field`": `"$Extension/typeHandlerVersion`"*"
        }

        It 'reports a field that the related type doesn''t have, with suggestions from it' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Field osDisk | Must -Exist")
            $result.Errors | Should -Contain 'BYL2001'
            Get-Message $result 'BYL2001' | Should -BeLike "*of '$Extension'*"
        }

        It 'emits reserved fields as the related resource''s own' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Field name | Must -BeLike 'IaaS*'")
            (Get-AineDetail $result)['existenceCondition']['field'] | Should -BeExactly 'name'
        }

        It 'combines several Require blocks and statements with AND' {
            $effect = "AuditIfNotExists -Type '$Extension' { Require 'a' { Field publisher | Must -Be 'p'; Field typeHandlerVersion | Must -Be 'v' }; Require 'b' { Field provisioningState | Must -Be 'Succeeded' } }"
            Get-ExistenceText (Invoke-AineCompile -Effect $effect) | Should -Be 'allOf[equals, equals, equals]'
        }

        It 'keeps Require in Resource, inverted, alongside the existence condition' {
            $body = "Require 'Licensed' { Field licenseType | Must -Be 'Windows_Server' }"
            $result = Invoke-AineCompile -Body $body
            $result.RuleObject['if']['allOf'][1]['notEquals'] | Should -BeExactly 'Windows_Server'
            (Get-AineDetail $result)['existenceCondition']['equals'] | Should -BeExactly 'Microsoft.Azure.Security'
        }

        It 'does not warn that there is no Require block in Resource' {
            (Invoke-AineCompile).Codes | Should -Not -Contain 'BYL3041'
        }

        It 'emits an effect parameter from -Effect' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Field publisher | Must -Be 'p'" -Parameters '-Effect (Param Effect)') -Extra 'Parameter Effect -AllowedValues AuditIfNotExists, Disabled -Default AuditIfNotExists'
            $result.Errors | Should -BeNullOrEmpty
            $result.RuleObject['then']['effect'] | Should -BeExactly "[parameters('effect')]"
        }

        It 'generates an EPAC effect parameter that allows AuditIfNotExists and Disabled' {
            $result = Invoke-AineCompile
            $result.Emitted.Diagnostics | Should -BeNullOrEmpty
            $parameter = (ConvertFrom-Json -InputObject $result.Emitted.Text -AsHashtable).properties.parameters.effect
            $parameter['allowedValues'] | Should -BeExactly @('AuditIfNotExists', 'Disabled')
            $parameter['defaultValue'] | Should -BeExactly 'AuditIfNotExists'
        }

        It 'conforms to the EPAC schema' {
            $result = Invoke-AineCompile
            Test-Json -Json $result.Emitted.Text -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json') | Should -BeTrue
        }

        It 'counts parameters used in the existence condition, -Name and -ResourceGroupName as used' {
            $effect = "AuditIfNotExists -Type '$Extension' -Name (Param ExtensionName) -ResourceGroupName (Arm `"[parameters('rg')]`") { Require 'r' { Field publisher | Must -Be (Param Publisher) } }"
            $extra = 'Parameter ExtensionName -Default x; Parameter Rg -Default y; Parameter Publisher -Default z'
            $result = Invoke-AineCompile -Effect $effect -Extra $extra
            $result.Errors | Should -BeNullOrEmpty
            $result.Codes | Should -Not -Contain 'BYL3029'
        }
    }

    Context 'existence condition: compliant form and missing fields (ADR-0004)' {
        # The condition is emitted as written. A missing field doesn't satisfy a requirement unless
        # -IfPresent is used: guards are added where the operator alone would give the wrong result.
        It 'compiles <Statement> to <Expected>' -ForEach @(
            @{ Statement = "Field publisher | Must -Be 'p'"; Expected = 'equals' }
            @{ Statement = "Field publisher | Must -Not -Be 'p'"; Expected = 'allOf[exists:true, notEquals]' }
            @{ Statement = "Field publisher | Must -BeIn 'a', 'b'"; Expected = 'in' }
            @{ Statement = "Field publisher | Must -Not -BeIn 'a', 'b'"; Expected = 'allOf[exists:true, notIn]' }
            @{ Statement = "Field publisher | Must -BeLike 'Micro*'"; Expected = 'like' }
            @{ Statement = "Field publisher | Must -Not -BeLike 'Micro*'"; Expected = 'allOf[exists:true, notLike]' }
            @{ Statement = 'Field publisher | Must -Exist'; Expected = 'exists:true' }
            @{ Statement = 'Field publisher | Must -Not -Exist'; Expected = 'exists:false' }
            @{ Statement = "Field publisher | Must -Be 'p' -IfPresent"; Expected = 'anyOf[exists:false, equals]' }
            @{ Statement = "Field publisher | Must -Not -Be 'p' -IfPresent"; Expected = 'notEquals' }
            @{ Statement = "Field publisher | Must -BeIn 'a', 'b' -IfPresent"; Expected = 'anyOf[exists:false, in]' }
        ) {
            Get-ExistenceText (Invoke-AineCompile -Effect (Format-AineBlock -Statements $Statement)) | Should -Be $Expected
        }

        It 'keeps AnyOf and AllOf as written' {
            $statements = "AnyOf { Field publisher | Must -Be 'a'; AllOf { Field publisher | Must -Be 'b'; Field typeHandlerVersion | Must -Not -Be '1.0' } }"
            Get-ExistenceText (Invoke-AineCompile -Effect (Format-AineBlock -Statements $statements)) | Should -Be 'anyOf[equals, allOf[equals, exists:true, notEquals]]'
        }

        It 'compiles Each to count(where: violation) equals 0, with lenient element fields' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Each provisionAfterExtensions[*] { Element | Must -Not -Be 'bad' }")
            $condition = (Get-AineDetail $result)['existenceCondition']
            $condition['count']['field'] | Should -BeExactly "$Extension/provisionAfterExtensions[*]"
            $condition['count']['where']['equals'] | Should -BeExactly 'bad'
            $condition.Keys | Should -Be @('count', 'equals')
            $condition['equals'] | Should -Be 0
        }

        It 'does not guard a value condition' {
            Get-ExistenceText (Invoke-AineCompile -Effect (Format-AineBlock -Statements "Arm `"[field('name')]`" | Must -Not -Be 'x'")) | Should -Be 'notEquals'
        }
    }

    Context 'front-end errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1038'; Case = 'no -Type'; Effect = "AuditIfNotExists { Require 'r' { Field publisher | Must -Exist } }" }
            @{ Code = 'BYL1038'; Case = 'a -Type that is not a resource type'; Effect = 'AuditIfNotExists -Type extensions' }
            @{ Code = 'BYL1039'; Case = 'a -Name that is a number'; Effect = "AuditIfNotExists -Type '$Extension' -Name 5" }
            @{ Code = 'BYL1039'; Case = 'an empty -ResourceGroupName'; Effect = "AuditIfNotExists -Type '$Extension' -ResourceGroupName ''" }
            @{ Code = 'BYL1040'; Case = 'an invalid -ExistenceScope'; Effect = "AuditIfNotExists -Type '$Extension' -ExistenceScope Tenant" }
            @{ Code = 'BYL1041'; Case = 'a delay over 360 minutes'; Effect = "AuditIfNotExists -Type '$Extension' -EvaluationDelay PT361M" }
            @{ Code = 'BYL1041'; Case = 'a delay of 7 hours'; Effect = "AuditIfNotExists -Type '$Extension' -EvaluationDelay PT7H" }
            @{ Code = 'BYL1041'; Case = 'a delay that is not a duration'; Effect = "AuditIfNotExists -Type '$Extension' -EvaluationDelay 30m" }
            @{ Code = 'BYL1041'; Case = 'an empty duration'; Effect = "AuditIfNotExists -Type '$Extension' -EvaluationDelay PT" }
            @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Effect = "AuditIfNotExists -Type '$Extension' -Effect Disabled" }
            @{ Code = 'BYL1026'; Case = 'AuditIfNotExists and Effect'; Effect = "Effect Audit; AuditIfNotExists -Type '$Extension'" }
            @{ Code = 'BYL1004'; Case = 'two AuditIfNotExists'; Effect = "AuditIfNotExists -Type '$Extension'; AuditIfNotExists -Type '$Extension'" }
            @{ Code = 'BYL1002'; Case = 'When in AuditIfNotExists'; Effect = "AuditIfNotExists -Type '$Extension' { When { Field publisher | Must -Exist } }" }
            @{ Code = 'BYL1002'; Case = 'Field directly in AuditIfNotExists'; Effect = "AuditIfNotExists -Type '$Extension' { Field publisher | Must -Exist }" }
            @{ Code = 'BYL1002'; Case = 'AuditIfNotExists inside Resource'; Effect = 'Effect Audit'; Body = "AuditIfNotExists -Type '$Extension'" }
            @{ Code = 'BYL1010'; Case = '-Strict outside Each'; Effect = (Format-AineBlock -Statements "Field publisher | Must -Be 'p' -Strict") }
        ) {
            $arguments = @{ Effect = $Effect }
            if ($_.ContainsKey('Body')) {
                $arguments.Body = $_.Body
            }
            $result = Invoke-BylawTestScript -Script (Format-AinePolicy @arguments)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'explains -Type when it is missing' {
            $result = Invoke-BylawTestScript -Script (Format-AinePolicy -Effect 'AuditIfNotExists')
            Get-Message $result 'BYL1038' | Should -BeLike "AuditIfNotExists needs -Type: the type of the related resource*"
        }
    }

    Context 'validation' {
        It 'reports BYL2003 for a related type that is not in the snapshot' {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/widgets'"
            Get-Message $result 'BYL2003' | Should -BeLike "Related resource type 'Microsoft.Compute/virtualMachines/widgets' is not in the alias snapshot*"
        }

        It 'reports BYL3090 when -Type is the Resource type and -Name is <Case>' -ForEach @(
            @{ Case = 'missing'; Parameters = '' }
            @{ Case = 'a literal'; Parameters = "-Name 'vm1'" }
            @{ Case = 'another expression'; Parameters = "-Name (Arm `"[field('id')]`")" }
        ) {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines' $Parameters"
            Get-Message $result 'BYL3090' | Should -BeLike "*-Name must be the resource's own name*"
        }

        It 'accepts -Name <Name> for the Resource type, warning (BYL3091) that Audit fits better' -ForEach @(
            @{ Name = "[field('name')]" }, @{ Name = "[field('fullName')]" }, @{ Name = "[FIELD('Name')]" }
        ) {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines' -Name (Arm `"$Name`")"
            $result.Errors | Should -BeNullOrEmpty
            ($result.Diagnostics | Where-Object Code -EQ 'BYL3091').Severity.ToString() | Should -Be 'Warning'
        }

        It 'warns (BYL3092) that -<Parameter> has no effect on a child type' -ForEach @(
            @{ Parameter = 'ResourceGroupName'; Value = "'rg'" }
            @{ Parameter = 'ExistenceScope'; Value = 'Subscription' }
        ) {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type '$Extension' -$Parameter $Value"
            $result.Errors | Should -BeNullOrEmpty
            Get-Message $result 'BYL3092' | Should -BeLike "-$Parameter has no effect*is a child of 'Microsoft.Compute/virtualMachines'*"
        }

        It 'does not warn about -ExistenceScope for a type that is not a child' {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' -ExistenceScope Subscription"
            $result.Codes | Should -Not -Contain 'BYL3092'
        }

        It 'reports an undeclared parameter in <Where>' -ForEach @(
            @{ Where = '-Name'; Effect = "AuditIfNotExists -Type '$Extension' -Name (Param Missing)" }
            @{ Where = 'the existence condition'; Effect = (Format-AineBlock -Statements 'Field publisher | Must -Be (Param Missing)') }
        ) {
            $result = Invoke-AineCompile -Effect $Effect
            $result.Errors | Should -Contain 'BYL3020'
        }

        It 'checks operator values in the existence condition' {
            $result = Invoke-AineCompile -Effect (Format-AineBlock -Statements "Field publisher | Must -BeLike '*a*'")
            $result.Errors | Should -Contain 'BYL3011'
        }

        It 'reports BYL3072 for an effect parameter that allows <Value>' -ForEach @(
            @{ Value = 'Audit' }, @{ Value = 'DeployIfNotExists' }
        ) {
            $result = Invoke-AineCompile -Effect "AuditIfNotExists -Type '$Extension' -Effect (Param Effect)" -Extra "Parameter Effect -AllowedValues AuditIfNotExists, $Value -Default AuditIfNotExists"
            Get-Message $result 'BYL3072' | Should -Be "Effect parameter 'Effect' of an AuditIfNotExists policy allows '$Value'. Allowed values: AuditIfNotExists, Disabled."
        }

        It 'points Effect AuditIfNotExists to the keyword' {
            $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Effect 'AuditIfNotExists')
            Get-Message $result 'BYL3030' | Should -BeLike '*AuditIfNotExists has its own block*'
        }
    }
}
