BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:TagContributor = '/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
    $script:Contributor = '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'

    function Format-ModifyPolicy {
        # A policy that requires the Environment tag, with the given Modify block.
        param(
            [string] $Modify = "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }",
            [string] $Requirements = "Require 'Environment is Production' { Tag Environment | Must -Be 'Production' }",
            [string] $Extra = '',
            [string] $Type = 'Microsoft.Storage/storageAccounts',
            [string] $Properties = "DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Tags'; Version = '1.0.0'"
        )
        @"
Policy 'test-policy' {
    Properties @{ $Properties }
    $Extra
    Resource '$Type' {
        $Requirements
    }
    $Modify
}
"@
    }

    function Invoke-ModifyCompile {
        param([string] $Modify, [string] $Requirements, [string] $Extra, [string] $Type, [string] $Properties)
        $arguments = @{}
        foreach ($name in 'Modify', 'Requirements', 'Extra', 'Type', 'Properties') {
            if ($PSBoundParameters.ContainsKey($name)) {
                $arguments[$name] = $PSBoundParameters[$name]
            }
        }
        Invoke-BylawTestCompile -Script (Format-ModifyPolicy @arguments)
    }

    function Get-ModifyDetail {
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['then']['details']
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Modify (ADR-0024)' {
    Context 'emitted rule' {
        It 'emits the effect, the role and the operation' {
            $result = Invoke-ModifyCompile
            $result.RuleObject['then']['effect'] | Should -BeExactly 'Modify'
            $details = Get-ModifyDetail $result
            @($details.Keys) | Should -Be @('roleDefinitionIds', 'operations')
            @($details['roleDefinitionIds']) | Should -Be @($TagContributor)
            $operation = @($details['operations'])[0]
            @($operation.Keys) | Should -Be @('operation', 'field', 'value')
            $operation['operation'] | Should -BeExactly 'addOrReplace'
            $operation['field'] | Should -Be "tags['Environment']"
            $operation['value'] | Should -Be 'Production'
        }

        It 'emits <Keyword> as <Operation>' -ForEach @(
            @{ Keyword = "AddOrReplace 'x'"; Operation = 'addOrReplace'; HasValue = $true }
            @{ Keyword = "Add 'x'"; Operation = 'add'; HasValue = $true }
            @{ Keyword = 'Remove'; Operation = 'remove'; HasValue = $false }
        ) {
            $result = Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributor' { Tag Environment | $Keyword }" -Requirements "Require 'r' { Tag Environment | Must -Be 'x' }"
            # Not $operation: variable names ignore case, so it would overwrite $Operation.
            $emitted = @((Get-ModifyDetail $result)['operations'])[0]
            $emitted['operation'] | Should -BeExactly $Operation
            $emitted.Contains('value') | Should -Be $HasValue
        }

        It 'emits operations in the order written' {
            $modify = "Modify -Role 'Tag Contributor' { Tag B | Add 'b'; Tag A | AddOrReplace 'a'; Tag C | Remove }"
            $requirements = "Require 'r' { Tag A | Must -Be 'a'; Tag B | Must -Be 'b'; Tag C | Must -Not -Exist }"
            $operations = @((Get-ModifyDetail (Invoke-ModifyCompile -Modify $modify -Requirements $requirements))['operations'])
            @($operations | ForEach-Object { $_['field'] }) | Should -Be @("tags['B']", "tags['A']", "tags['C']")
        }

        It 'emits a <Kind> value' -ForEach @(
            @{ Kind = 'Param'; Value = '(Param TagValue)'; Extra = 'Parameter TagValue -Type String'; Expected = "[parameters('tagValue')]" }
            @{ Kind = 'Arm'; Value = "(Arm `"[concat('a', 'b')]`")"; Extra = ''; Expected = "[concat('a', 'b')]" }
            @{ Kind = 'ResourceGroupTag'; Value = '(ResourceGroupTag Environment)'; Extra = ''; Expected = "[resourceGroup().tags['Environment']]" }
            @{ Kind = 'boolean'; Value = '$true'; Extra = ''; Expected = $true }
        ) {
            $result = Invoke-ModifyCompile -Extra $Extra -Modify "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace $Value }"
            @((Get-ModifyDetail $result)['operations'])[0]['value'] | Should -Be $Expected
        }

        It 'emits a tag name parameter in the form built-in tag policies use' {
            $result = Invoke-ModifyCompile -Extra 'Parameter TagName -Type String' -Requirements "Require 'r' { Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName)) }" -Modify "Modify -Role 'Tag Contributor' { Tag (Param TagName) | AddOrReplace (ResourceGroupTag (Param TagName)) }"
            $operation = @((Get-ModifyDetail $result)['operations'])[0]
            $operation['field'] | Should -Be "[concat('tags[', parameters('tagName'), ']')]"
            $operation['value'] | Should -Be "[resourceGroup().tags[parameters('tagName')]]"
        }

        It 'emits -Condition after the value' {
            $result = Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' -Condition (Arm `"[greaterOrEquals(requestContext().apiVersion, '2019-04-01')]`") }"
            $operation = @((Get-ModifyDetail $result)['operations'])[0]
            @($operation.Keys) | Should -Be @('operation', 'field', 'value', 'condition')
            $operation['condition'] | Should -Be "[greaterOrEquals(requestContext().apiVersion, '2019-04-01')]"
        }

        It 'emits -ConflictEffect <Written> as <Emitted>, before the operations' -ForEach @(
            @{ Written = 'Audit'; Emitted = 'audit' }
            @{ Written = 'deny'; Emitted = 'deny' }
            @{ Written = 'DISABLED'; Emitted = 'disabled' }
        ) {
            $details = Get-ModifyDetail (Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributor' -ConflictEffect $Written { Tag Environment | AddOrReplace 'Production' }")
            @($details.Keys) | Should -Be @('roleDefinitionIds', 'conflictEffect', 'operations')
            $details['conflictEffect'] | Should -BeExactly $Emitted
        }

        It 'resolves a role given as <Form>' -ForEach @(
            @{ Form = 'a built-in name in any case'; Role = "'tag contributor'" }
            @{ Form = 'a GUID'; Role = "'4a9ae827-6dc8-4573-8ac7-8239d42aa03f'" }
            @{ Form = 'a full role definition ID'; Role = "'/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f'" }
        ) {
            $details = Get-ModifyDetail (Invoke-ModifyCompile -Modify "Modify -Role $Role { Tag Environment | AddOrReplace 'Production' }")
            @($details['roleDefinitionIds']) | Should -Be @($TagContributor)
        }

        It 'emits several roles in the order written' {
            $details = Get-ModifyDetail (Invoke-ModifyCompile -Modify "Modify -Role Contributor, 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }")
            @($details['roleDefinitionIds']) | Should -Be @($Contributor, $TagContributor)
        }

        It 'generates an effect parameter that allows Modify and Disabled' {
            $result = Invoke-ModifyCompile
            $result.Emitted.Diagnostics | Should -BeNullOrEmpty
            $document = $result.Emitted.Text | ConvertFrom-Json -AsHashtable
            $effect = $document['properties']['parameters']['effect']
            @($effect['allowedValues']) | Should -Be @('Modify', 'Disabled')
            $effect['defaultValue'] | Should -Be 'Modify'
            $document['properties']['policyRule']['then']['effect'] | Should -Be "[parameters('effect')]"
        }

        It 'uses a declared effect parameter with -Effect (Param Effect)' {
            $result = Invoke-ModifyCompile -Extra 'Parameter Effect -AllowedValues Modify, Disabled -Default Disabled' -Modify "Modify -Role 'Tag Contributor' -Effect (Param Effect) { Tag Environment | AddOrReplace 'Production' }"
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $result.Codes | Should -Not -Contain 'BYL3029'
            $result.RuleObject['then']['effect'] | Should -Be "[parameters('effect')]"
            ($result.Emitted.Text | ConvertFrom-Json -AsHashtable)['properties']['parameters']['effect']['defaultValue'] | Should -Be 'Disabled'
        }

        It 'allows Audit in a declared effect parameter, but generates only Modify and Disabled' {
            $declared = Invoke-ModifyCompile -Extra 'Parameter Effect -AllowedValues Modify, Audit, Disabled -Default Audit' -Modify "Modify -Role 'Tag Contributor' -Effect (Param Effect) { Tag Environment | AddOrReplace 'Production' }"
            $declared.Errors | Should -BeNullOrEmpty -Because ($declared.Diagnostics -join '; ')
            @(($declared.Emitted.Text | ConvertFrom-Json -AsHashtable)['properties']['parameters']['effect']['allowedValues']) | Should -Be @('Modify', 'Audit', 'Disabled')
            $generated = Invoke-ModifyCompile
            @(($generated.Emitted.Text | ConvertFrom-Json -AsHashtable)['properties']['parameters']['effect']['allowedValues']) | Should -Be @('Modify', 'Disabled')
        }

        It 'counts parameters used only in operations as used' {
            $result = Invoke-ModifyCompile -Extra 'Parameter TagValue -Type String; Parameter Version -Type String' -Requirements "Require 'r' { Tag Environment | Must -Be (Param TagValue) }" -Modify "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace (Param TagValue) -Condition (Arm `"[equals(parameters('version'), '2')]`") }"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'produces a file that is valid against the EPAC schema' {
            $result = Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributor' -ConflictEffect Audit { Tag Environment | AddOrReplace 'Production' }"
            Test-Json -Json $result.Emitted.Text -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json') | Should -BeTrue
        }
    }

    Context 'front-end errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1026'; Case = 'Effect then Modify'; Modify = "Effect Deny; Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }" }
            @{ Code = 'BYL1026'; Case = 'Modify then Effect'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'Production' }; Effect Deny" }
            @{ Code = 'BYL1004'; Case = 'two Modify blocks'; Modify = "Modify -Role 'Tag Contributor' { Tag A | AddOrReplace 'a' }; Modify -Role 'Tag Contributor' { Tag B | AddOrReplace 'b' }" }
            @{ Code = 'BYL1013'; Case = 'an empty block'; Modify = "Modify -Role 'Tag Contributor' { }" }
            @{ Code = 'BYL1013'; Case = 'no block'; Modify = "Modify -Role 'Tag Contributor'" }
            @{ Code = 'BYL1027'; Case = 'AddOrReplace without a value'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace }" }
            @{ Code = 'BYL1027'; Case = 'Add without a value'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | Add }" }
            @{ Code = 'BYL1027'; Case = 'Remove with a value'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | Remove 'x' }" }
            @{ Code = 'BYL1028'; Case = 'a -Condition that is not Arm'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'x' -Condition '[true()]' }" }
            @{ Code = 'BYL1029'; Case = 'an invalid -ConflictEffect'; Modify = "Modify -Role 'Tag Contributor' -ConflictEffect Modify { Tag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Modify = "Modify -Role 'Tag Contributor' -Effect Disabled { Tag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1031'; Case = 'an operation with no field'; Modify = "Modify -Role 'Tag Contributor' { AddOrReplace 'x' }" }
            @{ Code = 'BYL1031'; Case = 'a value piped to an operation'; Modify = "Modify -Role 'Tag Contributor' { ResourceGroupTag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1032'; Case = 'no -Role'; Modify = "Modify { Tag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1032'; Case = 'an empty -Role'; Modify = "Modify -Role @() { Tag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1002'; Case = 'Element in Modify'; Modify = "Modify -Role 'Tag Contributor' { Element | AddOrReplace 'x' }" }
            @{ Code = 'BYL1002'; Case = 'Must in Modify'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment | Must -Exist }" }
            @{ Code = 'BYL1002'; Case = 'Modify inside Resource'; Modify = '' ; Requirements = "Require 'r' { Tag Environment | Must -Exist }; Modify -Role 'Tag Contributor' { Tag Environment | AddOrReplace 'x' }" }
            @{ Code = 'BYL1007'; Case = 'a field not piped to an operation'; Modify = "Modify -Role 'Tag Contributor' { Tag Environment; Tag Other | AddOrReplace 'x' }" }
        ) {
            # Read the case's own data: a bare $Requirements would find a variable of that name in
            # the caller, such as the build script's.
            $arguments = @{ Modify = $Modify }
            if ($_.ContainsKey('Requirements')) {
                $arguments.Requirements = $_.Requirements
            }
            $result = Invoke-BylawTestScript -Script (Format-ModifyPolicy @arguments)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'reports an operation outside Modify' {
            $result = Invoke-BylawTestScript -Script (Format-ModifyPolicy -Requirements "Require 'r' { Tag Environment | AddOrReplace 'x' }")
            $result.Codes | Should -Contain 'BYL1002'
        }

        It 'reports no effect when there is neither Effect nor Modify' {
            $result = Invoke-BylawTestScript -Script (Format-ModifyPolicy -Modify '')
            $result.Codes | Should -Contain 'BYL1006'
            ($result.Diagnostics | Where-Object Code -EQ 'BYL1006').Message | Should -BeLike '*Modify or Append block*'
        }

        It 'says a field in Modify is not piped to an operation, not to Must' {
            $result = Invoke-BylawTestScript -Script (Format-ModifyPolicy -Modify "Modify -Role 'Tag Contributor' { Tag Environment; Tag Other | AddOrReplace 'x' }")
            ($result.Diagnostics | Where-Object Code -EQ 'BYL1007').Message | Should -BeLike '*not piped to an operation*'
        }

        It 'does not report an empty block when its operations had errors' {
            $result = Invoke-BylawTestScript -Script (Format-ModifyPolicy -Modify "Modify -Role 'Tag Contributor' { Tag Environment | Add }")
            $result.Codes | Should -Not -Contain 'BYL1013'
        }
    }

    Context 'validation errors' {
        It 'reports an unknown role, with the closest name' {
            $result = Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributer' { Tag Environment | AddOrReplace 'x' }"
            $result.Errors | Should -Contain 'BYL3060'
            Get-Message $result 'BYL3060' | Should -BeLike "*Did you mean 'Tag Contributor'*"
        }

        It 'reports a role given twice in different forms' {
            $result = Invoke-ModifyCompile -Modify "Modify -Role 'Tag Contributor', '4A9AE827-6DC8-4573-8AC7-8239D42AA03F' { Tag Environment | AddOrReplace 'x' }"
            $result.Errors | Should -Contain 'BYL3061'
        }

        It 'reports <Value> in the effect parameter' -ForEach @(
            @{ Value = 'Deny'; Reason = '*never denies*' }
            @{ Value = 'Append'; Reason = '*Allowed values: Modify, Audit, Disabled*' }
        ) {
            $result = Invoke-ModifyCompile -Extra "Parameter Effect -AllowedValues Modify, $Value -Default Modify" -Modify "Modify -Role 'Tag Contributor' -Effect (Param Effect) { Tag Environment | AddOrReplace 'x' }"
            $result.Errors | Should -Contain 'BYL3062'
            Get-Message $result 'BYL3062' | Should -BeLike $Reason
        }

        It 'reports Modify in the effect parameter of a policy with Effect' {
            $script = Format-BylawTestPolicy -Extra 'Parameter Effect -AllowedValues Modify, Disabled -Default Disabled' -Effect '(Param Effect)'
            $result = Invoke-BylawTestCompile -Script $script
            $result.Errors | Should -Contain 'BYL3033'
            Get-Message $result 'BYL3033' | Should -BeLike '*Modify has its own block*'
        }

        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL3063'; Case = 'Remove on an alias'; Requirements = "Require 'r' { Field minimumTlsVersion | Must -Be 'TLS1_2' }"; Operation = 'Field minimumTlsVersion | Remove' }
            @{ Code = 'BYL3064'; Case = 'an alias that is not Modifiable'; Requirements = "Require 'r' { Field accessTier | Must -Be 'Hot' }"; Operation = "Field accessTier | AddOrReplace 'Hot'" }
            @{ Code = 'BYL3064'; Case = 'a reserved field'; Requirements = "Require 'r' { Field location | Must -Be 'uksouth' }"; Operation = "Field location | AddOrReplace 'uksouth'" }
            @{ Code = 'BYL3065'; Case = 'identity.type on a storage account'; Requirements = "Require 'r' { Field identity.type | Must -Be 'SystemAssigned' }"; Operation = "Field identity.type | AddOrReplace 'SystemAssigned'" }
            @{ Code = 'BYL3066'; Case = 'an array element'; Requirements = "Require 'r' { Field minimumTlsVersion | Must -Be 'TLS1_2' }"; Operation = "Field 'networkAcls.ipRules[*].value' | AddOrReplace '10.0.0.0/8'" }
            @{ Code = 'BYL3067'; Case = 'the same field twice'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = "Tag Environment | Add 'x'; Field `"tags['environment']`" | AddOrReplace 'x'" }
            @{ Code = 'BYL3068'; Case = 'a condition that uses field()'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = "Tag Environment | AddOrReplace 'x' -Condition (Arm `"[equals(field('location'), 'uksouth')]`")" }
            @{ Code = 'BYL3068'; Case = 'a condition that uses resourceGroup()'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = "Tag Environment | AddOrReplace 'x' -Condition (Arm `"[empty(resourceGroup().tags)]`")" }
            @{ Code = 'BYL3020'; Case = 'an undeclared value parameter'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = 'Tag Environment | AddOrReplace (Param Missing)' }
            @{ Code = 'BYL3020'; Case = 'an undeclared tag name parameter'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = "Tag (Param Missing) | AddOrReplace 'x'" }
            @{ Code = 'BYL2001'; Case = 'an unknown alias'; Requirements = "Require 'r' { Tag Environment | Must -Be 'x' }"; Operation = "Field minimumTlsVersoin | AddOrReplace 'x'" }
        ) {
            $result = Invoke-ModifyCompile -Requirements $Requirements -Modify "Modify -Role 'Storage Account Contributor' -ConflictEffect Audit { $Operation }"
            $result.Errors | Should -Contain $Code
        }

        It 'reports a tag name parameter that is not a String' {
            $result = Invoke-ModifyCompile -Extra 'Parameter TagName -Type Integer' -Modify "Modify -Role 'Tag Contributor' { Tag (Param TagName) | AddOrReplace 'x' }"
            $result.Errors | Should -Contain 'BYL3034'
        }

        It 'allows identity.type on a virtual machine' {
            $result = Invoke-ModifyCompile -Type 'Microsoft.Compute/virtualMachines' -Requirements "Require 'r' { Field identity.type | Must -Be 'SystemAssigned' }" -Modify "Modify -Role 'Virtual Machine Contributor' { Field identity.type | AddOrReplace 'SystemAssigned' }"
            $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
            $result.Codes | Should -Not -Contain 'BYL3071'
        }

        It 'allows a Modifiable alias' {
            $result = Invoke-ModifyCompile -Requirements "Require 'r' { Field minimumTlsVersion | Must -Be 'TLS1_2' }" -Modify "Modify -Role 'Storage Account Contributor' -ConflictEffect Audit { Field minimumTlsVersion | AddOrReplace 'TLS1_2' }"
            $result.Diagnostics | Should -BeNullOrEmpty
            @((Get-ModifyDetail $result)['operations'])[0]['field'] | Should -Be 'Microsoft.Storage/storageAccounts/minimumTlsVersion'
        }
    }

    Context 'warnings' {
        It 'warns about a tag operation when Mode is All' {
            $result = Invoke-ModifyCompile -Properties "DisplayName = 'Test policy'; Mode = 'All'"
            $result.Errors | Should -BeNullOrEmpty
            $result.Codes | Should -Contain 'BYL3069'
        }

        It 'does not warn about Mode All for a resource group' {
            $result = Invoke-ModifyCompile -Properties "DisplayName = 'Test policy'; Mode = 'All'" -Type 'Microsoft.Resources/subscriptions/resourceGroups' -Requirements "Require 'r' { Tag Environment | Must -Be 'Production' }"
            $result.Codes | Should -Not -Contain 'BYL3069'
        }

        It 'warns about an operation on a field no Require checks' {
            $result = Invoke-ModifyCompile -Requirements "Require 'r' { Tag Owner | Must -Exist }"
            $result.Errors | Should -BeNullOrEmpty
            $result.Codes | Should -Contain 'BYL3070'
            # Contains, not -BeLike: [...] is a wildcard character class.
            (Get-Message $result 'BYL3070').Contains("tags['Environment']") | Should -BeTrue
        }

        It 'does not warn when a Require inside a group or Each checks the field' {
            $result = Invoke-ModifyCompile -Requirements "Require 'r' { AnyOf { Tag Environment | Must -Be 'Production'; Tag Environment | Must -Be 'Prod' } }"
            $result.Codes | Should -Not -Contain 'BYL3070'
        }

        It 'does not count a When condition as checking the field' {
            $result = Invoke-ModifyCompile -Requirements "When { Tag Environment | Must -Exist }; Require 'r' { Tag Owner | Must -Exist }"
            $result.Codes | Should -Contain 'BYL3070'
        }

        It 'warns about an alias operation <Case>' -ForEach @(
            @{ Case = 'without -ConflictEffect'; Option = '' }
            @{ Case = 'with -ConflictEffect Deny'; Option = '-ConflictEffect Deny' }
        ) {
            $result = Invoke-ModifyCompile -Requirements "Require 'r' { Field minimumTlsVersion | Must -Be 'TLS1_2' }" -Modify "Modify -Role 'Storage Account Contributor' $Option { Field minimumTlsVersion | AddOrReplace 'TLS1_2' }"
            $result.Errors | Should -BeNullOrEmpty
            $result.Codes | Should -Contain 'BYL3071'
        }

        It 'does not warn about the conflict effect of tag operations' {
            (Invoke-ModifyCompile).Codes | Should -Not -Contain 'BYL3071'
        }
    }
}
