# Diagnostics catalogue (ADR-0037): BYL2xxx, reported while field names are resolved to Azure Policy
# aliases, and when the alias snapshot or role map is loaded. Example is the corrected code.
@{
    Range       = 'BYL2xxx'
    Title       = 'Aliases'
    Description = 'Reported while field names are resolved to Azure Policy aliases, using the bundled alias snapshot or one refreshed with Update-BylawAliasCache, and when the alias snapshot or role map is loaded.'
    Diagnostics = @(
        @{
            Code        = 'BYL2001'
            Severity    = 'Error'
            Title       = 'Alias not in the snapshot'
            Explanation = 'Azure Policy only evaluates fields through aliases, and an alias that doesn''t exist is silently never matched, so the policy would never find a violation. Bylaw checks every field against its alias snapshot. The message suggests the closest alias of the resource type.'
            Fix         = 'Correct the field name. If the alias is newer than the snapshot, refresh it with Update-BylawAliasCache, or use Field <name> -AllowUnknownAlias (or Build-Bylaw -AllowUnknownAlias) to accept it with a warning.'
            Adr         = '0008'
        }
        @{
            Code        = 'BYL2002'
            Severity    = 'Error'
            Title       = 'Field matches more than one alias'
            Explanation = 'A short field name is resolved by matching the end of the resource type''s aliases, and this one matched several, for example two properties with the same name in different places. Bylaw doesn''t guess which one you meant.'
            Fix         = 'Use the full alias, or enough of its path to match only one. The message lists the candidates.'
            Example     = @'
Field 'Microsoft.Storage/storageAccounts/networkAcls.defaultAction' | Must -Be 'Deny'
'@
        }
        @{
            Code        = 'BYL2003'
            Severity    = 'Error'
            Title       = 'Resource type not in the snapshot'
            Explanation = 'The Resource type, or the -Type of AuditIfNotExists or DeployIfNotExists, isn''t in the alias snapshot, so its fields can''t be resolved. It is usually misspelled, or newer than the snapshot. With -AllowUnknownAlias it is a warning instead, and fields must then be written as full aliases.'
            Fix         = 'Check the type''s spelling and case, refresh the snapshot with Update-BylawAliasCache, or use -AllowUnknownAlias.'
            Adr         = '0008'
        }
        @{
            Code        = 'BYL2004'
            Severity    = 'Error'
            Title       = 'Short field name under Resource *'
            Explanation = 'Under Resource * there is no resource type to resolve a short name against, so a field must be a reserved field, such as location or tags, or a full alias.'
            Fix         = 'Write the full alias, or give the policy a resource type.'
            Example     = @'
Resource * {
    Require 'An allowed location' {
        Field location | Must -BeIn (Param AllowedLocations)
    }
}
'@
        }
        @{
            Code        = 'BYL2005'
            Severity    = 'Error'
            Title       = 'Array field with [*] outside Each'
            Explanation = 'Azure evaluates a condition on a field with [*] for every element of the array, so negating it doesn''t give the opposite condition, and Bylaw couldn''t invert it correctly in Require.'
            Fix         = 'Wrap it in Each, which says every element must meet the condition, or count the elements with Count -Where. For an array inside an array, nest one Each or Count per level.'
            Example     = @'
Each networkAcls.ipRules[*] {
    Field value | Must -Not -Be '0.0.0.0/0'
}
'@
            Adr         = '0032'
        }
        @{
            Code        = 'BYL2006'
            Severity    = 'Warning'
            Title       = 'Unknown alias used because of -AllowUnknownAlias'
            Explanation = 'The field isn''t in the alias snapshot, but -AllowUnknownAlias is set, so Bylaw uses it as written. If the alias doesn''t exist in Azure, the policy will never find a violation.'
            Fix         = 'Check the alias in Azure, for example with Get-AzPolicyAlias, then refresh the snapshot with Update-BylawAliasCache so the warning goes away.'
            Adr         = '0008'
        }
        @{
            Code        = 'BYL2010'
            Severity    = 'Error'
            Title       = 'Alias snapshot can''t be read'
            Explanation = 'The alias snapshot set with -AliasCachePath or aliasCache in bylaw.json wasn''t found, isn''t valid JSON, or isn''t a Bylaw alias snapshot. The build stops, because no field could be checked.'
            Fix         = 'Check the path, which is relative to bylaw.json, or regenerate the file with Update-BylawAliasCache. Leave the setting out to use the bundled snapshot.'
            Adr         = '0008'
        }
        @{
            Code        = 'BYL2020'
            Severity    = 'Error'
            Title       = 'Role map can''t be read'
            Explanation = 'The role map set with -RoleCachePath or roleCache in bylaw.json wasn''t found, isn''t valid JSON, isn''t a Bylaw role map, or has a role whose ID isn''t a GUID. Modify and DeployIfNotExists need it to turn role names into IDs.'
            Fix         = 'Check the path, which is relative to bylaw.json, or regenerate the file with Update-BylawRoleCache. Leave the setting out to use the bundled role map.'
            Adr         = '0022'
        }
    )
}
