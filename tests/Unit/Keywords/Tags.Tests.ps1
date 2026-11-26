BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    function Get-FirstAssertion($Result) {
        $Result.Policies[0].Resource.Requirements[0].Children[0]
    }

    function Invoke-TagCompile {
        # Compiles requirements in an Indexed policy (tags want Indexed, ADR-0016), with extra
        # declarations such as parameters.
        param([Parameter(Mandatory)] [string] $Requirements, [string] $Extra = '', [string] $Type = 'Microsoft.Storage/storageAccounts')
        Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements $Requirements -Extra $Extra -Type $Type -Properties "DisplayName = 'Test policy'; Mode = 'Indexed'")
    }

    function Get-ViolationObject {
        # The compiled condition after the type condition.
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['if']['allOf'][1]
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Tag (ADR-0020)' {
    It 'records a tag field with its name' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Tag CostCenter | Must -Exist }")
        $result.Diagnostics | Should -BeNullOrEmpty
        $field = (Get-FirstAssertion $result).Field
        $field.Kind.ToString() | Should -Be 'Tag'
        $field.TagName.Value | Should -Be 'CostCenter'
        $field.Location.Keyword | Should -Be 'Tag'
    }

    It 'records a parameter as the tag name' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Extra 'Parameter TagName -Type String' -Requirements "Require 'r' { Tag (Param TagName) | Must -Exist }")
        $result.Diagnostics | Should -BeNullOrEmpty
        (Get-FirstAssertion $result).Field.TagName.Name | Should -Be 'TagName'
    }

    It 'compiles to the same JSON as Field "tags[''name'']"' {
        $tag = Invoke-TagCompile -Requirements "Require 'r' { Tag CostCenter | Must -Not -Be 'none' }"
        $field = Invoke-TagCompile -Requirements "Require 'r' { Field `"tags['CostCenter']`" | Must -Not -Be 'none' }"
        $tag.Errors | Should -BeNullOrEmpty
        $tag.RuleJson | Should -BeExactly $field.RuleJson
        $tag.RuleJson.Contains("`"field`": `"tags['CostCenter']`"") | Should -BeTrue
    }

    It 'emits a parameter tag name in the form built-in tag policies use, with the JSON name' -ForEach @(
        @{ Declaration = 'Parameter TagName -Type String'; JsonName = 'tagName' }
        @{ Declaration = "Parameter @{ Name = 'TagName'; Type = 'String'; JsonName = 'tag_name' }"; JsonName = 'tag_name' }
    ) {
        $result = Invoke-TagCompile -Extra $Declaration -Requirements "Require 'r' { Tag (Param TagName) | Must -Exist }"
        (Get-ViolationObject $result)['field'] | Should -Be "[concat('tags[', parameters('$JsonName'), ']')]"
    }

    It 'can be used in <Where>' -ForEach @(
        @{ Where = 'When'; Requirements = "When { Tag Environment | Must -Be 'prod' }; Require 'r' { Field name | Must -Exist }" }
        @{ Where = 'AnyOf'; Requirements = "Require 'r' { AnyOf { Tag Environment | Must -Be 'prod'; Field name | Must -Exist } }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Diagnostics | Should -BeNullOrEmpty
    }

    It 'is rejected inside Each, where fields refer to the element' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Each networkAcls.ipRules[*] { Tag x | Must -Exist } }")
        $result.Codes | Should -Contain 'BYL1002'
        ($result.Diagnostics | Where-Object Code -EQ 'BYL1002').Message | Should -BeLike "'Tag' cannot be used inside 'Each'*"
    }

    It 'rejects the tag name <Name>' -ForEach @(
        @{ Name = "`"it's`"" }
        @{ Name = "'a[b'" }
        @{ Name = "'a]b'" }
        @{ Name = "''" }
        @{ Name = "(Arm '[parameters(''x'')]')" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Tag $Name | Must -Exist }")
        $result.Codes | Should -Contain 'BYL1023'
    }

    It 'counts a parameter used as a tag name as used' {
        $result = Invoke-TagCompile -Extra 'Parameter TagName -Type String' -Requirements "Require 'r' { Tag (Param TagName) | Must -Exist }"
        $result.Codes | Should -Not -Contain 'BYL3029'
    }

    It 'requires a tag name parameter to be declared and a String' {
        $result = Invoke-TagCompile -Extra 'Parameter Count -Type Integer' -Requirements "Require 'r' { Tag (Param Count) | Must -Exist; Tag (Param Missing) | Must -Exist }"
        $result.Errors | Should -Be @('BYL3034', 'BYL3020')
    }

    It 'warns when a policy that checks tags has Mode All' {
        $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Tag CostCenter | Must -Exist }")
        $result.Codes | Should -Contain 'BYL3040'
    }
}

Describe 'ResourceGroupTag (ADR-0020)' {
    It 'emits <Expected> as a value' -ForEach @(
        @{ Argument = 'CostCenter'; Expected = "[resourceGroup().tags['CostCenter']]" }
        @{ Argument = '(Param TagName)'; Expected = "[resourceGroup().tags[parameters('tagName')]]" }
    ) {
        $result = Invoke-TagCompile -Extra 'Parameter TagName -Type String' -Requirements "Require 'r' { Tag (Param TagName) | Must -Be (ResourceGroupTag $Argument) }"
        (Get-ViolationObject $result)['notEquals'] | Should -Be $Expected
    }

    It 'rejects an invalid tag name' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Field name | Must -Be (ResourceGroupTag 'a]') }")
        $result.Codes | Should -Contain 'BYL1023'
    }

    It 'requires its tag name parameter to be declared and a String' {
        $result = Invoke-TagCompile -Extra 'Parameter Count -Type Integer' -Requirements "Require 'r' { Field name | Must -Be (ResourceGroupTag (Param Count)); Field kind | Must -Be (ResourceGroupTag (Param Gone)) }"
        $result.Errors | Should -Be @('BYL3034', 'BYL3020')
    }

    It 'rejects -BeIn, because it is a single value' {
        $result = Invoke-TagCompile -Requirements "Require 'r' { Field name | Must -BeIn (ResourceGroupTag Owner) }"
        $result.Errors | Should -Be @('BYL3017')
    }
}

Describe 'Value conditions (ADR-0025)' {
    It 'records <Subject> as the subject of the assertion' -ForEach @(
        @{ Subject = 'ResourceGroupTag Owner'; Type = 'BylawResourceGroupTag' }
        @{ Subject = 'Param Enabled'; Type = 'BylawParamRef' }
        @{ Subject = "Arm `"[field('name')]`""; Type = 'BylawExpr' }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { $Subject | Must -Be 'x' }")
        $result.Diagnostics | Should -BeNullOrEmpty
        $assertion = Get-FirstAssertion $result
        $assertion.Field | Should -BeNullOrEmpty
        $assertion.Subject.GetType().Name | Should -Be $Type
    }

    It 'rejects a literal piped into Must' {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { 'constant' | Must -Be 'x' }")
        $result.Codes | Should -Be @('BYL1008')
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = '-Exist'; Requirements = "Require 'r' { ResourceGroupTag Owner | Must -Exist }" }
        @{ Case = '-IfPresent'; Requirements = "Require 'r' { ResourceGroupTag Owner | Must -Be 'x' -IfPresent }" }
        @{ Case = '-Strict inside Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { ResourceGroupTag Owner | Must -Be 'x' -Strict } }" }
        @{ Case = 'a value condition inside Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { ResourceGroupTag Owner | Must -Be 'x' } }" }
        @{ Case = 'a value condition in a group inside Each'; Requirements = "Require 'r' { Each networkAcls.ipRules[*] { AnyOf { Arm `"[field('name')]`" | Must -Be 'x' } } }" }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements)
        $result.Codes | Should -Be @('BYL1024')
    }

    It 'emits a value condition in When as written' {
        $result = Invoke-TagCompile -Requirements "When { ResourceGroupTag Owner | Must -Not -Be '' }; Require 'r' { Field name | Must -Exist }"
        $condition = Get-ViolationObject $result
        $condition['value'] | Should -Be "[resourceGroup().tags['Owner']]"
        $condition['notEquals'] | Should -Be ''
    }

    It 'inverts a value condition in Require without a missing-field guard' {
        # A field condition -Not -Be would get an exists:false guard; an expression gets none.
        $result = Invoke-TagCompile -Requirements "Require 'r' { ResourceGroupTag Owner | Must -Not -Be '' }"
        $condition = Get-ViolationObject $result
        $condition.Keys | Should -Be @('value', 'equals')
        $condition['equals'] | Should -Be ''
    }

    It 'emits a parameter subject as a parameters() expression' {
        $result = Invoke-TagCompile -Extra 'Parameter Enabled -Type Boolean' -Requirements "When { Param Enabled | Must -Be `$true }; Require 'r' { Field name | Must -Exist }"
        $condition = Get-ViolationObject $result
        $condition['value'] | Should -Be "[parameters('enabled')]"
        $condition['equals'] | Should -BeTrue
    }

    It 'requires a parameter subject to be declared' {
        $result = Invoke-TagCompile -Requirements "Require 'r' { Param Enabled | Must -Be `$true }"
        $result.Errors | Should -Be @('BYL3020')
    }

    It 'works inside AnyOf' {
        # The group's violation is an allOf, which flattening merges into the rule's allOf.
        $result = Invoke-TagCompile -Requirements "Require 'r' { AnyOf { ResourceGroupTag Owner | Must -Be ''; Tag Owner | Must -Exist } }"
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        Format-BylawTestCondition -Condition $result.RuleObject['if'] | Should -Be 'allOf[equals, notEquals, exists:false]'
        $result.RuleObject['if']['allOf'][1]['value'] | Should -Be "[resourceGroup().tags['Owner']]"
    }

    It 'compiles the tag inheritance rule of the built-in policy' {
        # Azure's built-in "Inherit a tag from the resource group": the tag differs from the
        # resource group's, and the resource group has the tag.
        $requirements = @'
When { ResourceGroupTag (Param TagName) | Must -Not -Be '' }
Require 'The tag matches the resource group' {
    Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName))
}
'@
        $script = "Policy 'tags-inherit' { Properties @{ DisplayName = 'x'; Mode = 'Indexed' }; Parameter TagName -Type String; Resource * { $requirements }; Effect Audit }"
        $result = Invoke-BylawTestCompile -Script $script
        $result.Errors | Should -BeNullOrEmpty -Because ($result.Diagnostics -join '; ')
        $result.RuleObject['if']['allOf'][0]['value'] | Should -Be "[resourceGroup().tags[parameters('tagName')]]"
        $result.RuleObject['if']['allOf'][0]['notEquals'] | Should -Be ''
        $result.RuleObject['if']['allOf'][1]['field'] | Should -Be "[concat('tags[', parameters('tagName'), ']')]"
        $result.RuleObject['if']['allOf'][1]['notEquals'] | Should -Be "[resourceGroup().tags[parameters('tagName')]]"
    }
}

Describe 'Fields used as values' {
    It 'rejects <Keyword> as a Must value, without also reporting it as not piped to Must' -ForEach @(
        @{ Keyword = 'Tag'; Value = '(Tag Owner)' }
        @{ Keyword = 'Field'; Value = '(Field kind)' }
    ) {
        $result = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements "Require 'r' { Field name | Must -Be $Value }")
        $result.Codes | Should -Be @('BYL1025')
    }
}
