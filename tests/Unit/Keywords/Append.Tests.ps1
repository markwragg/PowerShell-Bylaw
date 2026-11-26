BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Prefix = 'Microsoft.Storage/storageAccounts/'

    function Format-AppendPolicy {
        # A storage account policy that requires HTTPS only, with the given Append block.
        param(
            [string] $Append = 'Append { Field supportsHttpsTrafficOnly | Add $true }',
            [string] $Requirements = "Require 'HTTPS only' { Field supportsHttpsTrafficOnly | Must -Be `$true }",
            [string] $Extra = '',
            [string] $Properties = "DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Storage'; Version = '1.0.0'"
        )
        @"
Policy 'test-policy' {
    Properties @{ $Properties }
    $Extra
    Resource 'Microsoft.Storage/storageAccounts' {
        $Requirements
    }
    $Append
}
"@
    }

    function Invoke-AppendCompile {
        param([string] $Append, [string] $Requirements, [string] $Extra, [string] $Properties)
        $arguments = @{}
        foreach ($name in 'Append', 'Requirements', 'Extra', 'Properties') {
            if ($PSBoundParameters.ContainsKey($name)) {
                $arguments[$name] = $PSBoundParameters[$name]
            }
        }
        Invoke-BylawTestCompile -Script (Format-AppendPolicy @arguments)
    }

    function Get-AppendDetail {
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        , $Result.RuleObject['then']['details']
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Append (ADR-0030)' {
    Context 'emitted rule' {
        It 'emits the effect and one { field, value } per Add, as an array' {
            $result = Invoke-AppendCompile
            $result.RuleObject['then']['effect'] | Should -BeExactly 'Append'
            $details = Get-AppendDetail $result
            , $details | Should -BeOfType [object[]]
            $details.Count | Should -Be 1
            $details[0].Keys | Should -Be @('field', 'value')
            $details[0]['field'] | Should -BeExactly "$($Prefix)supportsHttpsTrafficOnly"
            $details[0]['value'] | Should -BeExactly $true
        }

        It 'keeps the order the operations are written in' {
            $append = "Append { Field supportsHttpsTrafficOnly | Add `$true; Field minimumTlsVersion | Add 'TLS1_2' }"
            $requirements = "Require 'r' { Field supportsHttpsTrafficOnly | Must -Be `$true; Field minimumTlsVersion | Must -Be 'TLS1_2' }"
            $details = Get-AppendDetail (Invoke-AppendCompile -Append $append -Requirements $requirements)
            $details.ForEach({ $_['field'] }) | Should -Be @("$($Prefix)supportsHttpsTrafficOnly", "$($Prefix)minimumTlsVersion")
        }

        It 'adds an object to a [*] array, keeping an ordered hashtable''s key order' {
            $append = "Append { Field 'networkAcls.ipRules[*]' | Add ([ordered]@{ value = '40.40.40.40'; action = 'Allow' }) }"
            $requirements = "Require 'r' { Each networkAcls.ipRules[*] { Field value | Must -Not -Be '0.0.0.0/0' } }"
            $result = Invoke-AppendCompile -Append $append -Requirements $requirements
            $details = Get-AppendDetail $result
            $details[0]['field'] | Should -BeExactly "$($Prefix)networkAcls.ipRules[*]"
            $result.RuleJson | Should -BeLike '*"value": {*"value": "40.40.40.40",*"action": "Allow"*}*'
            $result.Codes | Should -Not -Contain 'BYL3083'
        }

        It 'adds an array' {
            $append = "Append { Field 'networkAcls.ipRules' | Add @(@{ value = '1.1.1.1' }, @{ value = '2.2.2.2' }) }"
            $requirements = "Require 'r' { Field networkAcls.ipRules | Must -Exist }"
            $details = Get-AppendDetail (Invoke-AppendCompile -Append $append -Requirements $requirements)
            , $details[0]['value'] | Should -BeOfType [object[]]
            $details[0]['value'].Count | Should -Be 2
        }

        It 'emits a <Kind> value' -ForEach @(
            @{ Kind = 'Param'; Value = '(Param HttpsOnly)'; Extra = 'Parameter HttpsOnly -Type Boolean -Default $true'; Expected = "[parameters('httpsOnly')]" }
            @{ Kind = 'Arm'; Value = '(Arm "[bool(''true'')]")'; Extra = ''; Expected = "[bool('true')]" }
        ) {
            $details = Get-AppendDetail (Invoke-AppendCompile -Append "Append { Field supportsHttpsTrafficOnly | Add $Value }" -Extra $Extra)
            $details[0]['value'] | Should -BeExactly $Expected
        }

        It 'emits a tag field, with a ResourceGroupTag value' {
            $append = 'Append { Tag CostCenter | Add (ResourceGroupTag CostCenter) }'
            $result = Invoke-AppendCompile -Append $append -Requirements "Require 'r' { Tag CostCenter | Must -Exist }"
            $details = Get-AppendDetail $result
            $details[0]['field'] | Should -BeExactly "tags['CostCenter']"
            $details[0]['value'] | Should -BeExactly "[resourceGroup().tags['CostCenter']]"
        }

        It 'emits an effect parameter from -Effect' {
            $result = Invoke-AppendCompile -Append 'Append -Effect (Param Effect) { Field supportsHttpsTrafficOnly | Add $true }' -Extra 'Parameter Effect -AllowedValues Append, Disabled -Default Append'
            $result.Errors | Should -BeNullOrEmpty
            $result.RuleObject['then']['effect'] | Should -BeExactly "[parameters('effect')]"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'counts a parameter used only in an Add value as used' {
            $result = Invoke-AppendCompile -Append 'Append { Field supportsHttpsTrafficOnly | Add (Param HttpsOnly) }' -Extra 'Parameter HttpsOnly -Type Boolean -Default $true'
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'generates an EPAC effect parameter that allows Append and Disabled' {
            $result = Invoke-AppendCompile
            @($result.Emitted.Diagnostics | ForEach-Object Code) | Should -Be @('BYL4010')
            $parameter = (ConvertFrom-Json -InputObject $result.Emitted.Text -AsHashtable).properties.parameters.effect
            $parameter['allowedValues'] | Should -BeExactly @('Append', 'Disabled')
            $parameter['defaultValue'] | Should -BeExactly 'Append'
        }

        It 'warns (BYL4010) that the EPAC schema expects details to be an object' {
            $result = Invoke-AppendCompile
            $diagnostic = $result.Emitted.Diagnostics | Where-Object Code -EQ 'BYL4010'
            $diagnostic.Severity.ToString() | Should -Be 'Warning'
            $result.Emitted.Text | Should -Not -BeNullOrEmpty
            $schema = Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json'
            { Test-Json -Json $result.Emitted.Text -SchemaFile $schema -ErrorAction Stop } | Should -Throw '*/properties/policyRule/then/details*'
        }

        It 'does not warn about the EPAC schema in plain JSON' {
            InModuleScope Bylaw -Parameters @{ Policy = (Invoke-AppendCompile).Policy } {
                param($Policy)
                (Invoke-BylawEmitter -Policy $Policy -Format PlainJson).Diagnostics | Should -BeNullOrEmpty
            }
        }
    }

    Context 'front-end errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1036'; Case = 'AddOrReplace in Append'; Append = "Append { Field minimumTlsVersion | AddOrReplace 'TLS1_2' }" }
            @{ Code = 'BYL1036'; Case = 'Remove in Append'; Append = 'Append { Tag Environment | Remove }' }
            @{ Code = 'BYL1037'; Case = 'Add with -Condition'; Append = 'Append { Field supportsHttpsTrafficOnly | Add $true -Condition (Arm "[true()]") }' }
            @{ Code = 'BYL1027'; Case = 'Add without a value'; Append = 'Append { Field supportsHttpsTrafficOnly | Add }' }
            @{ Code = 'BYL1031'; Case = 'Add with no field'; Append = 'Append { Add $true }' }
            @{ Code = 'BYL1013'; Case = 'an empty block'; Append = 'Append { }' }
            @{ Code = 'BYL1013'; Case = 'no block'; Append = 'Append' }
            @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Append = 'Append -Effect Disabled { Field supportsHttpsTrafficOnly | Add $true }' }
            @{ Code = 'BYL1026'; Case = 'Append and Effect'; Append = 'Effect Deny; Append { Field supportsHttpsTrafficOnly | Add $true }' }
            @{ Code = 'BYL1026'; Case = 'Append and Modify'; Append = "Append { Field supportsHttpsTrafficOnly | Add `$true }; Modify -Role 'Tag Contributor' { Tag A | AddOrReplace 'a' }" }
            @{ Code = 'BYL1004'; Case = 'two Append blocks'; Append = 'Append { Field supportsHttpsTrafficOnly | Add $true }; Append { Field supportsHttpsTrafficOnly | Add $true }' }
            @{ Code = 'BYL1002'; Case = 'Must in Append'; Append = 'Append { Field supportsHttpsTrafficOnly | Must -Be $true }' }
            @{ Code = 'BYL1002'; Case = 'Element in Append'; Append = 'Append { Element | Add $true }' }
            @{ Code = 'BYL1007'; Case = 'a field not piped to Add'; Append = 'Append { Field minimumTlsVersion; Field supportsHttpsTrafficOnly | Add $true }' }
            @{ Code = 'BYL1020'; Case = 'a Param inside a hashtable'; Append = "Append { Field 'networkAcls.ipRules[*]' | Add @{ value = (Param Range) } }" }
            @{ Code = 'BYL1020'; Case = 'an Arm inside a nested hashtable'; Append = "Append { Field 'networkAcls.ipRules[*]' | Add @{ a = @{ b = (Arm '[x()]') } } }" }
            @{ Code = 'BYL1020'; Case = 'a Param inside a hashtable in an array'; Append = "Append { Field 'networkAcls.ipRules' | Add @(@{ value = (Param Range) }) }" }
        ) {
            $result = Invoke-BylawTestScript -Script (Format-AppendPolicy -Append $Append)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'explains that Append can only Add' {
            $result = Invoke-BylawTestScript -Script (Format-AppendPolicy -Append "Append { Field minimumTlsVersion | AddOrReplace 'TLS1_2' }")
            Get-Message $result 'BYL1036' | Should -Be "AddOrReplace can't be used in Append, which can only Add values to the request. To replace or remove a value, use Modify."
        }

        It 'says a field in Append is not piped to Add' {
            $result = Invoke-BylawTestScript -Script (Format-AppendPolicy -Append 'Append { Field minimumTlsVersion; Field supportsHttpsTrafficOnly | Add $true }')
            Get-Message $result 'BYL1007' | Should -BeLike '*is not piped to Add*'
        }

        It 'still reports Add outside Modify and Append' {
            $result = Invoke-BylawTestScript -Script (Format-AppendPolicy -Requirements "Require 'r' { Field supportsHttpsTrafficOnly | Add `$true }")
            Get-Message $result 'BYL1002' | Should -BeLike "*'Modify' or 'Append'*"
        }
    }

    Context 'validation' {
        It 'reports BYL3080 for [*] before the end of the path' {
            $result = Invoke-AppendCompile -Append "Append { Field 'networkAcls.ipRules[*].action' | Add 'Allow' }"
            Get-Message $result 'BYL3080' | Should -BeLike "*only allowed at the end of the path*Field 'networkAcls.ipRules``[``*``]' | Add*"
            $result.Codes | Should -Not -Contain 'BYL2005'
        }

        It 'reports BYL3081 for the same field twice, ignoring case' {
            $result = Invoke-AppendCompile -Append 'Append { Field supportsHttpsTrafficOnly | Add $true; Field SupportsHttpsTrafficOnly | Add $false }'
            Get-Message $result 'BYL3081' | Should -BeLike "*is added by more than one Add (first at line 7)*"
        }

        It 'reports an unknown alias in an Add field' {
            $result = Invoke-AppendCompile -Append 'Append { Field supportsHttpsOnly | Add $true }'
            $result.Errors | Should -Contain 'BYL2001'
        }

        It 'warns (BYL3082) that Azure recommends Modify for <Case>' -ForEach @(
            @{ Case = 'Tag'; Field = 'Tag Environment'; Requirement = 'Tag Environment | Must -Exist' }
            @{ Case = 'a tags field'; Field = "Field 'tags'"; Requirement = "Field 'tags' | Must -Exist" }
        ) {
            $result = Invoke-AppendCompile -Append "Append { $Field | Add 'x' }" -Requirements "Require 'r' { $Requirement }"
            $diagnostic = $result.Diagnostics | Where-Object Code -EQ 'BYL3082'
            $diagnostic.Severity.ToString() | Should -Be 'Warning'
            $diagnostic.Message | Should -BeLike '*recommends Modify for tags*'
        }

        It 'warns (BYL3083) when no Require checks an added field' {
            $result = Invoke-AppendCompile -Append "Append { Field minimumTlsVersion | Add 'TLS1_2' }"
            $diagnostic = $result.Diagnostics | Where-Object Code -EQ 'BYL3083'
            $diagnostic.Severity.ToString() | Should -Be 'Warning'
            $diagnostic.Message | Should -BeLike "*Append adds '$($Prefix)minimumTlsVersion', but no Require checks it*"
        }

        It 'warns (BYL3083) for a [*] field that no Each checks' {
            $result = Invoke-AppendCompile -Append "Append { Field 'networkAcls.ipRules[*]' | Add @{ value = '1.1.1.1' } }"
            $result.Codes | Should -Contain 'BYL3083'
        }

        It 'counts an Each over the array, with no element condition, as checking a [*] field' {
            $result = Invoke-AppendCompile -Append "Append { Field 'networkAcls.ipRules[*]' | Add @{ value = '1.1.1.1' } }" -Requirements "Require 'r' { Each networkAcls.ipRules[*] { Element | Must -Not -BeNullOrEmpty } }"
            $result.Codes | Should -Not -Contain 'BYL3083'
        }

        It 'reports an undeclared parameter in an Add value' {
            $result = Invoke-AppendCompile -Append 'Append { Field supportsHttpsTrafficOnly | Add (Param HttpsOnly) }'
            Get-Message $result 'BYL3020' | Should -BeLike "*'HttpsOnly' is used but not declared*"
        }

        It 'reports BYL3072 for an effect parameter that allows <Value>' -ForEach @(
            @{ Value = 'Audit' }, @{ Value = 'Deny' }, @{ Value = 'Modify' }
        ) {
            $result = Invoke-AppendCompile -Append 'Append -Effect (Param Effect) { Field supportsHttpsTrafficOnly | Add $true }' -Extra "Parameter Effect -AllowedValues Append, $Value -Default Append"
            Get-Message $result 'BYL3072' | Should -Be "Effect parameter 'Effect' of an Append policy allows '$Value'. Allowed values: Append, Disabled."
        }

        It 'points Effect Append to the Append block' {
            $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Effect 'Append')
            Get-Message $result 'BYL3030' | Should -BeLike '*Append has its own block*'
        }
    }
}

Describe 'Add in Modify is unchanged' {
    It 'still emits a Modify add operation' {
        $script = Format-AppendPolicy -Append "Modify -Role 'Tag Contributor' { Tag Environment | Add 'Production' }" -Requirements "Require 'r' { Tag Environment | Must -Exist }"
        $result = Invoke-BylawTestCompile -Script $script
        $result.Errors | Should -BeNullOrEmpty
        $result.RuleObject['then']['details']['operations'][0]['operation'] | Should -BeExactly 'add'
    }
}
