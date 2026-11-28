# Diagnostics catalogue (ADR-0037): BYL4xxx, reported when a definition is checked against the
# output format, before it is written. Example is the corrected code.
@{
    Range       = 'BYL4xxx'
    Title       = 'Output'
    Description = 'Reported when a policy or initiative is checked against the output format, before anything is written: EPAC''s schema and conventions for -Format Epac, the default, and what plain JSON needs for -Format PlainJson.'
    Diagnostics = @(
        @{
            Code        = 'BYL4001'
            Severity    = 'Error'
            Title       = 'EPAC needs a Category'
            Explanation = 'EPAC''s schema requires metadata.category on every policy and initiative.'
            Fix         = 'Add Category to Properties, or build with -Format PlainJson.'
            Example     = @'
Properties @{
    DisplayName = 'Storage accounts require TLS 1.2'
    Category    = 'Storage'
    Version     = '1.0.0'
}
'@
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4002'
            Severity    = 'Error'
            Title       = 'EPAC needs a Version'
            Explanation = 'EPAC''s schema requires metadata.version on every policy and initiative.'
            Fix         = 'Add Version to Properties, e.g. Version = ''1.0.0''.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4003'
            Severity    = 'Error'
            Title       = 'Effect parameter not named effect'
            Explanation = 'EPAC finds a policy''s effect parameter by its name, effect, to manage effects across assignments.'
            Fix         = 'Name the parameter Effect, or set -JsonName effect.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4004'
            Severity    = 'Error'
            Title       = 'Effect parameter needs a default'
            Explanation = 'EPAC requires the effect parameter to have a default, so an assignment that doesn''t set it still works.'
            Fix         = 'Add -Default, e.g. -Default Audit.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4005'
            Severity    = 'Error'
            Title       = 'Effect parameter needs two effects'
            Explanation = 'EPAC requires the effect parameter to allow at least two different effects. Otherwise it isn''t a choice.'
            Fix         = 'Allow at least two effects, such as the policy''s effect and Disabled, or use a literal effect.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4006'
            Severity    = 'Error'
            Title       = 'Effect parameter display name isn''t Effect'
            Explanation = 'EPAC requires the effect parameter''s display name to be Effect, which Bylaw sets.'
            Fix         = 'Remove -DisplayName from the effect parameter.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4007'
            Severity    = 'Error'
            Title       = 'Literal effect, and a parameter already named effect'
            Explanation = 'With a literal effect, EPAC output gets a generated parameter named effect, so the assignment can still change it. A parameter of yours already has that name.'
            Fix         = 'Use that parameter for the effect: Effect (Param <name>).'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4008'
            Severity    = 'Error'
            Title       = 'Effect from an Arm expression'
            Explanation = 'EPAC requires the effect to be [parameters(''effect'')], so it can be set per assignment. Any other expression can''t be.'
            Fix         = 'Use Effect (Param Effect), or a literal effect.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4009'
            Severity    = 'Warning'
            Title       = 'DateTime parameter'
            Explanation = 'Azure accepts DateTime parameters, but EPAC''s schema doesn''t list the type, so editors that validate against it will flag the file. EPAC still deploys it.'
            Fix         = 'Nothing is needed. To avoid the warning, use a String parameter holding the date.'
            Adr         = '0023'
        }
        @{
            Code        = 'BYL4010'
            Severity    = 'Warning'
            Title       = 'Append details are an array'
            Explanation = 'Azure requires Append''s details to be an array, and EPAC deploys them as written, but EPAC''s schema says details is an object, so editors that validate against it will flag the file.'
            Fix         = 'Nothing is needed: the output is correct for Azure.'
            Adr         = '0029'
        }
        @{
            Code        = 'BYL4011'
            Severity    = 'Error'
            Title       = 'Definition group option EPAC doesn''t allow'
            Explanation = 'EPAC''s schema only allows a name and -AdditionalMetadataId on a definition group, so -DisplayName, -Category and -Description can''t be emitted.'
            Fix         = 'Remove them, put the details in a policyMetadata object and link it with -AdditionalMetadataId, or build with -Format PlainJson.'
            Adr         = '0035'
        }
        @{
            Code        = 'BYL4012'
            Severity    = 'Error'
            Title       = 'Plain JSON needs the definition scope'
            Explanation = 'In plain JSON, an initiative refers to each member by its full ID. For a policy in this build, that includes the scope the policy is deployed at, which Bylaw can''t know.'
            Fix         = 'Pass Build-Bylaw -DefinitionScope with the management group or subscription, or set definitionScope in bylaw.json.'
            Example     = @'
Build-Bylaw ./policies -Format PlainJson -DefinitionScope '/providers/Microsoft.Management/managementGroups/contoso'
'@
            Adr         = '0035'
        }
    )
}
