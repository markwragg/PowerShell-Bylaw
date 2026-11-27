BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:InheritTag = '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54'

    function Format-Initiative {
        # An initiative with the given body. The default has one member from the build.
        param(
            [string] $Body = "PolicyDefinition 'tags-require-mandatory-tags'",
            [string] $Properties = "DisplayName = 'Tagging baseline'; Category = 'Tags'; Version = '1.0.0'",
            [string] $Name = 'tagging-baseline'
        )
        @"
Initiative '$Name' {
    Properties @{ $Properties }
    $Body
}
"@
    }

    function Invoke-InitiativeScript {
        # Runs the script and the initiative's own checks. Returns the initiative, front-end codes,
        # and validation diagnostics.
        param([Parameter(Mandatory)] [string] $Script)
        $frontEnd = Invoke-BylawTestScript -Script $Script
        $initiative = $frontEnd.Initiatives | Select-Object -First 1
        $validation = @()
        if ($initiative -and $frontEnd.Diagnostics.Count -eq 0) {
            $validation = InModuleScope Bylaw -Parameters @{ Initiative = $initiative } {
                param($Initiative)
                @(Invoke-BylawInitiativeValidation -Initiative $Initiative)
            }
        }
        $all = @($frontEnd.Diagnostics) + @($validation)
        [pscustomobject]@{
            Initiative  = $initiative
            Diagnostics = $all
            Codes       = @($all | ForEach-Object Code)
            Errors      = @($all | Where-Object { $_.Severity.ToString() -eq 'Error' } | ForEach-Object Code)
        }
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Initiative (ADR-0033)' {
    Context 'the initiative' {
        It 'collects an initiative with its properties, parameters and members, without diagnostics' {
            $body = "Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit; PolicyDefinition 'tags-require-mandatory-tags' -Parameters @{ effect = Param Effect }"
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body $body)
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Initiative.Name | Should -BeExactly 'tagging-baseline'
            $result.Initiative.Properties.DisplayName | Should -BeExactly 'Tagging baseline'
            $result.Initiative.Parameters.Name | Should -Be @('Effect')
            $result.Initiative.Members.Count | Should -Be 1
        }

        It 'can be in the same file as policies' {
            $script = @"
Policy 'p' {
    Properties @{ DisplayName = 'p' }
    Resource 'Microsoft.Storage/storageAccounts' { Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' } }
    Effect Deny
}
$(Format-Initiative -Body "PolicyDefinition 'p'")
"@
            $frontEnd = Invoke-BylawTestScript -Script $script
            $frontEnd.Diagnostics | Should -BeNullOrEmpty
            $frontEnd.Policies.Count | Should -Be 1
            $frontEnd.Initiatives.Count | Should -Be 1
        }

        It 'is exported, and its inner keywords are not' {
            $exported = @((Get-Module Bylaw).ExportedCommands.Keys)
            $exported | Should -Contain 'Initiative'
            $exported | Should -Not -Contain 'PolicyDefinition'
            $exported | Should -Not -Contain 'DefinitionGroup'
        }

        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1054'; Case = 'no members'; Body = '' }
            @{ Code = 'BYL1011'; Case = 'Mode in Properties'; Body = "PolicyDefinition 'p'"; Properties = "DisplayName = 'x'; Mode = 'All'" }
            @{ Code = 'BYL1002'; Case = 'Resource in an initiative'; Body = "PolicyDefinition 'p'; Resource * { }" }
            @{ Code = 'BYL1002'; Case = 'Effect in an initiative'; Body = "PolicyDefinition 'p'; Effect Deny" }
            @{ Code = 'BYL1003'; Case = 'a Policy inside an initiative'; Body = "PolicyDefinition 'p'; Policy 'q' { }" }
            @{ Code = 'BYL1004'; Case = 'two Properties'; Body = "PolicyDefinition 'p'; Properties @{ DisplayName = 'y' }" }
        ) {
            $arguments = @{ Body = $Body }
            if ($_.ContainsKey('Properties')) {
                $arguments.Properties = $_.Properties
            }
            $result = Invoke-InitiativeScript -Script (Format-Initiative @arguments)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'says why Mode is not allowed' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Properties "DisplayName = 'x'; Mode = 'All'")
            Get-Message $result 'BYL1011' | Should -BeLike '*An initiative has no Mode: each member policy has its own.*'
        }

        It 'reports an Initiative nested in a Policy' {
            $script = "Policy 'p' { $(Format-Initiative) }"
            $result = Invoke-BylawTestScript -Script $script
            ($result.Diagnostics | Where-Object Code -EQ 'BYL1003').Message | Should -BeLike "Initiative 'tagging-baseline' is nested inside Policy*"
        }

        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL3001'; Case = 'an invalid name'; Name = 'tagging/baseline'; Properties = "DisplayName = 'x'" }
            @{ Code = 'BYL3002'; Case = 'no DisplayName'; Name = 'i'; Properties = "Category = 'Tags'" }
            @{ Code = 'BYL3005'; Case = 'a Version that is not SemVer'; Name = 'i'; Properties = "DisplayName = 'x'; Version = '1'" }
            @{ Code = 'BYL3006'; Case = 'a generated metadata key'; Name = 'i'; Properties = "DisplayName = 'x'; Metadata = @{ category = 'x' }" }
        ) {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Name $Name -Properties $Properties)
            $result.Errors | Should -Contain $Code
        }

        It 'names an initiative in the DisplayName message' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Properties "Category = 'Tags'")
            Get-Message $result 'BYL3002' | Should -BeLike "Initiative 'tagging-baseline' needs a DisplayName*"
        }

        It 'checks parameters as for a policy' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "Parameter Tier -AllowedValues Hot, Cool -Default Archive; PolicyDefinition 'p' -Parameters @{ tier = Param Tier }")
            $result.Errors | Should -Contain 'BYL3021'
        }

        It 'warns about a parameter no member uses' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "Parameter Unused -Default x; PolicyDefinition 'p'")
            $diagnostic = $result.Diagnostics | Where-Object Code -EQ 'BYL3029'
            $diagnostic.Severity.ToString() | Should -Be 'Warning'
            $diagnostic.Message | Should -Be "Parameter 'Unused' is declared but never passed to a member."
        }

        It 'counts a parameter used in <Case> as used' -ForEach @(
            @{ Case = 'an Arm expression'; Value = "Arm `"[concat(parameters('prefix'), '-x')]`"" }
            @{ Case = 'a ResourceGroupTag name'; Value = 'ResourceGroupTag (Param Prefix)' }
        ) {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "Parameter Prefix -Default x; PolicyDefinition 'p' -Parameters @{ a = ($Value) }")
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'reports more than 400 parameters (BYL3115)' {
            $parameters = (1..401 | ForEach-Object { "Parameter P$_ -Default x" }) -join '; '
            $members = "PolicyDefinition 'p' -Parameters @{ $((1..401 | ForEach-Object { "p$_ = Param P$_" }) -join '; ') }"
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "$parameters; $members")
            Get-Message $result 'BYL3115' | Should -BeLike '*has 401 parameters; Azure allows at most 400.'
        }

        It 'reports more than 1000 members (BYL3115)' {
            $members = (1..1001 | ForEach-Object { "PolicyDefinition -Id '$InheritTag' -ReferenceId M$_" }) -join '; '
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body $members)
            Get-Message $result 'BYL3115' | Should -BeLike '*has 1001 members; Azure allows at most 1000.'
        }
    }

    Context 'PolicyDefinition' {
        It 'takes a policy name, defaulting the reference ID to it' {
            $member = (Invoke-InitiativeScript -Script (Format-Initiative)).Initiative.Members[0]
            $member.PolicyName | Should -BeExactly 'tags-require-mandatory-tags'
            $member.DefinitionId | Should -BeNullOrEmpty
            $member.ReferenceId | Should -BeExactly 'tags-require-mandatory-tags'
        }

        It 'takes -Id, -ReferenceId, -Version and -Group' {
            $body = "DefinitionGroup 'Tags'; PolicyDefinition -Id '$InheritTag' -ReferenceId InheritCostCenter -Version '1.*.*' -Group Tags"
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body $body)
            $result.Diagnostics | Should -BeNullOrEmpty
            $member = $result.Initiative.Members[0]
            $member.DefinitionId | Should -BeExactly $InheritTag
            $member.ReferenceId | Should -BeExactly 'InheritCostCenter'
            $member.Version | Should -BeExactly '1.*.*'
            $member.GroupNames | Should -Be @('Tags')
        }

        It 'accepts a policy more than once with different reference IDs' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p'; PolicyDefinition 'p' -ReferenceId p2")
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Initiative.Members.ReferenceId | Should -Be @('p', 'p2')
        }

        It 'keeps parameter values of each kind, sorting a plain hashtable' {
            $body = "Parameter Effect -AllowedValues Audit, Disabled -Default Audit; PolicyDefinition 'p' -Parameters @{ effect = Param Effect; tagName = 'CostCenter'; value = (ResourceGroupTag CostCenter); expr = (Arm '[field(''name'')]') }"
            $member = (Invoke-InitiativeScript -Script (Format-Initiative -Body $body)).Initiative.Members[0]
            @($member.Parameters.Keys) | Should -Be @('effect', 'expr', 'tagName', 'value')
            $member.Parameters['effect'].GetType().Name | Should -Be 'BylawParamRef'
            $member.Parameters['tagName'].Value | Should -BeExactly 'CostCenter'
            $member.Parameters['value'].GetType().Name | Should -Be 'BylawResourceGroupTag'
            $member.Parameters['expr'].GetType().Name | Should -Be 'BylawExpr'
        }

        It 'keeps the order of an [ordered] hashtable' {
            $member = (Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p' -Parameters ([ordered]@{ zeta = 1; alpha = 2 })")).Initiative.Members[0]
            @($member.Parameters.Keys) | Should -Be @('zeta', 'alpha')
        }

        It 'accepts -Version <Version>' -ForEach @(
            @{ Version = '1.*.*' }, @{ Version = '2.1.*' }, @{ Version = '1.0.3' }, @{ Version = '6.*.*-preview' }
        ) {
            (Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p' -Version '$Version'")).Diagnostics | Should -BeNullOrEmpty
        }

        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1055'; Case = 'a name and -Id'; Body = "PolicyDefinition 'p' -Id '/providers/Microsoft.Authorization/policyDefinitions/x' -ReferenceId x" }
            @{ Code = 'BYL1055'; Case = 'neither a name nor -Id'; Body = 'PolicyDefinition -ReferenceId x' }
            @{ Code = 'BYL1056'; Case = '-Id without -ReferenceId'; Body = "PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/x'" }
            @{ Code = 'BYL1056'; Case = 'an empty -ReferenceId'; Body = "PolicyDefinition 'p' -ReferenceId ''" }
            @{ Code = 'BYL1053'; Case = 'a -Version of 1'; Body = "PolicyDefinition 'p' -Version '1'" }
            @{ Code = 'BYL1053'; Case = 'a -Version with * for the major version'; Body = "PolicyDefinition 'p' -Version '*.*.*'" }
            @{ Code = 'BYL1053'; Case = 'a -Version with a patch after *'; Body = "PolicyDefinition 'p' -Version '1.*'" }
            @{ Code = 'BYL1057'; Case = 'an empty -Group'; Body = "PolicyDefinition 'p' -Group ''" }
            @{ Code = 'BYL1002'; Case = 'Count in an initiative'; Body = "PolicyDefinition 'p' -Parameters @{ a = (Count -Value @(1)) }" }
            @{ Code = 'BYL1020'; Case = 'a Param in a hashtable value'; Body = "Parameter P -Default x; PolicyDefinition 'p' -Parameters @{ a = @{ b = (Param P) } }" }
            @{ Code = 'BYL1002'; Case = 'PolicyDefinition in a Policy'; Body = "PolicyDefinition 'p'"; Policy = $true }
        ) {
            $script = if ($_.ContainsKey('Policy')) { "Policy 'q' { $Body }" } else { Format-Initiative -Body $Body }
            $result = Invoke-InitiativeScript -Script $script
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'reports BYL1054 only when there is no PolicyDefinition at all' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p' -Version 'x'")
            $result.Codes | Should -Contain 'BYL1053'
            $result.Codes | Should -Not -Contain 'BYL1054'
        }

        It 'reports BYL3110 for a reference ID used twice, ignoring case' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p'; PolicyDefinition 'P'")
            Get-Message $result 'BYL3110' | Should -BeLike "Reference ID 'P' is used by more than one member (first at line 3)*"
        }

        It 'accepts -Id <Case>' -ForEach @(
            @{ Case = 'for a built-in'; Id = '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' }
            @{ Case = 'at a management group'; Id = '/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/policyDefinitions/Deny-Storage-minTLS' }
            @{ Case = 'at a subscription'; Id = '/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/my-policy' }
            @{ Case = 'in any case'; Id = '/PROVIDERS/microsoft.authorization/POLICYDEFINITIONS/x' }
        ) {
            (Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition -Id '$Id' -ReferenceId r")).Errors | Should -BeNullOrEmpty
        }

        It 'reports BYL3111 for -Id <Case>' -ForEach @(
            @{ Case = 'that is an initiative'; Id = '/providers/Microsoft.Authorization/policySetDefinitions/x'; Message = "*is an initiative. An initiative can't include another initiative*" }
            @{ Case = 'that is a bare GUID'; Id = 'cd3aa116-8754-49c9-a813-ad46512ece54'; Message = '*is not a policy definition ID*' }
            @{ Case = 'of another resource type'; Id = '/providers/Microsoft.Authorization/roleDefinitions/x'; Message = '*is not a policy definition ID*' }
        ) {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition -Id '$Id' -ReferenceId r")
            Get-Message $result 'BYL3111' | Should -BeLike $Message
        }

        It 'reports an undeclared parameter in <Case>' -ForEach @(
            @{ Case = 'a Param value'; Value = 'Param Missing' }
            @{ Case = 'a ResourceGroupTag name'; Value = 'ResourceGroupTag (Param Missing)' }
        ) {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "PolicyDefinition 'p' -Parameters @{ a = ($Value) }")
            Get-Message $result 'BYL3020' | Should -BeLike "Parameter 'Missing' is passed to member 'p' but not declared*"
        }
    }

    Context 'DefinitionGroup' {
        It 'collects a group with its options' {
            $body = "DefinitionGroup 'AC-2' -DisplayName 'Account Management' -Category 'Access Control' -Description 'd' -AdditionalMetadataId '/providers/Microsoft.PolicyInsights/policyMetadata/x'; PolicyDefinition 'p' -Group 'AC-2'"
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body $body)
            $result.Diagnostics | Should -BeNullOrEmpty
            $group = $result.Initiative.Groups[0]
            $group.Name | Should -BeExactly 'AC-2'
            $group.DisplayName | Should -BeExactly 'Account Management'
            $group.Category | Should -BeExactly 'Access Control'
            $group.Description | Should -BeExactly 'd'
            $group.AdditionalMetadataId | Should -BeExactly '/providers/Microsoft.PolicyInsights/policyMetadata/x'
        }

        It 'puts a member in several groups' {
            $result = Invoke-InitiativeScript -Script (Format-Initiative -Body "DefinitionGroup A; DefinitionGroup B; PolicyDefinition 'p' -Group A, B")
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Initiative.Members[0].GroupNames | Should -Be @('A', 'B')
        }

        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1057'; Case = 'a group with no name'; Body = "DefinitionGroup ''; PolicyDefinition 'p'" }
            @{ Code = 'BYL3112'; Case = 'a group declared twice, ignoring case'; Body = "DefinitionGroup A; DefinitionGroup a; PolicyDefinition 'p' -Group A" }
            @{ Code = 'BYL3113'; Case = 'a member in an undeclared group'; Body = "PolicyDefinition 'p' -Group Missing" }
            @{ Code = 'BYL3114'; Case = 'a group with no members'; Body = "DefinitionGroup Empty; PolicyDefinition 'p'" }
            @{ Code = 'BYL1002'; Case = 'DefinitionGroup in a Policy'; Body = 'DefinitionGroup A'; Policy = $true }
        ) {
            $script = if ($_.ContainsKey('Policy')) { "Policy 'q' { $Body }" } else { Format-Initiative -Body $Body }
            $result = Invoke-InitiativeScript -Script $script
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }
    }
}
