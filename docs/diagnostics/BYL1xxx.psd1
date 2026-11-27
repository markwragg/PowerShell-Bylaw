# Diagnostics catalogue (ADR-0037): BYL1xxx, reported while a .bylaw.ps1 file runs. The wiki page
# Diagnostics-BYL1xxx is generated from this file, and tests/Build/Diagnostics.Tests.ps1 checks that
# it lists exactly the codes src emits. Example is the corrected code.
@{
    Range       = 'BYL1xxx'
    Title       = 'Front end'
    Description = 'Reported while a .bylaw.ps1 file runs, when a keyword is used in the wrong place or with the wrong arguments. They point at the line of the keyword.'
    Diagnostics = @(
        @{
            Code        = 'BYL1001'
            Severity    = 'Error'
            Title       = 'Keyword used outside a Policy block'
            Explanation = 'Bylaw''s keywords only exist while a Policy or Initiative block runs, so they don''t clash with other commands. A keyword such as Field, Param or Arm was used outside one, at the top of the file or in a function called from outside the block.'
            Fix         = 'Move the statement inside a Policy or Initiative block. To share statements between policies, put them in a scriptblock or function and call it from inside each block.'
            Example     = @'
Policy 'storage-tls' {
    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'TLS 1.2' {
            Field minimumTlsVersion | Must -Be 'TLS1_2'
        }
    }
    Effect Deny
}
'@
            Adr         = '0005'
        }
        @{
            Code        = 'BYL1002'
            Severity    = 'Error'
            Title       = 'Keyword in the wrong block'
            Explanation = 'Each keyword can only be used inside certain blocks: for example Require goes inside Resource, and Must inside When, Require, Each or a group. The message names the blocks it is allowed in. It is also reported for Element in a value count, where the member is Current, and for Tag inside Each, where field names refer to the array element.'
            Fix         = 'Move the keyword into one of the blocks the message names. The keyword''s wiki page lists them under Used in.'
            Adr         = '0005'
        }
        @{
            Code        = 'BYL1003'
            Severity    = 'Error'
            Title       = 'Nested Policy or Initiative'
            Explanation = 'A Policy or Initiative was declared inside another one. Each is a definition of its own, so it must be at the top level of the file.'
            Fix         = 'Move the inner Policy or Initiative out, after the closing brace of the outer one. A file can hold several of them.'
        }
        @{
            Code        = 'BYL1004'
            Severity    = 'Error'
            Title       = 'Keyword used more than once'
            Explanation = 'Properties and Resource can appear only once in a Policy, and Deployment only once in a DeployIfNotExists. The message gives the line of the first one.'
            Fix         = 'Merge the two into one: all the properties in one Properties hashtable, or all the requirements in one Resource. A policy has one resource type; for several, use one policy each, or Resource * with a type condition in When.'
        }
        @{
            Code        = 'BYL1005'
            Severity    = 'Error'
            Title       = 'Policy has no Resource block'
            Explanation = 'A policy needs a Resource block: it sets the resource type the policy applies to, and holds the When and Require blocks.'
            Fix         = 'Add Resource ''<type>'' { ... } for one resource type, or Resource * { ... } for every type.'
            Example     = @'
Resource 'Microsoft.Storage/storageAccounts' {
    Require 'TLS 1.2' {
        Field minimumTlsVersion | Must -Be 'TLS1_2'
    }
}
'@
        }
        @{
            Code        = 'BYL1006'
            Severity    = 'Error'
            Title       = 'Policy has no effect'
            Explanation = 'Every policy has exactly one effect, which says what Azure does with a non-compliant resource. None of the effect keywords was used.'
            Fix         = 'Add Effect Audit, Effect Deny or Effect (Param Effect), or one of the effect blocks: Modify, Append, DenyAction, Manual, AuditIfNotExists or DeployIfNotExists.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL1007'
            Severity    = 'Error'
            Title       = 'Field or count not piped to anything'
            Explanation = 'Field, Tag, Element and Count only describe what to test. On their own they do nothing, so a line with one that isn''t piped to Must (or, in Modify, to an operation) is almost certainly a mistake.'
            Fix         = 'Pipe it to Must with an operator, or inside Modify and Append to AddOrReplace, Add or Remove.'
            Example     = @'
Field publicNetworkAccess | Must -Be 'Disabled'
Count securityRules[*] | Must -BeLessOrEqual 10
'@
        }
        @{
            Code        = 'BYL1008'
            Severity    = 'Error'
            Title       = 'Must has nothing to test'
            Explanation = 'Must tests what is piped to it, and nothing was: it was called on its own, or after something that isn''t a field, tag, element, count or value.'
            Fix         = 'Pipe a Field, Tag, Element or Count, or a value such as ResourceGroupTag, Param or Arm, to Must.'
            Example     = @'
Field publicNetworkAccess | Must -Be 'Disabled'
'@
        }
        @{
            Code        = 'BYL1009'
            Severity    = 'Error'
            Title       = 'Must needs exactly one operator'
            Explanation = 'Each Must statement tests one thing, so it takes one operator, such as -Be or -BeIn. It had none or several. -Not, -IfPresent and -Strict change an operator and don''t count as one.'
            Fix         = 'Use one operator per Must. To test several things, write several Must statements: in a Require, they must all hold.'
            Example     = @'
Field minimumTlsVersion | Must -BeIn 'TLS1_2', 'TLS1_3'
Field allowBlobPublicAccess | Must -Be $false
'@
        }
        @{
            Code        = 'BYL1010'
            Severity    = 'Error'
            Title       = '-IfPresent or -Strict where it doesn''t apply'
            Explanation = '-IfPresent makes a missing field compliant, and -Strict makes a missing field on an array element a violation. They only mean something where Bylaw adds missing-field checks: -IfPresent in Require, and -Strict inside Each. They can''t be used together, and When and Count -Where are emitted as written, so neither applies there.'
            Fix         = 'Remove the switch, or move the statement to where it applies. In When, write the missing-field case out with -Exist if you need it.'
            Adr         = '0004'
        }
        @{
            Code        = 'BYL1011'
            Severity    = 'Error'
            Title       = 'Unknown Properties key'
            Explanation = 'Properties only takes the keys Bylaw knows how to emit, so a misspelled key fails instead of being dropped. The message suggests the closest key. An initiative has no Mode: each member policy has its own.'
            Fix         = 'Use one of the keys the message lists: DisplayName, Description, Category, Version, Mode, Preview, Deprecated or Metadata. Put other metadata in Metadata.'
        }
        @{
            Code        = 'BYL1012'
            Severity    = 'Error'
            Title       = 'Properties value of the wrong type'
            Explanation = 'DisplayName, Description, Category, Version and Mode are strings, Preview and Deprecated are $true or $false, and Metadata is a hashtable.'
            Fix         = 'Give the key a value of the type the message names, e.g. Version = ''1.0.0'' in quotes, or Preview = $true.'
        }
        @{
            Code        = 'BYL1013'
            Severity    = 'Error'
            Title       = 'Empty block'
            Explanation = 'A block that should hold statements is missing or has none: When, Require, Each, AnyOf or AllOf without a Must, Modify or Append without an operation, or Count -Where without a condition. An empty block would emit an empty condition, which Azure rejects or which matches everything.'
            Fix         = 'Add the statements the block needs, or remove it. For Count, leave out -Where to count every element.'
        }
        @{
            Code        = 'BYL1014'
            Severity    = 'Error'
            Title       = 'Policy or Initiative stopped by an error'
            Explanation = 'PowerShell raised an error while the block ran, for example a mistyped command, a failing expression or a throw in your own code. Bylaw reports it with the block''s name and stops compiling that definition.'
            Fix         = 'Read the error in the message: it is PowerShell''s own. Fix the line it points to, as you would in any script.'
        }
        @{
            Code        = 'BYL1015'
            Severity    = 'Error'
            Title       = 'Invalid Parameter declaration'
            Explanation = 'A Parameter was declared in a way Bylaw can''t use: no name, a name with characters other than letters, digits and underscores, a name declared twice, an unknown type or option, a type that can''t be inferred, or the hashtable form mixed with named options.'
            Fix         = 'Give the parameter a name, and its options either as named parameters or as one hashtable. Add -Type when there''s no default or allowed values to infer it from.'
            Example     = @'
Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
Parameter AllowedLocations @{ Type = 'Array'; Metadata = @{ strongType = 'location' } }
'@
            Adr         = '0021'
        }
        @{
            Code        = 'BYL1016'
            Severity    = 'Error'
            Title       = 'Each needs an array path ending in [*]'
            Explanation = 'Each goes through the elements of an array, so its path must name an array with [*] at the end, as Azure''s aliases do.'
            Fix         = 'Add [*] to the path, e.g. networkAcls.ipRules[*].'
            Example     = @'
Each networkAcls.ipRules[*] {
    Field value | Must -Not -Be '0.0.0.0/0'
}
'@
        }
        @{
            Code        = 'BYL1017'
            Severity    = 'Error'
            Title       = 'Require needs a description'
            Explanation = 'Every Require is named with what it requires, so the source reads as a list of requirements and error messages can refer to them.'
            Fix         = 'Give the Require a description before its block.'
            Example     = @'
Require 'Public network access is disabled' {
    Field publicNetworkAccess | Must -Be 'Disabled'
}
'@
        }
        @{
            Code        = 'BYL1019'
            Severity    = 'Error'
            Title       = 'Effect needs an effect name or a parameter'
            Explanation = 'Effect takes the name of an effect, or a Param that holds one. Something else was given, such as a number or an expression.'
            Fix         = 'Use Effect Deny (or Audit or Disabled), or Effect (Param Effect).'
        }
        @{
            Code        = 'BYL1020'
            Severity    = 'Error'
            Title       = 'Param or Arm inside an array or hashtable value'
            Explanation = 'Azure Policy can only use a parameter or an expression as a whole value. An array that mixes literals with Param or Arm, or a hashtable with Param or Arm inside it, has no JSON form.'
            Fix         = 'Use one parameter for the whole value: an Array parameter for a list, or an Object parameter for a hashtable.'
            Example     = @'
Parameter AllowedValues -Type Array -Default @('a', 'b')
Field kind | Must -BeIn (Param AllowedValues)
'@
        }
        @{
            Code        = 'BYL1021'
            Severity    = 'Error'
            Title       = 'Invalid resource type'
            Explanation = 'Resource takes a resource type in the form Namespace/type, such as Microsoft.Storage/storageAccounts, with child types after further slashes.'
            Fix         = 'Correct the type, or use Resource * for a policy that applies to every type.'
        }
        @{
            Code        = 'BYL1022'
            Severity    = 'Error'
            Title       = 'AllOf outside AnyOf'
            Explanation = 'Statements in When, Require, Each and Count -Where already all have to hold, so AllOf is only needed inside AnyOf, to make one alternative out of several statements.'
            Fix         = 'Remove the AllOf and keep its statements.'
            Adr         = '0026'
        }
        @{
            Code        = 'BYL1023'
            Severity    = 'Error'
            Title       = 'Invalid tag name'
            Explanation = 'Tag and ResourceGroupTag take a tag name or a Param that holds one. A literal name can''t contain '', [ or ], because it is written inside tags[''...'']. In a field count, Current is an array element, not a tag name.'
            Fix         = 'Use the tag''s name, or Tag (Param TagName). For a tag name with those characters, write the expression with Arm.'
            Adr         = '0020'
        }
        @{
            Code        = 'BYL1024'
            Severity    = 'Error'
            Title       = 'Expression tested where only a field can be'
            Explanation = 'A value condition tests an expression such as ResourceGroupTag or Arm, not a field. An expression is never missing, so -Exist, -IfPresent and -Strict don''t apply to it, and testing one inside Each isn''t supported yet.'
            Fix         = 'Use -Not -Be '''' to require a value, and remove -IfPresent or -Strict. Inside Each, test the expression in a separate Require or in When.'
            Adr         = '0025'
        }
        @{
            Code        = 'BYL1025'
            Severity    = 'Error'
            Title       = 'Field used as a value'
            Explanation = 'A Field describes what to test, so it goes on the left of Must, not as the value to compare with.'
            Fix         = 'Pipe the field to Must. To compare two fields, write the other one with Arm.'
            Example     = @'
Field location | Must -Be (Arm '[resourceGroup().location]')
'@
        }
        @{
            Code        = 'BYL1026'
            Severity    = 'Error'
            Title       = 'More than one effect'
            Explanation = 'A policy has exactly one effect. Two effect keywords were used, for example Effect and Modify. The message gives the line of the first.'
            Fix         = 'Keep one. To let an assignment choose, use an effect parameter: Effect (Param Effect), or -Effect (Param Effect) on Modify, DenyAction and the other effect blocks.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL1027'
            Severity    = 'Error'
            Title       = 'Operation with the wrong value'
            Explanation = 'AddOrReplace and Add need the value to set. Remove takes none: it removes the field.'
            Fix         = 'Give AddOrReplace and Add a value, and remove the value from Remove.'
            Example     = @'
Tag Environment | AddOrReplace 'Production'
Tag TempResource | Remove
'@
            Adr         = '0024'
        }
        @{
            Code        = 'BYL1028'
            Severity    = 'Error'
            Title       = '-Condition needs an Arm expression'
            Explanation = 'A Modify operation''s -Condition is an ARM expression that is true or false, evaluated by Azure for each resource.'
            Fix         = 'Pass an Arm expression.'
            Example     = @'
Tag Environment | AddOrReplace 'Production' -Condition (Arm "[equals(parameters('mode'), 'strict')]")
'@
            Adr         = '0024'
        }
        @{
            Code        = 'BYL1029'
            Severity    = 'Error'
            Title       = 'Invalid -ConflictEffect'
            Explanation = 'Modify''s -ConflictEffect says what happens when two Modify policies change the same field. Azure accepts Audit, Deny and Disabled.'
            Fix         = 'Use -ConflictEffect Audit, Deny or Disabled.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL1030'
            Severity    = 'Error'
            Title       = '-Effect needs a parameter'
            Explanation = 'On Modify, Append, DenyAction, Manual and the IfNotExists effects, -Effect is only for letting an assignment choose the effect, so it takes a Param or an Arm expression, not a literal. Without it, the effect is the keyword''s own.'
            Fix         = 'Use -Effect (Param Effect), with a parameter whose allowed values include the keyword''s effect and Disabled, or leave -Effect out.'
        }
        @{
            Code        = 'BYL1031'
            Severity    = 'Error'
            Title       = 'Operation needs a field'
            Explanation = 'AddOrReplace, Add and Remove change the field piped to them, and nothing was.'
            Fix         = 'Pipe a Field or Tag to the operation.'
            Example     = @'
Tag CostCenter | Add (ResourceGroupTag CostCenter)
'@
        }
        @{
            Code        = 'BYL1032'
            Severity    = 'Error'
            Title       = 'Role needed for remediation'
            Explanation = 'Modify and DeployIfNotExists change resources through the assignment''s managed identity, so Azure needs the roles that identity must have. Bylaw writes them as roleDefinitionIds.'
            Fix         = 'Add -Role with a built-in role name or a role definition ID, e.g. -Role ''Tag Contributor''.'
            Adr         = '0022'
        }
        @{
            Code        = 'BYL1033'
            Severity    = 'Error'
            Title       = 'DenyAction supports only Delete'
            Explanation = 'Azure''s denyAction effect can only block delete requests today.'
            Fix         = 'Use DenyAction Delete.'
            Adr         = '0028'
        }
        @{
            Code        = 'BYL1034'
            Severity    = 'Error'
            Title       = 'Invalid -CascadeBehavior'
            Explanation = 'DenyAction''s -CascadeBehavior says whether deleting a parent, such as a resource group, is blocked when it would delete a protected resource. Azure accepts Deny and Allow.'
            Fix         = 'Use -CascadeBehavior Deny or Allow.'
            Adr         = '0028'
        }
        @{
            Code        = 'BYL1035'
            Severity    = 'Error'
            Title       = 'Invalid -DefaultState'
            Explanation = 'Manual''s -DefaultState is the compliance state before anyone attests. Azure accepts Unknown, Compliant and NonCompliant.'
            Fix         = 'Use -DefaultState Unknown, Compliant or NonCompliant.'
            Adr         = '0028'
        }
        @{
            Code        = 'BYL1036'
            Severity    = 'Error'
            Title       = 'Operation not allowed in Append'
            Explanation = 'Append can only add values to a create or update request. AddOrReplace and Remove need the modify effect.'
            Fix         = 'Use Add in Append, or use Modify to replace or remove a value.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL1037'
            Severity    = 'Error'
            Title       = '-Condition in Append'
            Explanation = 'Azure''s append details have no conditions, so Add in Append can''t take -Condition.'
            Fix         = 'Put the condition in When or Require instead.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL1038'
            Severity    = 'Error'
            Title       = 'IfNotExists effect needs -Type'
            Explanation = 'AuditIfNotExists and DeployIfNotExists check for a related resource, such as a VM extension or diagnostic setting, and need its resource type.'
            Fix         = 'Add -Type with the related resource''s type.'
            Example     = @'
AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' {
    Require 'The antimalware extension is installed' {
        Field publisher | Must -Be 'Microsoft.Azure.Security'
        Field 'Microsoft.Compute/virtualMachines/extensions/type' | Must -Be 'IaaSAntimalware'
    }
}
'@
            Adr         = '0030'
        }
        @{
            Code        = 'BYL1039'
            Severity    = 'Error'
            Title       = 'Invalid name or location value'
            Explanation = '-Name and -ResourceGroupName on the IfNotExists effects, and -Location on Deployment, take a literal, a Param or an Arm expression.'
            Fix         = 'Pass one of those, e.g. -Name (Arm "[field(''name'')]") or -Location (Param Location).'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL1040'
            Severity    = 'Error'
            Title       = 'Invalid scope'
            Explanation = 'Deployment -Scope and the IfNotExists effects'' -ExistenceScope take ResourceGroup or Subscription.'
            Fix         = 'Use ResourceGroup or Subscription.'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL1041'
            Severity    = 'Error'
            Title       = 'Invalid -EvaluationDelay'
            Explanation = '-EvaluationDelay says when Azure checks for the related resource after a change. Azure accepts AfterProvisioning, AfterProvisioningSuccess, AfterProvisioningFailure, or an ISO 8601 duration from 0 to 360 minutes.'
            Fix         = 'Use one of the three names, or a duration such as PT30M.'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL1043'
            Severity    = 'Error'
            Title       = 'DeployIfNotExists needs a Deployment'
            Explanation = 'DeployIfNotExists deploys a template when the related resource is missing, so its block needs a Deployment with the template.'
            Fix         = 'Add a Deployment to the block.'
            Example     = @'
DeployIfNotExists -Type 'Microsoft.Insights/diagnosticSettings' -Role 'Contributor' {
    Require 'Logs go to the workspace' {
        Field workspaceId | Must -Be (Param WorkspaceId)
    }
    Deployment -TemplateFile ./templates/diagnostic-settings.json -Parameters @{
        workspaceId = Param WorkspaceId
    }
}
'@
            Adr         = '0031'
        }
        @{
            Code        = 'BYL1044'
            Severity    = 'Error'
            Title       = 'Deployment needs one template'
            Explanation = 'Deployment takes the template either from a JSON file with -TemplateFile or as a hashtable with -Template. It had neither or both.'
            Fix         = 'Use exactly one of -TemplateFile and -Template.'
            Adr         = '0031'
        }
        @{
            Code        = 'BYL1045'
            Severity    = 'Error'
            Title       = 'Invalid deployment template'
            Explanation = 'The template file couldn''t be found or read as JSON, it isn''t an ARM template (an object with a resources array), or a -Template hashtable contains Param or Arm. The template is evaluated by the deployment, not by the policy.'
            Fix         = 'Check the path, which is relative to the .bylaw.ps1 file, and the JSON. Pass policy values with -Parameters, and use them in the template as [parameters(''name'')].'
            Adr         = '0031'
        }
        @{
            Code        = 'BYL1046'
            Severity    = 'Error'
            Title       = 'Subscription deployment needs -Location'
            Explanation = 'Azure requires a location for a deployment at subscription scope, to store its metadata.'
            Fix         = 'Add -Location to the Deployment, e.g. -Location (Param Location).'
            Adr         = '0031'
        }
        @{
            Code        = 'BYL1047'
            Severity    = 'Error'
            Title       = 'Invalid Count'
            Explanation = 'Count is a field count with an array path ending in [*], or a value count with -Value and a list: an array, a Param or an Arm expression. It had both, neither, a path without [*], or a -Value that isn''t a list.'
            Fix         = 'Use Count path[*] or Count -Value <list>.'
            Example     = @'
Count networkAcls.ipRules[*] | Must -BeGreaterThan 0
Count -Value (Param NamePatterns) -Name pattern -Where { Field name | Must -BeLike (Current pattern) } | Must -BeGreaterThan 0
'@
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1048'
            Severity    = 'Error'
            Title       = 'Invalid Count -Name'
            Explanation = '-Name names the member of a value count, so Current can refer to it. A field count has no -Name: Current is the element. Azure only allows letters and digits.'
            Fix         = 'Remove -Name from a field count, or use a name of letters and digits, e.g. -Name tagName.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1049'
            Severity    = 'Error'
            Title       = 'Nested value count needs -Name'
            Explanation = 'Azure requires a name for a value count inside another count, including one inside Each, so the two members can be told apart.'
            Fix         = 'Add -Name to the inner count, and refer to it with Current <name>.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1050'
            Severity    = 'Error'
            Title       = 'Invalid Current'
            Explanation = 'Current is the element or member being counted, so it only exists inside Count -Where. Current <name> must match the -Name of a value count around it, and Current without a name is ambiguous in a value count inside another count.'
            Fix         = 'Use Current inside -Where, with the name of the count you mean.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1051'
            Severity    = 'Error'
            Title       = 'Operator a count doesn''t take'
            Explanation = 'A count is a number, so it is tested with -Be, -BeIn, -BeGreaterThan, -BeGreaterOrEqual, -BeLessThan or -BeLessOrEqual. A count is never missing, so -IfPresent and -Strict don''t apply either.'
            Fix         = 'Use one of those operators, without -IfPresent or -Strict.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1052'
            Severity    = 'Error'
            Title       = 'Count used as a value'
            Explanation = 'A Count is something to test, so it goes on the left of Must, not as a value.'
            Fix         = 'Pipe the count to Must.'
            Example     = @'
Count securityRules[*] | Must -BeLessOrEqual 10
'@
            Adr         = '0032'
        }
        @{
            Code        = 'BYL1053'
            Severity    = 'Error'
            Title       = 'Invalid definition version'
            Explanation = 'PolicyDefinition -Version is the definitionVersion Azure uses to pick a version of the member: a major version, then a minor version or *, then a patch or *, optionally with -preview.'
            Fix         = 'Use a version such as ''1.*.*'' or ''2.1.*''.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL1054'
            Severity    = 'Error'
            Title       = 'Initiative has no members'
            Explanation = 'An initiative groups policies, so it needs at least one PolicyDefinition.'
            Fix         = 'Add the policies it includes: by name for a policy in this build, or by -Id for a built-in one.'
            Example     = @'
PolicyDefinition 'general-require-tag' -Parameters @{ tagName = 'CostCenter' }
PolicyDefinition -Id 96670d01-0a4d-4649-9c89-2d3abc0a5025 -ReferenceId 'require-environment' -Parameters @{ tagName = 'Environment' }
'@
            Adr         = '0033'
        }
        @{
            Code        = 'BYL1055'
            Severity    = 'Error'
            Title       = 'PolicyDefinition needs a name or -Id'
            Explanation = 'A member is either a policy in this build, by name, or another definition, by -Id. It had both or neither.'
            Fix         = 'Use PolicyDefinition ''policy-name'' or PolicyDefinition -Id <id> -ReferenceId <name>.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL1056'
            Severity    = 'Error'
            Title       = 'Missing or empty -ReferenceId'
            Explanation = 'The reference ID is the short name the initiative uses for a member. It defaults to the policy''s name for a member from the build, but a member by -Id needs one, and an empty one is never valid.'
            Fix         = 'Add -ReferenceId with a short name, e.g. -ReferenceId InheritCostCenter.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL1057'
            Severity    = 'Error'
            Title       = 'Missing definition group name'
            Explanation = 'DefinitionGroup needs a name, and PolicyDefinition -Group needs the names of the groups the member belongs to.'
            Fix         = 'Give the group a name, and refer to it by that name in -Group.'
            Example     = @'
DefinitionGroup 'AC-2' -DisplayName 'Account Management'
PolicyDefinition 'general-require-tag' -Group 'AC-2'
'@
            Adr         = '0033'
        }
        @{
            Code        = 'BYL1059'
            Severity    = 'Error'
            Title       = 'Tag named with Current'
            Explanation = 'Tag (Current name) would emit a field named with current(), and Azure rejects that: "''field'' and ''current'' functions are not supported in the ''field'' accessor".'
            Fix         = 'Check each tag with its own Tag, or with Tag (Param TagName) in a policy that an initiative includes once per tag.'
            Example     = @'
Tag CostCenter | Must -Exist
Tag (Param TagName) | Must -Exist
'@
            Adr         = '0032'
        }
    )
}
