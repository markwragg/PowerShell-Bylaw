BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Get-ViolationText {
        # Compiles one Must statement in the given context and returns the violation in ADR-0004 notation.
        param(
            [Parameter(Mandatory)] [string] $Must,
            [ValidateSet('Require', 'IfPresent', 'Each', 'EachStrict')] [string] $Context
        )
        $requirements = switch ($Context) {
            'Require' { "Require 'r' { Field minimumTlsVersion | Must $Must }" }
            'IfPresent' { "Require 'r' { Field minimumTlsVersion | Must $Must -IfPresent }" }
            'Each' { "Require 'r' { Each networkAcls.ipRules[*] { Field value | Must $Must } }" }
            'EachStrict' { "Require 'r' { Each networkAcls.ipRules[*] { Field value | Must $Must -Strict } }" }
        }
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        # if = allOf[type, <violation>]. A lenient allOf violation is flattened into the outer allOf,
        # so the violation is everything after the type condition.
        $rest = @($result.RuleObject['if']['allOf'] | Select-Object -Skip 1)
        $violation = if ($rest.Count -eq 1) { $rest[0] } else { [ordered]@{ allOf = $rest } }
        if ($Context -like 'Each*') {
            $violation['count']['field'] | Should -Be 'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]'
            $violation['greater'] | Should -Be 0
            return Format-BylawTestCondition -Condition $violation['count']['where']
        }
        Format-BylawTestCondition -Condition $violation
    }
}

BeforeDiscovery {
    # ADR-0004 truth table: compliant Must -> strict violation, lenient violation.
    $script:truthTable = @(
        @{ Must = "-Be 'x'"; Strict = 'notEquals'; Lenient = 'allOf[exists:true, notEquals]' }
        @{ Must = "-Not -Be 'x'"; Strict = 'anyOf[exists:false, equals]'; Lenient = 'equals' }
        @{ Must = "-BeIn 'x', 'y'"; Strict = 'notIn'; Lenient = 'allOf[exists:true, notIn]' }
        @{ Must = "-Not -BeIn 'x', 'y'"; Strict = 'anyOf[exists:false, in]'; Lenient = 'in' }
        @{ Must = "-BeLike 'x*'"; Strict = 'notLike'; Lenient = 'allOf[exists:true, notLike]' }
        @{ Must = "-Not -BeLike 'x*'"; Strict = 'anyOf[exists:false, like]'; Lenient = 'like' }
        @{ Must = "-Match '##'"; Strict = 'notMatchInsensitively'; Lenient = 'allOf[exists:true, notMatchInsensitively]' }
        @{ Must = "-Not -Match '##'"; Strict = 'anyOf[exists:false, matchInsensitively]'; Lenient = 'matchInsensitively' }
        @{ Must = "-MatchCase '##'"; Strict = 'notMatch'; Lenient = 'allOf[exists:true, notMatch]' }
        @{ Must = "-Not -MatchCase '##'"; Strict = 'anyOf[exists:false, match]'; Lenient = 'match' }
        @{ Must = "-ContainText 'x'"; Strict = 'notContains'; Lenient = 'allOf[exists:true, notContains]' }
        @{ Must = "-Not -ContainText 'x'"; Strict = 'anyOf[exists:false, contains]'; Lenient = 'contains' }
        @{ Must = "-ContainKey 'k'"; Strict = 'notContainsKey'; Lenient = 'allOf[exists:true, notContainsKey]' }
        @{ Must = "-Not -ContainKey 'k'"; Strict = 'anyOf[exists:false, containsKey]'; Lenient = 'containsKey' }
        @{ Must = '-BeGreaterThan 5'; Strict = 'lessOrEquals'; Lenient = 'allOf[exists:true, lessOrEquals]' }
        @{ Must = '-Not -BeGreaterThan 5'; Strict = 'anyOf[exists:false, greater]'; Lenient = 'greater' }
        @{ Must = '-BeGreaterOrEqual 5'; Strict = 'anyOf[exists:false, less]'; Lenient = 'less' }
        @{ Must = '-Not -BeGreaterOrEqual 5'; Strict = 'greaterOrEquals'; Lenient = 'allOf[exists:true, greaterOrEquals]' }
        @{ Must = '-BeLessThan 5'; Strict = 'greaterOrEquals'; Lenient = 'allOf[exists:true, greaterOrEquals]' }
        @{ Must = '-Not -BeLessThan 5'; Strict = 'anyOf[exists:false, less]'; Lenient = 'less' }
        @{ Must = '-BeLessOrEqual 5'; Strict = 'anyOf[exists:false, greater]'; Lenient = 'greater' }
        @{ Must = '-Not -BeLessOrEqual 5'; Strict = 'lessOrEquals'; Lenient = 'allOf[exists:true, lessOrEquals]' }
    )
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Inversion truth table (ADR-0004)' {
    It 'Must <Must> in Require is violated by <Strict>' -ForEach $truthTable {
        Get-ViolationText -Must $Must -Context Require | Should -BeExactly $Strict
    }

    It 'Must <Must> -IfPresent is violated by <Lenient>' -ForEach $truthTable {
        Get-ViolationText -Must $Must -Context IfPresent | Should -BeExactly $Lenient
    }

    It 'Must <Must> inside Each is violated by <Lenient>' -ForEach $truthTable {
        Get-ViolationText -Must $Must -Context Each | Should -BeExactly $Lenient
    }

    It 'Must <Must> -Strict inside Each is violated by <Strict>' -ForEach $truthTable {
        Get-ViolationText -Must $Must -Context EachStrict | Should -BeExactly $Strict
    }

    It 'inverts -Exist without guards in <Context>' -ForEach @(
        @{ Context = 'Require' }, @{ Context = 'Each' }, @{ Context = 'EachStrict' }
    ) {
        Get-ViolationText -Must '-Exist' -Context $Context | Should -BeExactly 'exists:false'
        Get-ViolationText -Must '-Not -Exist' -Context $Context | Should -BeExactly 'exists:true'
    }

    It 'adds no guard for Element' {
        $requirements = "Require 'r' { Each networkAcls.ipRules[*] { Element | Must -Not -Be 'x' } }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty
        $where = $result.RuleObject['if']['allOf'][1]['count']['where']
        $where['field'] | Should -Be 'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]'
        Format-BylawTestCondition -Condition $where | Should -Be 'equals'
    }
}

Describe 'Compiled rule shape (ADR-0002, ADR-0003)' {
    It 'compiles the spec storage example to the expected policyRule' {
        $script = @'
Policy 'storage-deny-public-network-access' {

    Properties @{
        DisplayName = 'Storage accounts should disable public network access'
        Description = 'Denies storage accounts that allow public network access or allow-all IP rules.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'All'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.Storage/storageAccounts' {

        When {
            Field kind | Must -BeIn 'StorageV2', 'BlockBlobStorage'
        }

        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }

        Require 'No allow-all IP rules' {
            Each networkAcls.ipRules[*] {
                Field value | Must -Not -Be '0.0.0.0/0'
            }
        }
    }

    Effect (Param Effect)
}
'@
        # Expected policyRule from docs/SPEC.md, in canonical form.
        $expected = @'
{
  "if": {
    "allOf": [
      { "field": "type", "equals": "Microsoft.Storage/storageAccounts" },
      { "field": "kind", "in": [ "StorageV2", "BlockBlobStorage" ] },
      {
        "anyOf": [
          { "field": "Microsoft.Storage/storageAccounts/publicNetworkAccess", "notEquals": "Disabled" },
          {
            "count": {
              "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]",
              "where": { "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value", "equals": "0.0.0.0/0" }
            },
            "greater": 0
          }
        ]
      }
    ]
  },
  "then": { "effect": "[parameters('effect')]" }
}
'@
        $result = Invoke-BylawTestCompile -Script $script
        $result.Diagnostics | Should -BeNullOrEmpty
        $canonicalExpected = InModuleScope Bylaw -Parameters @{ Json = $expected } {
            param($Json)
            ConvertTo-BylawJson -InputObject (ConvertFrom-BylawJson -Json $Json)
        }
        $result.RuleJson | Should -BeExactly $canonicalExpected
    }

    It 'merges several Require blocks and several Must statements into one anyOf' {
        $requirements = @'
Require 'a' { Field publicNetworkAccess | Must -Be 'Disabled' }
Require 'b' {
    Field minimumTlsVersion | Must -Be 'TLS1_2'
    Field allowBlobPublicAccess | Must -Be $false
}
'@
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty
        $allOf = $result.RuleObject['if']['allOf']
        $allOf.Count | Should -Be 2
        $anyOf = $allOf[1]['anyOf']
        $anyOf.Count | Should -Be 3
        $anyOf.ForEach({ $_['field'] }) | Should -Be @(
            'Microsoft.Storage/storageAccounts/publicNetworkAccess'
            'Microsoft.Storage/storageAccounts/minimumTlsVersion'
            'Microsoft.Storage/storageAccounts/allowBlobPublicAccess'
        )
        $anyOf[2]['notEquals'] | Should -BeFalse
    }

    It 'emits When conditions as written, including -Not' {
        $requirements = "When { Field kind | Must -Not -Be 'FileStorage' }; Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty
        $when = $result.RuleObject['if']['allOf'][1]
        $when['field'] | Should -Be 'kind'
        $when['notEquals'] | Should -Be 'FileStorage'
        $when.Keys.Count | Should -Be 2 -Because 'When is not inverted and gets no missing-field guard'
    }

    It 'omits the type condition for Resource *' {
        $script = "Policy 'any-location' { Properties @{ DisplayName = 'Location' }; Resource * { Require 'r' { Field location | Must -BeIn 'uksouth', 'ukwest' } }; Effect Audit }"
        $result = Invoke-BylawTestCompile -Script $script
        $result.Errors | Should -BeNullOrEmpty
        Format-BylawTestCondition -Condition $result.RuleObject['if'] | Should -Be 'notIn'
        $result.RuleObject['if']['field'] | Should -Be 'location'
    }

    It 'compiles a policy without Require to the type and When conditions' {
        $script = "Policy 'deny-classic' { Properties @{ DisplayName = 'Deny' }; Resource 'Microsoft.Storage/storageAccounts' { When { Field kind | Must -Be 'Storage' } }; Effect Deny }"
        $result = Invoke-BylawTestCompile -Script $script
        $result.Errors | Should -BeNullOrEmpty
        $result.Codes | Should -Contain 'BYL3041'
        Format-BylawTestCondition -Condition $result.RuleObject['if'] | Should -Be 'allOf[equals, equals]'
    }

    It 'emits a literal effect in canonical casing' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy).Replace('Effect Deny', 'Effect audit')
        $result.RuleObject['then']['effect'] | Should -BeExactly 'Audit'
    }

    It 'emits parameter references with the JSON parameter name' {
        $extra = "Parameter AllowedLocations -Type Array; Parameter @{ Name = 'Sku'; Type = 'String'; JsonName = 'skuName' }"
        $requirements = "Require 'r' { Field location | Must -BeIn (Param AllowedLocations); Field 'sku.name' -AllowUnknownAlias | Must -Be (Param Sku) }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Extra $extra -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty
        $anyOf = $result.RuleObject['if']['allOf'][1]['anyOf']
        $anyOf[0]['notIn'] | Should -BeExactly "[parameters('allowedLocations')]"
        $anyOf[1]['notEquals'] | Should -BeExactly "[parameters('skuName')]"
    }

    It 'keeps Arm expressions verbatim' {
        $requirements = "Require 'r' { Field location | Must -Be (Arm '[resourceGroup().location]') }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $requirements)
        $result.RuleObject['if']['allOf'][1]['notEquals'] | Should -BeExactly '[resourceGroup().location]'
    }

    It 'compiles nested Each to nested counts' {
        $requirements = "Require 'r' { Each securityRules[*] { Field access | Must -Be 'Deny'; Each destinationPortRanges[*] { Element | Must -Not -Be '*' } } }"
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Type 'Microsoft.Network/networkSecurityGroups' -Requirements $requirements)
        $result.Errors | Should -BeNullOrEmpty
        $outer = $result.RuleObject['if']['allOf'][1]
        Format-BylawTestCondition -Condition $outer | Should -Be 'count(where: anyOf[allOf[exists:true, notEquals], count(where: equals)])'
        $inner = $outer['count']['where']['anyOf'][1]
        $inner['count']['field'] | Should -Be 'Microsoft.Network/networkSecurityGroups/securityRules[*].destinationPortRanges[*]'
    }

    It 'keeps provenance from compiled conditions to the DSL' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy)
        $violation = $result.Policy.Rule.If.Children[1]
        $violation.Origin.DslOperator | Should -Be 'Be'
        $violation.Location.Keyword | Should -Be 'Must'
    }
}
