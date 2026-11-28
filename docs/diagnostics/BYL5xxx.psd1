# Diagnostics catalogue (ADR-0037): BYL5xxx, reported by Build-Bylaw itself: settings, finding and
# running the files, and the build as a whole. Example is the corrected code.
@{
    Range       = 'BYL5xxx'
    Title       = 'Build and settings'
    Description = 'Reported by Build-Bylaw itself: reading bylaw.json and its parameters, finding and running the .bylaw.ps1 files, and checks across the whole build.'
    Diagnostics = @(
        @{
            Code        = 'BYL5001'
            Severity    = 'Error'
            Title       = 'bylaw.json isn''t valid'
            Explanation = 'The settings file isn''t valid JSON, or isn''t a JSON object.'
            Fix         = 'Correct the JSON. The file is an object of settings.'
            Example     = @'
{
  "languageVersion": "1.0",
  "definitionScope": "/providers/Microsoft.Management/managementGroups/contoso"
}
'@
        }
        @{
            Code        = 'BYL5002'
            Severity    = 'Error'
            Title       = 'Unknown setting'
            Explanation = 'bylaw.json has a key Bylaw doesn''t know, so a misspelled setting fails instead of being ignored. The message suggests the closest key.'
            Fix         = 'Use one of languageVersion, aliasCache, roleCache, initiativeOutputPath and definitionScope.'
        }
        @{
            Code        = 'BYL5003'
            Severity    = 'Error'
            Title       = 'Settings file not found'
            Explanation = 'The file given with -Settings doesn''t exist.'
            Fix         = 'Correct the path, or leave -Settings out to use the nearest bylaw.json at or above the -Path folder, if there is one.'
        }
        @{
            Code        = 'BYL5004'
            Severity    = 'Error'
            Title       = 'Unsupported languageVersion'
            Explanation = 'languageVersion pins the language''s behaviour, so upgrading Bylaw doesn''t change existing output. Only the versions this Bylaw knows are accepted, written as a string.'
            Fix         = 'Use a supported version, such as "1.0", in quotes.'
            Adr         = '0012'
        }
        @{
            Code        = 'BYL5005'
            Severity    = 'Error'
            Title       = 'Setting needs a path'
            Explanation = 'aliasCache, roleCache and initiativeOutputPath are paths, relative to bylaw.json, and must be non-empty strings.'
            Fix         = 'Give the setting a path, e.g. "aliasCache": "./aliases.json", or remove it.'
        }
        @{
            Code        = 'BYL5006'
            Severity    = 'Error'
            Title       = 'Invalid definition scope'
            Explanation = '-DefinitionScope and definitionScope are the management group or subscription the build''s policies are deployed at, as a resource ID.'
            Fix         = 'Use /providers/Microsoft.Management/managementGroups/<id> or /subscriptions/<id>.'
            Adr         = '0035'
        }
        @{
            Code        = 'BYL5010'
            Severity    = 'Error'
            Title       = 'The file failed'
            Explanation = 'The .bylaw.ps1 file stopped with an error outside any Policy or Initiative block, for example in code at the top of the file. The message is PowerShell''s own.'
            Fix         = 'Fix the line the message points to, as in any script.'
        }
        @{
            Code        = 'BYL5011'
            Severity    = 'Error'
            Title       = 'The file wrote an error'
            Explanation = 'The .bylaw.ps1 file wrote an error outside any Policy or Initiative block without stopping, for example with Write-Error or a command that failed. The build treats it as an error, so problems aren''t lost.'
            Fix         = 'Fix the cause, or handle the error in the file.'
        }
        @{
            Code        = 'BYL5012'
            Severity    = 'Error'
            Title       = 'The file could not be compiled'
            Explanation = 'The file couldn''t be run at all, for example because it has a syntax error or couldn''t be read.'
            Fix         = 'Open the file in an editor with PowerShell support, which shows syntax errors, and fix them.'
        }
        @{
            Code        = 'BYL5013'
            Severity    = 'Error'
            Title       = 'Param( at the start of a block'
            Explanation = 'PowerShell reads Param( at the start of a scriptblock as a parameter declaration, not as the Param keyword, so the file can''t be parsed.'
            Fix         = 'Write Param Name without brackets, or put the call in parentheses: (Param Name).'
            Example     = @'
Effect (Param Effect)
'@
        }
        @{
            Code        = 'BYL5020'
            Severity    = 'Error'
            Title       = 'Name used twice in the build'
            Explanation = 'Policy and initiative names become definition names and file names, so they must be unique across the build, ignoring case, policies and initiatives together. The message gives the first one.'
            Fix         = 'Rename one of them.'
            Adr         = '0013'
        }
        @{
            Code        = 'BYL5021'
            Severity    = 'Warning'
            Title       = 'File with no definitions'
            Explanation = 'A .bylaw.ps1 file ran without declaring any Policy or Initiative. It may be a helper file, or the blocks may be missing.'
            Fix         = 'Add the definitions, or give a helper file another extension, such as .ps1, and dot-source it.'
            Adr         = '0013'
        }
        @{
            Code        = 'BYL5030'
            Severity    = 'Warning'
            Title       = 'Output file not produced by this build'
            Explanation = 'The output folder has a .json file that this build didn''t write, usually from a policy that has since been renamed or removed. Bylaw never deletes output.'
            Fix         = 'Delete the file if its policy or initiative is gone.'
            Adr         = '0011'
        }
        @{
            Code        = 'BYL5040'
            Severity    = 'Error'
            Title       = 'Path not found'
            Explanation = 'A path given to Build-Bylaw -Path doesn''t exist.'
            Fix         = 'Correct the path. -Path takes files and folders, and folders are searched for *.bylaw.ps1 files.'
            Adr         = '0013'
        }
    )
}
