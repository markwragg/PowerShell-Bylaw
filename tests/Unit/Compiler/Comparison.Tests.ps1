# Semantic comparison of definitions (ADR-0041).

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:GoldenFiles = @(Get-ChildItem -Path (Join-Path $root 'tests/Golden'), (Join-Path $root 'tests/GoldenPlainJson'), (Join-Path $root 'examples') -Recurse -Filter '*.json' |
            Where-Object { $_.Directory.Name -ne 'templates' } | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force

    function Compare-TestRule {
        # Compares two if conditions, given as JSON, in otherwise identical policies.
        param([Parameter(Mandatory)] [string] $Left, [Parameter(Mandatory)] [string] $Right)
        InModuleScope Bylaw -Parameters @{ Left = $Left; Right = $Right } {
            param($Left, $Right)
            $wrap = { param($If) [ordered]@{ properties = [ordered]@{ displayName = 'p'; policyRule = [ordered]@{ if = (ConvertFrom-BylawJson -Json $If); then = [ordered]@{ effect = 'Deny' } } } } }
            Compare-BylawDefinition -Reference (& $wrap $Left) -Difference (& $wrap $Right)
        }
    }

    function Compare-TestDefinition {
        param([Parameter(Mandatory)] [string] $Left, [Parameter(Mandatory)] [string] $Right)
        InModuleScope Bylaw -Parameters @{ Left = $Left; Right = $Right } {
            param($Left, $Right)
            Compare-BylawDefinition -Reference $Left -Difference $Right
        }
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-BylawDefinition' {
    Context 'rules that are equivalent' {
        It 'treats <Case> as equivalent' -ForEach @(
            @{
                Case  = 'reordered groups and nesting'
                Left  = '{ "allOf": [ { "field": "a", "equals": "1" }, { "allOf": [ { "field": "b", "equals": "2" }, { "field": "c", "equals": "3" } ] } ] }'
                Right = '{ "allOf": [ { "field": "c", "equals": "3" }, { "field": "a", "equals": "1" }, { "field": "b", "equals": "2" } ] }'
            }
            @{
                Case  = 'a group of one'
                Left  = '{ "anyOf": [ { "field": "a", "equals": "1" } ] }'
                Right = '{ "field": "a", "equals": "1" }'
            }
            @{
                Case  = 'notEquals and not equals'
                Left  = '{ "field": "a", "notEquals": "x" }'
                Right = '{ "not": { "field": "a", "equals": "x" } }'
            }
            @{
                Case  = 'exists false and not exists true'
                Left  = '{ "field": "a", "exists": false }'
                Right = '{ "not": { "field": "a", "exists": "true" } }'
            }
            @{
                Case  = 'field names and values in another case'
                Left  = '{ "field": "Microsoft.Storage/storageAccounts/kind", "in": [ "StorageV2", "BlobStorage" ] }'
                Right = '{ "field": "microsoft.storage/storageaccounts/KIND", "in": [ "blobstorage", "STORAGEV2" ] }'
            }
            @{
                Case  = 'in with one value and equals'
                Left  = '{ "field": "a", "in": [ "x" ] }'
                Right = '{ "field": "a", "equals": "x" }'
            }
            @{
                Case  = "De Morgan's laws"
                Left  = '{ "not": { "allOf": [ { "field": "a", "equals": "1" }, { "field": "b", "notEquals": "2" } ] } }'
                Right = '{ "anyOf": [ { "field": "a", "notEquals": "1" }, { "field": "b", "equals": "2" } ] }'
            }
            @{
                Case  = 'absorption'
                Left  = '{ "anyOf": [ { "field": "a", "equals": "1" }, { "allOf": [ { "field": "a", "equals": "1" }, { "field": "b", "equals": "2" } ] } ] }'
                Right = '{ "field": "a", "equals": "1" }'
            }
            @{
                Case  = 'a condition split differently between When and Require'
                Left  = '{ "allOf": [ { "field": "w", "equals": "1" }, { "anyOf": [ { "field": "v", "equals": "1" }, { "field": "u", "equals": "1" } ] } ] }'
                Right = '{ "anyOf": [ { "allOf": [ { "field": "w", "equals": "1" }, { "field": "v", "equals": "1" } ] }, { "allOf": [ { "field": "u", "equals": "1" }, { "field": "w", "equals": "1" } ] } ] }'
            }
            @{
                Case  = 'count greater 0 and notEquals 0'
                Left  = '{ "count": { "field": "a[*]" }, "greater": 0 }'
                Right = '{ "count": { "field": "a[*]" }, "notEquals": 0 }'
            }
            @{
                Case  = 'count greaterOrEquals 1 and not equals 0'
                Left  = '{ "count": { "field": "a[*]" }, "greaterOrEquals": 1 }'
                Right = '{ "not": { "count": { "field": "a[*]" }, "equals": 0 } }'
            }
            @{
                Case  = 'count lessOrEquals 0 and less 1'
                Left  = '{ "count": { "field": "a[*]" }, "lessOrEquals": 0 }'
                Right = '{ "count": { "field": "a[*]" }, "less": 1 }'
            }
            @{
                Case  = 'a count that always holds'
                Left  = '{ "allOf": [ { "field": "a", "equals": "1" }, { "count": { "field": "b[*]" }, "greaterOrEquals": 0 } ] }'
                Right = '{ "field": "a", "equals": "1" }'
            }
            @{
                Case  = "count wheres written differently"
                Left  = '{ "count": { "field": "a[*]", "where": { "not": { "anyOf": [ { "field": "a[*].x", "equals": "1" }, { "field": "a[*].y", "equals": "2" } ] } } }, "greater": 0 }'
                Right = '{ "count": { "field": "a[*]", "where": { "allOf": [ { "field": "a[*].y", "notEquals": "2" }, { "field": "a[*].x", "notEquals": "1" } ] } }, "greater": 0 }'
            }
        ) {
            $result = Compare-TestRule -Left $Left -Right $Right
            $result.Result | Should -Be 'Equivalent' -Because (($result.Differences | ForEach-Object Message) -join '; ')
        }
    }

    Context 'rules that differ' {
        It 'reports <Case> as different as written, with an example' -ForEach @(
            @{ Case = 'another value'; Left = '{ "field": "a", "equals": "1" }'; Right = '{ "field": "a", "equals": "2" }' }
            @{ Case = 'match in another case'; Left = '{ "field": "a", "match": "AB##" }'; Right = '{ "field": "a", "match": "ab##" }' }
            @{ Case = 'an ARM expression in another case'; Left = '{ "field": "a", "equals": "[parameters(''x'')]" }'; Right = '{ "field": "a", "equals": "[PARAMETERS(''x'')]" }' }
            @{ Case = 'a different count range'; Left = '{ "count": { "field": "a[*]" }, "greater": 0 }'; Right = '{ "count": { "field": "a[*]" }, "greater": 1 }' }
            @{
                Case  = 'and instead of or'
                Left  = '{ "allOf": [ { "field": "a", "equals": "1" }, { "field": "b", "equals": "2" } ] }'
                Right = '{ "anyOf": [ { "field": "a", "equals": "1" }, { "field": "b", "equals": "2" } ] }'
            }
        ) {
            $result = Compare-TestRule -Left $Left -Right $Right
            $result.Result | Should -Be 'DifferentAsWritten'
            $result.Differences[0].Path | Should -Be 'properties.policyRule.if'
            $result.Differences[0].Message | Should -BeLike 'The conditions differ as written: with *, the * matches and the * doesn''t.*'
        }

        It 'reports more than 16 distinct leaf conditions as unproven' {
            $leaves = 1..17 | ForEach-Object { "{ ""field"": ""f$_"", ""equals"": ""1"" }" }
            $left = '{ "anyOf": [ ' + ($leaves -join ', ') + ' ] }'
            $right = '{ "allOf": [ ' + ($leaves -join ', ') + ' ] }'
            $result = Compare-TestRule -Left $left -Right $right
            $result.Result | Should -Be 'Unproven'
            $result.Differences[0].Message | Should -BeLike '*17 distinct leaf conditions, more than the 16*'
        }

        It 'proves 16 distinct leaf conditions' {
            $leaves = 1..16 | ForEach-Object { "{ ""field"": ""f$_"", ""equals"": ""1"" }" }
            $reversed = @($leaves)
            [array]::Reverse($reversed)
            $left = '{ "anyOf": [ ' + ($leaves -join ', ') + ' ] }'
            $right = '{ "not": { "allOf": [ ' + (($reversed | ForEach-Object { "{ ""not"": $_ }" }) -join ', ') + ' ] } }'
            (Compare-TestRule -Left $left -Right $right).Result | Should -Be 'Equivalent'
        }
    }

    Context 'everything else' {
        BeforeAll {
            $script:Base = '{ "name": "p", "properties": { "displayName": "P", "mode": "Indexed", "metadata": { "version": "1.0.0", "category": "Tags" }, "parameters": { "effect": { "type": "String", "allowedValues": [ "Audit", "Deny" ], "defaultValue": "Audit" } }, "policyRule": { "if": { "field": "type", "equals": "Microsoft.Storage/storageAccounts" }, "then": { "effect": "[parameters(''effect'')]" } } } }'
        }

        It 'ignores the EPAC schema, key order, the case of names and kinds, and metadata Azure adds' {
            $other = '{ "$schema": "https://example/schema.json", "properties": { "policyRule": { "then": { "effect": "[parameters(''effect'')]" }, "if": { "equals": "microsoft.storage/storageaccounts", "field": "TYPE" } }, "parameters": { "effect": { "defaultValue": "Audit", "type": "string", "allowedValues": [ "Audit", "Deny" ] } }, "metadata": { "category": "Tags", "version": "1.0.0", "createdBy": "someone", "deployedBy": "epac/abc" }, "mode": "indexed", "displayName": "P" }, "name": "P" }'
            (Compare-TestDefinition -Left $Base -Right $other).Result | Should -Be 'Equivalent'
        }

        It 'reports <Case> as different, with its path' -ForEach @(
            @{ Case = 'a display name'; Old = '"displayName": "P"'; New = '"displayName": "Q"'; Path = 'properties.displayname' }
            @{ Case = 'a default value'; Old = '"defaultValue": "Audit"'; New = '"defaultValue": "Deny"'; Path = 'properties.parameters.effect.defaultvalue' }
            @{ Case = 'a category'; Old = '"category": "Tags"'; New = '"category": "Storage"'; Path = 'properties.metadata.category' }
            @{ Case = 'the effect'; Old = '"effect": "[parameters(''effect'')]" }'; New = '"effect": "Deny" }'; Path = 'properties.policyRule.then.effect' }
        ) {
            $result = Compare-TestDefinition -Left $Base -Right $Base.Replace($Old, $New)
            $result.Result | Should -Be 'Different'
            $result.Differences.Path | Should -Contain $Path
        }

        It 'compares role definition IDs by GUID' {
            $left = '{ "properties": { "policyRule": { "if": { "field": "type", "equals": "x" }, "then": { "effect": "modify", "details": { "roleDefinitionIds": [ "/providers/Microsoft.Authorization/roleDefinitions/4A9AE827-6DC8-4573-8AC7-8239D42AA03F" ], "operations": [] } } } } }'
            $right = $left.Replace('/providers/Microsoft.Authorization/roleDefinitions/4A9AE827-6DC8-4573-8AC7-8239D42AA03F', '/providers/microsoft.authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f')
            (Compare-TestDefinition -Left $left -Right $right).Result | Should -Be 'Equivalent'
        }

        It 'compares an existence condition by meaning' {
            $left = '{ "properties": { "policyRule": { "if": { "field": "type", "equals": "x" }, "then": { "effect": "auditIfNotExists", "details": { "type": "y", "existenceCondition": { "allOf": [ { "field": "y/a", "equals": "1" }, { "field": "y/b", "notEquals": "2" } ] } } } } } }'
            $right = $left.Replace('{ "allOf": [ { "field": "y/a", "equals": "1" }, { "field": "y/b", "notEquals": "2" } ] }', '{ "not": { "anyOf": [ { "field": "y/b", "equals": "2" }, { "field": "y/a", "notEquals": "1" } ] } }')
            (Compare-TestDefinition -Left $left -Right $right).Result | Should -Be 'Equivalent'
            $wrong = $left.Replace('"notEquals": "2"', '"equals": "2"')
            $result = Compare-TestDefinition -Left $left -Right $wrong
            $result.Result | Should -Be 'DifferentAsWritten'
            $result.Differences[0].Path | Should -Be 'properties.policyRule.then.details.existenceCondition'
        }

        It 'compares an initiative''s members and groups as sets' {
            $left = '{ "properties": { "displayName": "I", "policyDefinitions": [ { "policyDefinitionReferenceId": "a", "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/X", "groupNames": [ "g1", "g2" ] }, { "policyDefinitionReferenceId": "b", "policyDefinitionName": "local", "parameters": { "effect": { "value": "Audit" } } } ], "policyDefinitionGroups": [ { "name": "g1" }, { "name": "g2" } ] } }'
            $right = '{ "properties": { "policyDefinitionGroups": [ { "name": "G2" }, { "name": "g1" } ], "policyDefinitions": [ { "policyDefinitionReferenceId": "B", "policyDefinitionName": "local", "parameters": { "effect": { "value": "Audit" } } }, { "groupNames": [ "g2", "g1" ], "policyDefinitionId": "/providers/microsoft.authorization/policyDefinitions/x", "policyDefinitionReferenceId": "a" } ], "displayName": "I" } }'
            (Compare-TestDefinition -Left $left -Right $right).Result | Should -Be 'Equivalent'
            $changed = $right.Replace('"value": "Audit"', '"value": "Deny"')
            $result = Compare-TestDefinition -Left $left -Right $changed
            $result.Result | Should -Be 'Different'
            $result.Differences.Path | Should -Contain 'properties.policyDefinitions[b].parameters.effect.value'
        }
    }

    Context 'golden files' {
        It '<Name> is equivalent to itself, and to its rule with every group reversed' -ForEach $GoldenFiles {
            $text = [System.IO.File]::ReadAllText($Path)
            InModuleScope Bylaw -Parameters @{ Text = $text } {
                param($Text)
                (Compare-BylawDefinition -Reference $Text -Difference $Text).Result | Should -Be 'Equivalent'
                $reversed = ConvertFrom-BylawJson -Json $Text
                $reverse = {
                    param($Node)
                    if ($Node -is [System.Collections.IDictionary]) {
                        foreach ($key in @($Node.Keys)) {
                            if ($key -in 'allOf', 'anyOf') {
                                $items = @($Node[$key])
                                [array]::Reverse($items)
                                $Node[$key] = $items
                            }
                            & $reverse $Node[$key]
                        }
                    }
                    elseif ($Node -is [object[]]) {
                        foreach ($item in $Node) { & $reverse $item }
                    }
                }
                & $reverse $reversed['properties']['policyRule']
                $result = Compare-BylawDefinition -Reference $Text -Difference $reversed
                $result.Result | Should -Be 'Equivalent' -Because (($result.Differences | ForEach-Object Message) -join '; ')
            }
        }
    }
}
