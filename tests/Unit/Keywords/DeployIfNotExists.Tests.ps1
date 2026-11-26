BeforeDiscovery {
    # The -ForEach data below is built during discovery, so these are needed then too.
    $script:Extension = 'Microsoft.Compute/virtualMachines/extensions'
    $script:GoodDeployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters ([ordered]@{ vmName = (Arm `"[field('name')]`"); location = (Arm `"[field('location')]`") })"

    function script:Format-DineBlock {
        # A DeployIfNotExists block with the given statements in its block.
        param(
            [string] $Inner = "Require 'r' { Field publisher | Must -Be 'Microsoft.Azure.Security' }; $GoodDeployment",
            [string] $Parameters = "-Role 'Virtual Machine Contributor'"
        )
        "DeployIfNotExists -Type '$Extension' $Parameters { $Inner }"
    }
}

BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
    . (Join-Path $PSScriptRoot '../../Helpers/BylawTestHelpers.ps1')

    $script:Extension = 'Microsoft.Compute/virtualMachines/extensions'
    $script:VmContributor = '/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
    $script:GoodDeployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters ([ordered]@{ vmName = (Arm `"[field('name')]`"); location = (Arm `"[field('location')]`") })"

    # Template files, next to the test.bylaw.ps1 that Invoke-BylawTestScript writes to TestDrive.
    $templateFolder = Join-Path $TestDrive 'templates'
    $null = New-Item -ItemType Directory -Force -Path $templateFolder
    $template = [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters     = [ordered]@{
            vmName     = @{ type = 'string' }
            Location   = @{ type = 'string' }
            exclusions = [ordered]@{ type = 'string'; defaultValue = '' }
        }
        resources      = @(
            [ordered]@{ type = 'Microsoft.Compute/virtualMachines/extensions'; apiVersion = '2023-03-01'; name = "[concat(parameters('vmName'), '/IaaSAntimalware')]" }
        )
    }
    [System.IO.File]::WriteAllText((Join-Path $templateFolder 'antimalware.json'), (ConvertTo-Json -InputObject $template -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $templateFolder 'broken.json'), '{ "resources": [ }')
    [System.IO.File]::WriteAllText((Join-Path $templateFolder 'no-resources.json'), '{ "contentVersion": "1.0.0.0" }')
    [System.IO.File]::WriteAllText((Join-Path $templateFolder 'template.bicep'), "resource x 'y' = {}")

    function Format-DineBlock {
        param(
            [string] $Inner = "Require 'r' { Field publisher | Must -Be 'Microsoft.Azure.Security' }; $GoodDeployment",
            [string] $Parameters = "-Role 'Virtual Machine Contributor'"
        )
        "DeployIfNotExists -Type '$Extension' $Parameters { $Inner }"
    }

    function Format-DinePolicy {
        # A Windows VM policy with the given effect block.
        param(
            [string] $Effect = (Format-DineBlock),
            [string] $Extra = '',
            [string] $Properties = "DisplayName = 'Test policy'; Mode = 'Indexed'; Category = 'Compute'; Version = '1.0.0'"
        )
        @"
Policy 'test-policy' {
    Properties @{ $Properties }
    $Extra
    Resource 'Microsoft.Compute/virtualMachines' {
        When { Field storageProfile.osDisk.osType | Must -Be 'Windows' }
    }
    $Effect
}
"@
    }

    function Invoke-DineCompile {
        param([string] $Effect = (Format-DineBlock), [string] $Extra = '')
        Invoke-BylawTestCompile -Script (Format-DinePolicy -Effect $Effect -Extra $Extra)
    }

    function Get-DineDetail {
        param([Parameter(Mandatory)] $Result)
        $Result.Errors | Should -BeNullOrEmpty -Because ($Result.Diagnostics -join '; ')
        $Result.RuleObject['then']['details']
    }

    function Get-Deployment {
        param([Parameter(Mandatory)] $Result)
        (Get-DineDetail $Result)['deployment']
    }

    function Get-Message {
        param([Parameter(Mandatory)] $Result, [Parameter(Mandatory)] [string] $Code)
        @($Result.Diagnostics | Where-Object Code -EQ $Code | ForEach-Object Message) -join "`n"
    }
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'DeployIfNotExists and Deployment (ADR-0030, ADR-0031)' {
    Context 'emitted rule' {
        It 'emits the effect, roles, existence condition and deployment, in Learn''s order' {
            $result = Invoke-DineCompile
            $result.RuleObject['then']['effect'] | Should -BeExactly 'DeployIfNotExists'
            $details = Get-DineDetail $result
            $details.Keys | Should -Be @('type', 'existenceCondition', 'roleDefinitionIds', 'deployment')
            , $details['roleDefinitionIds'] | Should -BeOfType [object[]]
            $details['roleDefinitionIds'] | Should -BeExactly @($VmContributor)
            $details['deployment'].Keys | Should -Be @('properties')
            $details['deployment']['properties'].Keys | Should -Be @('mode', 'template', 'parameters')
            $details['deployment']['properties']['mode'] | Should -BeExactly 'incremental'
        }

        It 'emits the template file in its own key order' {
            $template = (Get-Deployment (Invoke-DineCompile))['properties']['template']
            $template.Keys | Should -Be @('$schema', 'contentVersion', 'parameters', 'resources')
            $template['parameters'].Keys | Should -Be @('vmName', 'Location', 'exclusions')
            $template['resources'][0]['name'] | Should -BeExactly "[concat(parameters('vmName'), '/IaaSAntimalware')]"
        }

        It 'emits each parameter as { value }, in the order of an [ordered] hashtable' {
            $parameters = (Get-Deployment (Invoke-DineCompile))['properties']['parameters']
            $parameters.Keys | Should -Be @('vmName', 'location')
            $parameters['vmName'].Keys | Should -Be @('value')
            $parameters['vmName']['value'] | Should -BeExactly "[field('name')]"
        }

        It 'sorts the parameters of a plain hashtable, so the output never changes' {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters @{ vmName = 'a'; location = 'b'; exclusions = 'c' }"
            $parameters = (Get-Deployment (Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)))['properties']['parameters']
            $parameters.Keys | Should -Be @('exclusions', 'location', 'vmName')
        }

        It 'emits a <Kind> parameter value' -ForEach @(
            @{ Kind = 'literal'; Value = "'westeurope'"; Extra = ''; Expected = 'westeurope' }
            @{ Kind = 'Param'; Value = '(Param TargetLocation)'; Extra = 'Parameter TargetLocation -Default westeurope'; Expected = "[parameters('targetLocation')]" }
            @{ Kind = 'Arm'; Value = "(Arm `"[field('location')]`")"; Extra = ''; Expected = "[field('location')]" }
            @{ Kind = 'ResourceGroupTag'; Value = '(ResourceGroupTag Region)'; Extra = ''; Expected = "[resourceGroup().tags['Region']]" }
        ) {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters @{ vmName = 'vm'; location = $Value }"
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment) -Extra $Extra
            (Get-Deployment $result)['properties']['parameters']['location']['value'] | Should -BeExactly $Expected
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'emits -Template as written, keeping an [ordered] hashtable''s key order' {
            $deployment = "Deployment -Template ([ordered]@{ contentVersion = '1.0.0.0'; resources = @(); outputs = @{} })"
            $properties = (Get-Deployment (Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)))['properties']
            $properties.Keys | Should -Be @('mode', 'template')
            $properties['template'].Keys | Should -Be @('contentVersion', 'resources', 'outputs')
            , $properties['template']['resources'] | Should -BeOfType [object[]]
        }

        It 'emits -Scope Subscription with -Location' {
            $deployment = 'Deployment -Template @{ resources = @() } -Scope subscription -Location (Param Location)'
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment) -Extra 'Parameter Location -Default westeurope'
            $details = Get-DineDetail $result
            $details.Keys | Should -Be @('type', 'roleDefinitionIds', 'deploymentScope', 'deployment')
            $details['deploymentScope'] | Should -BeExactly 'Subscription'
            $details['deployment'].Keys | Should -Be @('location', 'properties')
            $details['deployment']['location'] | Should -BeExactly "[parameters('location')]"
            $result.Codes | Should -Not -Contain 'BYL3029'
        }

        It 'emits several roles in the order written' {
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Parameters "-Role 'Virtual Machine Contributor', 'Reader'")
            (Get-DineDetail $result)['roleDefinitionIds'].Count | Should -Be 2
        }

        It 'accepts an effect parameter that allows DeployIfNotExists, AuditIfNotExists and Disabled' {
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Parameters "-Role 'Virtual Machine Contributor' -Effect (Param Effect)") -Extra 'Parameter Effect -AllowedValues DeployIfNotExists, AuditIfNotExists, Disabled -Default DeployIfNotExists'
            $result.Errors | Should -BeNullOrEmpty
            $result.RuleObject['then']['effect'] | Should -BeExactly "[parameters('effect')]"
        }

        It 'generates an EPAC effect parameter that allows DeployIfNotExists and Disabled' {
            $result = Invoke-DineCompile
            $result.Emitted.Diagnostics | Should -BeNullOrEmpty
            $parameter = (ConvertFrom-Json -InputObject $result.Emitted.Text -AsHashtable).properties.parameters.effect
            $parameter['allowedValues'] | Should -BeExactly @('DeployIfNotExists', 'Disabled')
            $parameter['defaultValue'] | Should -BeExactly 'DeployIfNotExists'
        }

        It 'conforms to the EPAC schema' {
            $result = Invoke-DineCompile
            Test-Json -Json $result.Emitted.Text -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/epac-policy-definition-schema.json') | Should -BeTrue
        }

        It 'matches template parameter names ignoring case, as ARM does' {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters @{ VMNAME = 'a'; location = 'b' }"
            (Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)).Errors | Should -BeNullOrEmpty
        }
    }

    Context 'front-end errors' {
        It 'reports <Code> for <Case>' -ForEach @(
            @{ Code = 'BYL1032'; Case = 'no -Role'; Effect = (Format-DineBlock -Parameters '') }
            @{ Code = 'BYL1032'; Case = 'an empty -Role'; Effect = (Format-DineBlock -Parameters "-Role ''") }
            @{ Code = 'BYL1043'; Case = 'no block'; Effect = "DeployIfNotExists -Type '$Extension' -Role 'Reader'" }
            @{ Code = 'BYL1043'; Case = 'no Deployment'; Effect = (Format-DineBlock -Inner "Require 'r' { Field publisher | Must -Exist }") }
            @{ Code = 'BYL1044'; Case = 'neither -TemplateFile nor -Template'; Effect = (Format-DineBlock -Inner 'Deployment') }
            @{ Code = 'BYL1044'; Case = 'both -TemplateFile and -Template'; Effect = (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/antimalware.json -Template @{ resources = @() }') }
            @{ Code = 'BYL1045'; Case = 'a missing template file'; Effect = (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/missing.json') }
            @{ Code = 'BYL1045'; Case = 'a template file that is not JSON'; Effect = (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/broken.json') }
            @{ Code = 'BYL1045'; Case = 'a template without resources'; Effect = (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/no-resources.json') }
            @{ Code = 'BYL1045'; Case = 'a Bicep file'; Effect = (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/template.bicep') }
            @{ Code = 'BYL1045'; Case = 'a -Template whose resources is not an array'; Effect = (Format-DineBlock -Inner "Deployment -Template @{ resources = 'x' }") }
            @{ Code = 'BYL1045'; Case = 'a Param inside -Template'; Effect = (Format-DineBlock -Inner 'Deployment -Template @{ resources = @(); x = (Param P) }') }
            @{ Code = 'BYL1040'; Case = 'an invalid -Scope'; Effect = (Format-DineBlock -Inner 'Deployment -Template @{ resources = @() } -Scope Tenant') }
            @{ Code = 'BYL1046'; Case = '-Scope Subscription without -Location'; Effect = (Format-DineBlock -Inner 'Deployment -Template @{ resources = @() } -Scope Subscription') }
            @{ Code = 'BYL1039'; Case = 'a -Location that is a number'; Effect = (Format-DineBlock -Inner 'Deployment -Template @{ resources = @() } -Location 5') }
            @{ Code = 'BYL1004'; Case = 'two Deployment'; Effect = (Format-DineBlock -Inner 'Deployment -Template @{ resources = @() }; Deployment -Template @{ resources = @() }') }
            @{ Code = 'BYL1002'; Case = 'Deployment in AuditIfNotExists'; Effect = "AuditIfNotExists -Type '$Extension' { Deployment -Template @{ resources = @() } }" }
            @{ Code = 'BYL1002'; Case = 'Deployment in Policy'; Effect = 'Effect Audit; Deployment -Template @{ resources = @() }' }
            @{ Code = 'BYL1026'; Case = 'DeployIfNotExists and AuditIfNotExists'; Effect = "AuditIfNotExists -Type '$Extension'; $(Format-DineBlock)" }
            @{ Code = 'BYL1030'; Case = 'a literal -Effect'; Effect = (Format-DineBlock -Parameters "-Role 'Reader' -Effect Disabled") }
        ) {
            $result = Invoke-BylawTestScript -Script (Format-DinePolicy -Effect $Effect)
            $result.Codes | Should -Contain $Code -Because ($result.Diagnostics -join ' || ')
        }

        It 'explains that Bicep is not supported yet' {
            $result = Invoke-BylawTestScript -Script (Format-DinePolicy -Effect (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/template.bicep'))
            Get-Message $result 'BYL1045' | Should -BeLike "*is a Bicep file. Bicep isn't supported yet: build it to JSON with 'bicep build'*"
        }

        It 'says where it looked for a missing template file' {
            $result = Invoke-BylawTestScript -Script (Format-DinePolicy -Effect (Format-DineBlock -Inner 'Deployment -TemplateFile ./templates/missing.json'))
            $expected = [System.IO.Path]::GetFullPath((Join-Path $TestDrive 'templates/missing.json'))
            Get-Message $result 'BYL1045' | Should -BeLike "*was not found (looked for $([WildcardPattern]::Escape($expected)))*"
        }
    }

    Context 'validation' {
        It 'reports BYL3093 for a value passed to a parameter the template does not have' {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters ([ordered]@{ vmName = 'a'; location = 'b'; vmname2 = 'c' })"
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)
            Get-Message $result 'BYL3093' | Should -Be "Deployment passes 'vmname2', which is not a parameter of the template file 'antimalware.json'. Its parameters: vmName, Location, exclusions."
        }

        It 'reports BYL3094 once for a required template parameter that is not passed' {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters @{ vmName = 'a' }"
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)
            @($result.Diagnostics | Where-Object Code -EQ 'BYL3094').Count | Should -Be 1
            Get-Message $result 'BYL3094' | Should -BeLike "*requires parameter 'Location', which has no defaultValue*"
        }

        It 'reports BYL3093 for -Template with no parameters' {
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner 'Deployment -Template @{ resources = @() } -Parameters @{ x = 1 }')
            Get-Message $result 'BYL3093' | Should -BeLike '*of the template. It has no parameters.'
        }

        It 'reports an unknown role' {
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Parameters "-Role 'Not A Role'")
            $result.Errors | Should -Contain 'BYL3060'
        }

        It 'reports an undeclared parameter passed to the template' {
            $deployment = "Deployment -TemplateFile ./templates/antimalware.json -Parameters @{ vmName = (Param Missing); location = 'b' }"
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Inner $deployment)
            Get-Message $result 'BYL3020' | Should -BeLike "*'Missing' is passed to the template but not declared*"
        }

        It 'reports BYL3072 for an effect parameter that allows Audit' {
            $result = Invoke-DineCompile -Effect (Format-DineBlock -Parameters "-Role 'Reader' -Effect (Param Effect)") -Extra 'Parameter Effect -AllowedValues DeployIfNotExists, Audit -Default DeployIfNotExists'
            Get-Message $result 'BYL3072' | Should -Be "Effect parameter 'Effect' of a DeployIfNotExists policy allows 'Audit'. Allowed values: DeployIfNotExists, AuditIfNotExists, Disabled."
        }

        It 'reports BYL3090 when -Type is the Resource type without the resource''s own name' {
            $result = Invoke-DineCompile -Effect "DeployIfNotExists -Type 'Microsoft.Compute/virtualMachines' -Role 'Reader' { Deployment -Template @{ resources = @() } }"
            $result.Errors | Should -Contain 'BYL3090'
            $result.Codes | Should -Not -Contain 'BYL3091'
        }

        It 'points Effect DeployIfNotExists to the keyword' {
            $result = Invoke-BylawTestCompile -Script (Format-BylawTestPolicy -Effect 'DeployIfNotExists')
            Get-Message $result 'BYL3030' | Should -BeLike '*DeployIfNotExists has its own block*'
        }
    }
}
