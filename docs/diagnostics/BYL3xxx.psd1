# Diagnostics catalogue (ADR-0037): BYL3xxx, reported by validation, after a file has run and its
# fields have been resolved, and by the checks of initiative members against the build's policies.
# Example is the corrected code.
@{
    Range       = 'BYL3xxx'
    Title       = 'Validation'
    Description = 'Reported after a file has run and its fields have been resolved: checks of names, properties, parameters, operators, effects and Azure''s limits, and, once every file has compiled, of each initiative''s members against the policies they include.'
    Diagnostics = @(
        @{
            Code        = 'BYL3001'
            Severity    = 'Error'
            Title       = 'Invalid policy or initiative name'
            Explanation = 'The name becomes the definition''s name in Azure and its file name, so it must be 1 to 64 characters, with none of < > * % & : \ ? . + / " |, no control characters, no leading or trailing space, and not a name Windows reserves for files, such as CON.'
            Fix         = 'Rename the Policy or Initiative. Renaming a deployed definition creates a new one, so choose a name you can keep.'
            Adr         = '0010'
        }
        @{
            Code        = 'BYL3002'
            Severity    = 'Error'
            Title       = 'Missing or long DisplayName'
            Explanation = 'Every definition needs a DisplayName, the name shown in the portal, and Azure allows at most 128 characters.'
            Fix         = 'Add DisplayName to Properties, or shorten it. Put the detail in Description.'
            Adr         = '0016'
        }
        @{
            Code        = 'BYL3003'
            Severity    = 'Error'
            Title       = 'Description too long'
            Explanation = 'Azure allows at most 512 characters in a definition''s description.'
            Fix         = 'Shorten the Description. Longer guidance can go in Metadata or in your own documentation.'
            Adr         = '0016'
        }
        @{
            Code        = 'BYL3004'
            Severity    = 'Error'
            Title       = 'Unsupported Mode'
            Explanation = 'Language version 1.0 supports the All and Indexed modes. The resource provider modes, such as Microsoft.Kubernetes.Data, have different rules and effects, which Bylaw doesn''t cover yet.'
            Fix         = 'Use Mode = ''All'' or ''Indexed''.'
            Adr         = '0016'
        }
        @{
            Code        = 'BYL3005'
            Severity    = 'Error'
            Title       = 'Invalid Version'
            Explanation = 'A definition''s version is major.minor.patch, optionally with -preview, so tools and initiative members can compare versions.'
            Fix         = 'Use a version such as ''1.0.0'' or ''2.1.0-preview''.'
            Adr         = '0016'
        }
        @{
            Code        = 'BYL3006'
            Severity    = 'Error'
            Title       = 'Metadata key set elsewhere'
            Explanation = 'Metadata can''t set a key that Bylaw writes from Properties, such as version or category, or deployedBy, which EPAC sets when it deploys.'
            Fix         = 'Set it with its own Properties key, e.g. Properties @{ Version = ''1.0.0'' }, or leave deployedBy to EPAC.'
            Adr         = '0011'
        }
        @{
            Code        = 'BYL3007'
            Severity    = 'Error'
            Title       = 'Invalid metadata value'
            Explanation = 'Each metadata value must have a JSON form, so no scriptblocks or other PowerShell objects, and Azure allows at most 1024 characters per value.'
            Fix         = 'Use strings, numbers, booleans, arrays and hashtables, and keep each value under 1024 characters.'
        }
        @{
            Code        = 'BYL3010'
            Severity    = 'Error'
            Title       = '-Be with a list'
            Explanation = '-Be compares with one value. A list would be emitted as an equals with an array, which is never true for a single value.'
            Fix         = 'Use -BeIn for a list of values.'
            Example     = @'
Field minimumTlsVersion | Must -BeIn 'TLS1_2', 'TLS1_3'
'@
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3011'
            Severity    = 'Error'
            Title       = '-BeLike with more than one *'
            Explanation = 'Azure''s like operator allows at most one * wildcard in a pattern.'
            Fix         = 'Use one *, or test the parts with several conditions, or use -Match for a fixed-length pattern.'
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3012'
            Severity    = 'Error'
            Title       = '* in -ContainText'
            Explanation = 'Azure''s contains operator doesn''t allow wildcards: a * would be looked for literally.'
            Fix         = 'Remove the *, or use -BeLike for a wildcard match.'
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3013'
            Severity    = 'Warning'
            Title       = 'Match pattern that looks like a regular expression'
            Explanation = 'Azure''s match patterns aren''t regular expressions: # is a digit, ? a letter, . any character, and everything else is literal. A pattern with ^, $, \d, [, ( or + is probably meant as a regex and won''t match what you expect.'
            Fix         = 'Rewrite the pattern with #, ? and ., or use -BeLike for a wildcard match.'
            Example     = @'
Field name | Must -Match 'st????##'
'@
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3014'
            Severity    = 'Error'
            Title       = 'Text operator needs a string'
            Explanation = '-BeLike, -Match, -MatchCase, -ContainText and -ContainKey compare text, so their value must be a string.'
            Fix         = 'Quote the value, or use a String parameter.'
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3016'
            Severity    = 'Error'
            Title       = 'Comparison needs a number, string or date'
            Explanation = '-BeGreaterThan, -BeGreaterOrEqual, -BeLessThan and -BeLessOrEqual compare numbers, strings or dates. Azure can''t order other values, such as booleans or arrays.'
            Fix         = 'Compare with a number, a string or a date string.'
            Adr         = '0015'
        }
        @{
            Code        = 'BYL3017'
            Severity    = 'Error'
            Title       = '-BeIn with a single value'
            Explanation = 'ResourceGroupTag is one value, so it can''t be the list -BeIn needs.'
            Fix         = 'Use -Be to compare with the tag''s value.'
            Example     = @'
Tag CostCenter | Must -Be (ResourceGroupTag CostCenter)
'@
            Adr         = '0020'
        }
        @{
            Code        = 'BYL3020'
            Severity    = 'Error'
            Title       = 'Parameter used but not declared'
            Explanation = 'A Param refers to a parameter that the Policy or Initiative doesn''t declare, so the emitted [parameters(''name'')] would fail when the policy is deployed. The message says where it is used: in a rule, an effect, a tag name, a count, a deployment or an initiative member.'
            Fix         = 'Declare the parameter with Parameter, or correct the name in Param. Names are matched as written in Parameter.'
            Example     = @'
Parameter AllowedLocations -Type Array -Metadata @{ strongType = 'location' }
Field location | Must -BeIn (Param AllowedLocations)
'@
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3021'
            Severity    = 'Error'
            Title       = 'Default not in the allowed values'
            Explanation = 'A parameter''s default must be one of its allowed values, or Azure rejects the definition.'
            Fix         = 'Change the default, or add it to -AllowedValues.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3022'
            Severity    = 'Error'
            Title       = 'Two parameters with the same JSON name'
            Explanation = 'Parameter names are emitted with a lower-case first letter, so Effect and effect, for example, would both become effect.'
            Fix         = 'Rename one of them, or give one an explicit -JsonName.'
            Adr         = '0018'
        }
        @{
            Code        = 'BYL3023'
            Severity    = 'Error'
            Title       = 'Array parameter where a single value is needed'
            Explanation = 'The operator compares with one value, but the parameter is an Array.'
            Fix         = 'Use -BeIn to test against the list, or declare the parameter as a single value.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3024'
            Severity    = 'Error'
            Title       = '-BeIn with a parameter that isn''t an Array'
            Explanation = '-BeIn needs a list, but the parameter holds a single value.'
            Fix         = 'Declare the parameter with -Type Array, or use -Be.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3025'
            Severity    = 'Error'
            Title       = 'Text operator with a parameter that isn''t a String'
            Explanation = '-BeLike, -Match, -MatchCase, -ContainText and -ContainKey need text, but the parameter is of another type.'
            Fix         = 'Declare the parameter as a String.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3026'
            Severity    = 'Error'
            Title       = 'Comparison with a parameter Azure can''t order'
            Explanation = 'The comparison operators need a number, string or date, but the parameter is of another type, such as Boolean or Array.'
            Fix         = 'Declare the parameter as an Integer, Float, String or DateTime.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3027'
            Severity    = 'Error'
            Title       = 'Default of the wrong type'
            Explanation = 'A parameter''s default must be of its type, or Azure rejects the definition: for example a list for an Array, or $true or $false for a Boolean.'
            Fix         = 'Correct the default, or the -Type.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3028'
            Severity    = 'Error'
            Title       = 'Allowed values of the wrong type'
            Explanation = 'Every allowed value must be of the parameter''s type. The message lists the ones that aren''t.'
            Fix         = 'Correct the allowed values, or the -Type.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3029'
            Severity    = 'Warning'
            Title       = 'Parameter never used'
            Explanation = 'A parameter is declared but no rule, effect or value uses it, or in an initiative, no member is passed it. An assignment could set it to no effect, which is usually a mistake.'
            Fix         = 'Use the parameter, or remove it.'
            Adr         = '0021'
        }
        @{
            Code        = 'BYL3030'
            Severity    = 'Error'
            Title       = 'Unsupported effect'
            Explanation = 'Effect takes Audit, Deny or Disabled; the other effects have keywords of their own. The message lists the supported effects, and says which keyword to use for an effect with details.'
            Fix         = 'Use one of the effects the message lists, or the effect''s own keyword, such as Modify or DeployIfNotExists.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL3031'
            Severity    = 'Error'
            Title       = 'Effect parameter isn''t a String'
            Explanation = 'An effect parameter holds the name of an effect, so it must be a String.'
            Fix         = 'Declare it with -Type String, or leave -Type out and give it -AllowedValues.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL3032'
            Severity    = 'Error'
            Title       = 'Effect parameter needs allowed values'
            Explanation = 'Without allowed values, an assignment could set any effect, including one the policy can''t use. Azure''s built-in policies always list them.'
            Fix         = 'Add -AllowedValues with the effects the policy supports.'
            Example     = @'
Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
Effect (Param Effect)
'@
            Adr         = '0017'
        }
        @{
            Code        = 'BYL3033'
            Severity    = 'Error'
            Title       = 'Effect parameter allows an unsupported effect'
            Explanation = 'One of the effect parameter''s allowed values isn''t an effect Bylaw supports for this kind of policy.'
            Fix         = 'Remove that value from -AllowedValues.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL3034'
            Severity    = 'Error'
            Title       = 'Tag name parameter isn''t a String'
            Explanation = 'A parameter used as a tag name, as in Tag (Param TagName), must hold one name, so it must be a String.'
            Fix         = 'Declare the parameter with -Type String.'
            Adr         = '0020'
        }
        @{
            Code        = 'BYL3040'
            Severity    = 'Warning'
            Title       = 'Tags or location checked with Mode All'
            Explanation = 'With Mode All, the policy also evaluates resource types that don''t support tags or location, which are then reported as non-compliant. Azure recommends Indexed for policies on tags and location.'
            Fix         = 'Add Mode = ''Indexed'' to Properties, unless the policy is meant for resource groups or subscriptions.'
            Adr         = '0016'
        }
        @{
            Code        = 'BYL3041'
            Severity    = 'Warning'
            Title       = 'Policy has no Require block'
            Explanation = 'Without a Require, every resource that matches the resource type and When is non-compliant. That is sometimes intended, for example to deny a resource type, but usually a Require is missing.'
            Fix         = 'Add a Require describing a compliant resource, or, to deny the type outright, keep it as it is.'
        }
        @{
            Code        = 'BYL3042'
            Severity    = 'Error'
            Title       = 'Policy with no conditions'
            Explanation = 'Resource * with no When and no Require would match every resource in scope, which is almost never intended and, with Deny, would block every deployment.'
            Fix         = 'Add a When or Require, or give the policy a resource type.'
        }
        @{
            Code        = 'BYL3050'
            Severity    = 'Error'
            Title       = 'Too many field counts on one array'
            Explanation = 'Azure allows at most 5 field count expressions on the same array in a rule. Each Each and Count on that array is one.'
            Fix         = 'Combine the Each blocks for the array into one, with several statements inside.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL3051'
            Severity    = 'Error'
            Title       = 'Rule too large'
            Explanation = 'Azure allows at most 4096 condition expressions in a rule''s if. This usually comes from a loop that generates many requirements.'
            Fix         = 'Split the policy into several, for example one per group of settings, and put them in an initiative.'
        }
        @{
            Code        = 'BYL3052'
            Severity    = 'Error'
            Title       = 'Too many value counts'
            Explanation = 'Azure allows at most 10 value counts (Count -Value) in a rule.'
            Fix         = 'Combine counts over the same list, or split the policy.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL3053'
            Severity    = 'Error'
            Title       = 'Value count iterates too many times'
            Explanation = 'Azure allows a value count at most 100 iterations, with nested counts multiplied. A literal list that long, or nested lists that multiply to it, exceeds that.'
            Fix         = 'Count a shorter list, or pass the list as a parameter, which Azure evaluates at assignment time.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL3060'
            Severity    = 'Error'
            Title       = 'Role not found'
            Explanation = 'A -Role name isn''t a built-in role in the role map, so Bylaw can''t turn it into a role definition ID. The message suggests the closest name.'
            Fix         = 'Correct the role name, give a custom role by its GUID or full role definition ID, or refresh the role map with Update-BylawRoleCache.'
            Adr         = '0022'
        }
        @{
            Code        = 'BYL3061'
            Severity    = 'Error'
            Title       = 'Role given twice'
            Explanation = 'Two -Role values resolve to the same role, for example its name and its GUID.'
            Fix         = 'Give each role once.'
            Adr         = '0022'
        }
        @{
            Code        = 'BYL3062'
            Severity    = 'Error'
            Title       = 'Modify effect parameter allows an effect Modify can''t use'
            Explanation = 'The effect parameter of a Modify policy can allow Modify, Audit and Disabled. A Modify policy changes the request, so it never denies it.'
            Fix         = 'Remove the other values from -AllowedValues.'
            Example     = @'
Parameter Effect -AllowedValues Modify, Audit, Disabled -Default Modify
'@
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3063'
            Severity    = 'Error'
            Title       = 'Remove on something other than a tag'
            Explanation = 'Azure''s Modify can only remove tags.'
            Fix         = 'Use AddOrReplace to change the field instead.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3064'
            Severity    = 'Error'
            Title       = 'Field Modify can''t change'
            Explanation = 'Modify can change tags, identity.type and aliases that Azure marks as modifiable. The field is none of those, according to the alias snapshot.'
            Fix         = 'Change a modifiable alias instead, use Append to add the value on create, or use DeployIfNotExists.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3065'
            Severity    = 'Error'
            Title       = 'identity.type on an unsupported type'
            Explanation = 'Azure''s Modify can only change identity.type on virtual machines and virtual machine scale sets, and skips the operation on other types, so the policy would do nothing.'
            Fix         = 'Scope the policy to Microsoft.Compute/virtualMachines or virtualMachineScaleSets, or remove the operation.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3066'
            Severity    = 'Error'
            Title       = 'Modify on array elements'
            Explanation = 'Azure doesn''t document modifying array elements through a [*] alias.'
            Fix         = 'Modify the whole array alias, with the complete value.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3067'
            Severity    = 'Error'
            Title       = 'Field changed twice'
            Explanation = 'Two Modify operations change the same field, and Azure would apply them in an order you can''t rely on.'
            Fix         = 'Use one operation per field.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3068'
            Severity    = 'Error'
            Title       = 'Unsupported function in -Condition'
            Explanation = 'A Modify operation''s condition can''t use the field(), resourceGroup() or subscription() functions, which Azure doesn''t support there.'
            Fix         = 'Use other policy functions, such as parameters() or requestContext(), or move the condition into When.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3069'
            Severity    = 'Warning'
            Title       = 'Tag modified with Mode All'
            Explanation = 'Azure recommends Mode = ''Indexed'' for Modify policies on tags, so resource types that don''t support tags aren''t evaluated. The exception is a policy on resource groups.'
            Fix         = 'Add Mode = ''Indexed'' to Properties, unless the policy targets resource groups.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3070'
            Severity    = 'Warning'
            Title       = 'Modified field not checked'
            Explanation = 'Modify changes the field, but no Require checks it. Azure only remediates non-compliant resources, so the change would never be triggered by that field, and a remediated resource could still be non-compliant.'
            Fix         = 'Add a Require that checks the field has the value Modify sets.'
            Example     = @'
Modify -Role 'Tag Contributor' {
    Tag Environment | AddOrReplace 'Production'
}
Resource * {
    Require 'Environment is Production' {
        Tag Environment | Must -Be 'Production'
    }
}
'@
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3071'
            Severity    = 'Warning'
            Title       = 'Alias modified without -ConflictEffect Audit'
            Explanation = 'An alias can be modifiable in some API versions and not others. Azure recommends -ConflictEffect Audit when Modify changes aliases, so requests using other API versions are audited rather than denied.'
            Fix         = 'Add -ConflictEffect Audit to Modify.'
            Adr         = '0024'
        }
        @{
            Code        = 'BYL3072'
            Severity    = 'Error'
            Title       = 'Effect parameter allows an effect the policy can''t use'
            Explanation = 'The effect parameter of an Append, DenyAction, Manual, AuditIfNotExists or DeployIfNotExists policy allows an effect that kind of policy can''t use. The message lists the ones it can.'
            Fix         = 'Remove the other values from -AllowedValues.'
            Adr         = '0017'
        }
        @{
            Code        = 'BYL3073'
            Severity    = 'Error'
            Title       = '-CascadeBehavior needs Mode Indexed'
            Explanation = 'Azure only supports DenyAction''s cascade behavior in policies with Mode = ''Indexed''.'
            Fix         = 'Add Mode = ''Indexed'' to Properties, or remove -CascadeBehavior.'
            Adr         = '0028'
        }
        @{
            Code        = 'BYL3074'
            Severity    = 'Warning'
            Title       = 'DenyAction on a type it never applies to'
            Explanation = 'Azure''s denyAction never applies to some resource types: policy assignments, deny assignments, blueprint assignments, deployment stacks, subscriptions and locks. A DenyAction policy on one of them has no effect.'
            Fix         = 'Scope the policy to the resources you want to protect.'
            Adr         = '0028'
        }
        @{
            Code        = 'BYL3080'
            Severity    = 'Error'
            Title       = '[*] in the middle of an Append path'
            Explanation = 'Append can only use [*] at the end of a path, to add an element to an array.'
            Fix         = 'Add to the outer array, with the element as a hashtable.'
            Example     = @'
Append {
    Field 'networkAcls.ipRules[*]' | Add @{ value = '203.0.113.0/24'; action = 'Allow' }
}
'@
            Adr         = '0029'
        }
        @{
            Code        = 'BYL3081'
            Severity    = 'Error'
            Title       = 'Field added twice'
            Explanation = 'Two Add operations add to the same field.'
            Fix         = 'Use one Add per field. To add several array elements, add an array.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL3082'
            Severity    = 'Warning'
            Title       = 'Tag added with Append'
            Explanation = 'Azure recommends Modify for tags: it can also remediate existing resources, and Append can''t.'
            Fix         = 'Use Modify -Role ''Tag Contributor'' { Tag ... | Add ... } instead.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL3083'
            Severity    = 'Warning'
            Title       = 'Appended field not checked'
            Explanation = 'Append adds the field, but no Require checks it, so existing resources are reported as non-compliant whatever their value.'
            Fix         = 'Add a Require that checks the field has the value Append adds.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL3090'
            Severity    = 'Error'
            Title       = 'IfNotExists on the resource itself needs its name'
            Explanation = 'When -Type is the Resource type, the effect checks the resource being evaluated, so -Name must be that resource''s own name.'
            Fix         = 'Use -Name (Arm "[field(''name'')]"), or (Arm "[field(''fullName'')]") for a child resource.'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL3091'
            Severity    = 'Warning'
            Title       = 'AuditIfNotExists on the resource itself'
            Explanation = 'AuditIfNotExists checks the resource being evaluated, not a related one. Learn suggests the Audit effect for this, which is simpler and evaluated straight away.'
            Fix         = 'Use Effect Audit, with the existence condition as a Require block.'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL3092'
            Severity    = 'Warning'
            Title       = 'Option ignored for a child resource'
            Explanation = 'The related type is a child of the Resource type, and Azure only looks for child resources under the evaluated resource, so -ResourceGroupName or -ExistenceScope has no effect.'
            Fix         = 'Remove the option.'
            Adr         = '0030'
        }
        @{
            Code        = 'BYL3093'
            Severity    = 'Error'
            Title       = 'Value passed to a template parameter that doesn''t exist'
            Explanation = 'Deployment -Parameters passes a name the template doesn''t declare, so the deployment would fail when a remediation task runs. The message lists the template''s parameters.'
            Fix         = 'Correct the name, or add the parameter to the template.'
            Adr         = '0031'
        }
        @{
            Code        = 'BYL3094'
            Severity    = 'Error'
            Title       = 'Required template parameter not passed'
            Explanation = 'The template has a parameter with no defaultValue, and Deployment doesn''t pass it, so the deployment would fail.'
            Fix         = 'Pass it in -Parameters, or give it a defaultValue in the template.'
            Adr         = '0031'
        }
        @{
            Code        = 'BYL3100'
            Severity    = 'Error'
            Title       = 'Count compared with something other than a whole number'
            Explanation = 'A count is a whole number, so it is compared with whole numbers: a literal, an Integer parameter, an Array parameter for -BeIn, or Arm.'
            Fix         = 'Compare with a number, or declare the parameter as an Integer.'
            Example     = @'
Count securityRules[*] | Must -BeLessOrEqual (Param MaxRules)
'@
            Adr         = '0032'
        }
        @{
            Code        = 'BYL3101'
            Severity    = 'Error'
            Title       = 'Count -Value with a parameter that isn''t an Array'
            Explanation = 'A value count goes through the members of a list, so its parameter must be an Array.'
            Fix         = 'Declare the parameter with -Type Array.'
            Adr         = '0032'
        }
        @{
            Code        = 'BYL3110'
            Severity    = 'Error'
            Title       = 'Reference ID used twice'
            Explanation = 'Each member of an initiative needs its own reference ID, ignoring case. A policy can be a member more than once, with different reference IDs.'
            Fix         = 'Give each member its own -ReferenceId.'
            Example     = @'
PolicyDefinition 'tags-inherit-from-resource-group' -ReferenceId 'inherit-cost-center' -Parameters @{ tagName = 'CostCenter' }
PolicyDefinition 'tags-inherit-from-resource-group' -ReferenceId 'inherit-owner' -Parameters @{ tagName = 'Owner' }
'@
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3111'
            Severity    = 'Error'
            Title       = 'Invalid PolicyDefinition -Id'
            Explanation = '-Id must be a policy definition ID: /providers/Microsoft.Authorization/policyDefinitions/<name>, optionally after a management group or subscription, or a built-in policy''s GUID on its own. An initiative can''t include another initiative.'
            Fix         = 'Correct the ID. To use an initiative''s policies, include them one by one.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3112'
            Severity    = 'Error'
            Title       = 'Definition group declared twice'
            Explanation = 'Each DefinitionGroup name can be declared once in an initiative.'
            Fix         = 'Remove the second declaration, or rename it.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3113'
            Severity    = 'Error'
            Title       = 'Member in an undeclared group'
            Explanation = 'A PolicyDefinition -Group names a group that no DefinitionGroup declares, which Azure rejects.'
            Fix         = 'Declare the group with DefinitionGroup, or correct the name.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3114'
            Severity    = 'Error'
            Title       = 'Definition group with no members'
            Explanation = 'A DefinitionGroup isn''t used by any PolicyDefinition -Group.'
            Fix         = 'Add the group to the members that belong to it, or remove it.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3115'
            Severity    = 'Error'
            Title       = 'Initiative too large'
            Explanation = 'Azure allows an initiative at most 1000 members and 400 parameters.'
            Fix         = 'Split the initiative into several.'
            Adr         = '0033'
        }
        @{
            Code        = 'BYL3120'
            Severity    = 'Error'
            Title       = 'Member policy not in the build'
            Explanation = 'A PolicyDefinition by name must be a policy in this build, so its parameters can be checked and EPAC can resolve it. The message suggests the closest name.'
            Fix         = 'Correct the name, add the policy to the build, or include a policy defined elsewhere with PolicyDefinition -Id.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3121'
            Severity    = 'Error'
            Title       = 'Value passed to a parameter the policy doesn''t have'
            Explanation = 'A member''s -Parameters passes a name that isn''t one of the policy''s parameters, as the policy is emitted. The message lists them.'
            Fix         = 'Use the parameter''s JSON name, which starts with a lower-case letter, e.g. effect, or remove the value.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3122'
            Severity    = 'Error'
            Title       = 'Required policy parameter not passed'
            Explanation = 'The policy has a parameter with no default, and the member doesn''t pass it, so an assignment of the initiative would fail.'
            Fix         = 'Pass it in -Parameters, as a value or an initiative parameter, or give it a default in the policy.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3123'
            Severity    = 'Error'
            Title       = 'Passed value doesn''t fit the parameter'
            Explanation = 'A literal passed to a member is of the wrong type for the policy''s parameter, or isn''t one of its allowed values.'
            Fix         = 'Pass a value of the parameter''s type, from its allowed values.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3124'
            Severity    = 'Error'
            Title       = 'Initiative parameter of the wrong type'
            Explanation = 'An initiative parameter passed to a member is of a different type from the policy''s parameter.'
            Fix         = 'Declare the initiative parameter with the same type as the policy''s.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3125'
            Severity    = 'Error'
            Title       = 'Initiative parameter allows values the policy doesn''t'
            Explanation = 'An initiative parameter passed to a member has a default, or allowed values, that the policy''s parameter doesn''t allow, so an assignment could pass a value the policy rejects.'
            Fix         = 'Limit the initiative parameter''s -AllowedValues and default to values the policy allows.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3126'
            Severity    = 'Error'
            Title       = '-Version doesn''t match the policy'
            Explanation = 'A member''s -Version asks for a version the policy in this build isn''t, or the policy has no Version, so the assignment would use a version this build doesn''t produce.'
            Fix         = 'Make -Version match the policy''s Version, e.g. ''1.*.*'' for 1.2.0, or remove it.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3127'
            Severity    = 'Warning'
            Title       = 'Member name differs from the policy''s in case'
            Explanation = 'Azure ignores case in names, but tools such as EPAC may match them exactly, and the member is emitted as written.'
            Fix         = 'Write the name exactly as the Policy declares it.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3128'
            Severity    = 'Warning'
            Title       = 'Initiative parameter allows any value'
            Explanation = 'An initiative parameter with no allowed values is passed to a policy parameter that has some, so an assignment could pass a value the policy rejects.'
            Fix         = 'Give the initiative parameter -AllowedValues within the policy''s.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3129'
            Severity    = 'Warning'
            Title       = '-Version on a member from the build'
            Explanation = 'Azure matches definitionVersion against a definition''s top-level version property, which Bylaw doesn''t emit while custom versioning is in preview: Version goes to metadata.version. Azure gives such a definition version 1.0.0, so a pin such as 1.2.* may not select the version you expect.'
            Fix         = 'Remove -Version from members in this build, unless the pin is 1.*.*.'
            Adr         = '0034'
        }
        @{
            Code        = 'BYL3130'
            Severity    = 'Error'
            Title       = 'Invalid Param -Length'
            Explanation = 'Param -Length is Azure''s length() of a parameter, which takes an Array, String or Object, and it is a whole number, so it is tested with -Be or a comparison.'
            Fix         = 'Use -Length on an Array, String or Object parameter, and compare it with -Be, -BeIn or a comparison operator.'
            Example     = @'
Count -Value (Param NamePatterns) -Name pattern -Where { Field name | Must -BeLike (Current pattern) } | Must -Be (Param NamePatterns -Length)
'@
            Adr         = '0020'
        }
    )
}
