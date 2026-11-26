BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:snapshotPath = Join-Path $TestDrive 'aliases.json'
    $fixture = @'
{
  "schemaVersion": 1,
  "generatedAt": "2026-01-01T00:00:00Z",
  "types": {
    "Microsoft.Storage/storageAccounts": {
      "aliases": {
        "Microsoft.Storage/storageAccounts/publicNetworkAccess": { "modifiable": true, "type": "String" },
        "Microsoft.Storage/storageAccounts/minimumTlsVersion": {},
        "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]": {},
        "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value": {},
        "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].action": {}
      }
    },
    "Microsoft.Compute/virtualMachines": {
      "aliases": {
        "Microsoft.Compute/imagePublisher": {},
        "Microsoft.Compute/licenseType": {},
        "Microsoft.Compute/virtualMachines/extensions/licenseType": {}
      }
    },
    "Microsoft.Network/networkSecurityGroups": {
      "aliases": {
        "Microsoft.Network/networkSecurityGroups/securityRules[*]": {},
        "Microsoft.Network/networkSecurityGroups/securityRules[*].access": {},
        "Microsoft.Network/networkSecurityGroups/securityRules[*].destinationPortRanges[*]": {}
      }
    }
  }
}
'@
    Set-Content -Path $snapshotPath -Value $fixture -Encoding utf8NoBOM

    function Invoke-ResolutionTest {
        # Runs the front-end on a policy and then the resolution pass; returns policy and diagnostics.
        param(
            [Parameter(Mandatory)] [string] $Requirements,
            [string] $Type = 'Microsoft.Storage/storageAccounts',
            [switch] $AllowUnknownAlias
        )
        $frontEnd = Invoke-BylawTestScript -Script (Format-BylawTestPolicy -Requirements $Requirements -Type $Type)
        $frontEnd.Diagnostics | Should -BeNullOrEmpty -Because 'the test policy must be valid DSL'
        InModuleScope Bylaw -Parameters @{ Policy = $frontEnd.Policies[0]; Path = $snapshotPath; Allow = $AllowUnknownAlias.IsPresent } {
            param($Policy, $Path, $Allow)
            $snapshot = Get-BylawAliasSnapshot -Path $Path
            $diagnostics = @(Invoke-BylawAliasResolution -Policy $Policy -Snapshot $snapshot -AllowUnknownAlias:$Allow)
            [pscustomobject]@{
                Policy      = $Policy
                Diagnostics = $diagnostics
                Codes       = @($diagnostics | ForEach-Object Code)
            }
        }
    }

    function Get-FirstNode($Result) {
        $Result.Policy.Resource.Requirements[0].Children[0]
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'Alias resolution (ADR-0008)' {
    Context 'short names under a resource type' {
        It 'resolves an exact match to the snapshot casing' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field PublicNetworkAccess | Must -Be 'Disabled' }"
            $result.Diagnostics | Should -BeNullOrEmpty
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
            $result.Policy.Resource.ResolvedType | Should -BeExactly 'Microsoft.Storage/storageAccounts'
        }

        It 'resolves an alias that is not prefixed with the full type path' {
            $result = Invoke-ResolutionTest -Type 'Microsoft.Compute/virtualMachines' -Requirements "Require 'r' { Field imagePublisher | Must -Be 'x' }"
            $result.Diagnostics | Should -BeNullOrEmpty
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Compute/imagePublisher'
        }

        It 'reports an ambiguous short name with the candidates' {
            $result = Invoke-ResolutionTest -Type 'Microsoft.Compute/virtualMachines' -Requirements "Require 'r' { Field licenseType | Must -Be 'x' }"
            $result.Codes | Should -Be @('BYL2002')
            $result.Diagnostics[0].Message | Should -BeLike '*Microsoft.Compute/licenseType, Microsoft.Compute/virtualMachines/extensions/licenseType*'
        }

        It 'reports an unknown name and suggests the closest one' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field publicNetworkAcess | Must -Be 'Disabled' }"
            $result.Codes | Should -Be @('BYL2001')
            $result.Diagnostics[0].Message | Should -BeLike "*Did you mean 'publicNetworkAccess'?*"
            $result.Diagnostics[0].Location.Keyword | Should -Be 'Field'
            $result.Diagnostics[0].Severity.ToString() | Should -Be 'Error'
        }

        It 'resolves fields in When as well as Require' {
            $result = Invoke-ResolutionTest -Requirements "When { Field minimumTlsVersion | Must -Exist }; Require 'r' { Field publicNetworkAccess | Must -Exist }"
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Policy.Resource.When[0].Children[0].Field.Resolved | Should -Be 'Microsoft.Storage/storageAccounts/minimumTlsVersion'
        }
    }

    Context 'reserved fields and full aliases' {
        It 'passes <Written> through as <Expected>' -ForEach @(
            @{ Written = 'kind'; Expected = 'kind' }
            @{ Written = 'Location'; Expected = 'location' }
            @{ Written = 'identity.TYPE'; Expected = 'identity.type' }
            @{ Written = "tags['CostCentre']"; Expected = "tags['CostCentre']" }
            @{ Written = 'TAGS.env'; Expected = 'tags.env' }
        ) {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field `"$Written`" | Must -Exist }"
            $result.Diagnostics | Should -BeNullOrEmpty
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly $Expected
        }

        It 'validates a full alias, including one of another type' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field 'microsoft.compute/IMAGEPUBLISHER' | Must -Exist }"
            $result.Diagnostics | Should -BeNullOrEmpty
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Compute/imagePublisher'
        }

        It 'reports an unknown full alias' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field 'Microsoft.Storage/storageAccounts/nope' | Must -Exist }"
            $result.Codes | Should -Be @('BYL2001')
        }
    }

    Context 'Resource *' {
        It 'requires full aliases' {
            $result = Invoke-ResolutionTest -Type '*' -Requirements "Require 'r' { Field publicNetworkAccess | Must -Exist }"
            $result.Codes | Should -Be @('BYL2004')
        }

        It 'accepts reserved fields and full aliases' {
            $result = Invoke-ResolutionTest -Type '*' -Requirements "Require 'r' { Field location | Must -Exist; Field 'Microsoft.Storage/storageAccounts/publicNetworkAccess' | Must -Exist }"
            $result.Diagnostics | Should -BeNullOrEmpty
            $result.Policy.Resource.ResolvedType | Should -BeNullOrEmpty
        }
    }

    Context 'arrays and Each' {
        It 'rejects [*] in a field outside Each and suggests Each' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field 'networkAcls.ipRules[*].value' | Must -Not -Be '0.0.0.0/0' }"
            $result.Codes | Should -Be @('BYL2005')
            $result.Diagnostics[0].Message | Should -BeLike '*Each networkAcls.ipRules`[`*`] { Field value | Must ... }*'
        }

        It 'resolves the Each path and element fields relative to it' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Each networkAcls.ipRules[*] { Field value | Must -Not -Be '0.0.0.0/0'; Field ACTION | Must -Be 'Allow' } }"
            $result.Diagnostics | Should -BeNullOrEmpty
            $each = Get-FirstNode $result
            $each.Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]'
            $each.Children[0].Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value'
            $each.Children[1].Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].action'
        }

        It 'resolves nested Each and Element' {
            $requirements = "Require 'r' { Each securityRules[*] { Field access | Must -Be 'Deny'; Each destinationPortRanges[*] { Element | Must -Not -Be '*' } } }"
            $result = Invoke-ResolutionTest -Type 'Microsoft.Network/networkSecurityGroups' -Requirements $requirements
            $result.Diagnostics | Should -BeNullOrEmpty
            $inner = (Get-FirstNode $result).Children[1]
            $inner.Field.Resolved | Should -BeExactly 'Microsoft.Network/networkSecurityGroups/securityRules[*].destinationPortRanges[*]'
            $inner.Children[0].Field.Resolved | Should -BeExactly 'Microsoft.Network/networkSecurityGroups/securityRules[*].destinationPortRanges[*]'
        }

        It 'reports an unknown element field with a suggestion' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Each networkAcls.ipRules[*] { Field valeu | Must -Exist } }"
            $result.Codes | Should -Be @('BYL2001')
            $result.Diagnostics[0].Message | Should -BeLike "*Did you mean 'value'?*"
        }

        It 'reports an unknown array once, not once per element field' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Each networkAcls.nope[*] { Field value | Must -Exist; Field action | Must -Exist } }"
            $result.Codes | Should -Be @('BYL2001')
        }

        It 'rejects [*] inside an element field and suggests nesting Each' {
            $result = Invoke-ResolutionTest -Type 'Microsoft.Network/networkSecurityGroups' -Requirements "Require 'r' { Each securityRules[*] { Field 'destinationPortRanges[*]' | Must -Exist } }"
            $result.Codes | Should -Be @('BYL2005')
        }
    }

    Context 'unknown types and aliases' {
        It 'reports an unknown resource type once' {
            $result = Invoke-ResolutionTest -Type 'Microsoft.Nope/things' -Requirements "Require 'r' { Field a | Must -Exist; Field b | Must -Exist }"
            $result.Codes | Should -Be @('BYL2003')
        }

        It 'allows one unknown alias with Field -AllowUnknownAlias, silently' {
            $result = Invoke-ResolutionTest -Requirements "Require 'r' { Field brandNewSetting -AllowUnknownAlias | Must -Be 'x' }"
            $result.Diagnostics | Should -BeNullOrEmpty
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/brandNewSetting'
        }

        It 'allows unknown aliases build-wide with a warning for each' {
            $result = Invoke-ResolutionTest -AllowUnknownAlias -Requirements "Require 'r' { Field brandNewSetting | Must -Be 'x'; Field publicNetworkAccess | Must -Exist }"
            $result.Codes | Should -Be @('BYL2006')
            $result.Diagnostics[0].Severity.ToString() | Should -Be 'Warning'
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Storage/storageAccounts/brandNewSetting'
        }

        It 'downgrades an unknown type to a warning build-wide and builds alias names' {
            $result = Invoke-ResolutionTest -AllowUnknownAlias -Type 'Microsoft.Nope/things' -Requirements "Require 'r' { Field setting | Must -Exist }"
            $result.Codes | Should -Be @('BYL2003')
            $result.Diagnostics[0].Severity.ToString() | Should -Be 'Warning'
            (Get-FirstNode $result).Field.Resolved | Should -BeExactly 'Microsoft.Nope/things/setting'
        }
    }
}
