# bylaw.json project settings (ADR-0012).
#
#   { "languageVersion": "1.0", "aliasCache": "./aliases.json", "roleCache": "./roles.json" }
#
# Found with -Settings, else by searching upward from the build path, stopping at the first folder
# that contains .git, or at the filesystem root. aliasCache and roleCache are relative to the
# settings file.

$script:BylawSettingsFileName = 'bylaw.json'
$script:BylawSettingsKeys = @('languageVersion', 'aliasCache', 'roleCache')
$script:BylawSupportedLanguageVersions = @('1.0')

function Find-BylawSettingsFile {
    # The nearest bylaw.json at or above StartPath, or $null.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $StartPath)

    $folder = [System.IO.Path]::GetFullPath($StartPath)
    if (-not [System.IO.Directory]::Exists($folder)) {
        $folder = [System.IO.Path]::GetDirectoryName($folder)
    }
    while ($folder) {
        $candidate = [System.IO.Path]::Combine($folder, $script:BylawSettingsFileName)
        if ([System.IO.File]::Exists($candidate)) {
            return $candidate
        }
        $git = [System.IO.Path]::Combine($folder, '.git')
        if ([System.IO.Directory]::Exists($git) -or [System.IO.File]::Exists($git)) {
            return $null
        }
        $folder = [System.IO.Path]::GetDirectoryName($folder)
    }
    $null
}

function Read-BylawSettingsFile {
    # Settings from a bylaw.json path, or the defaults when Path is empty.
    # Returns @{ Settings = @{ Path; LanguageVersion; AliasCache; RoleCache }; Diagnostics = @(...) }.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string] $Path)

    $settings = @{ Path = $null; LanguageVersion = '1.0'; AliasCache = $null; RoleCache = $null }
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $result = @{ Settings = $settings; Diagnostics = $diagnostics }
    if (-not $Path) {
        return $result
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $location = [BylawSourceLocation]::new($fullPath, 0, 0, $null)
    $add = {
        param([string] $Code, [string] $Message)
        $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Error, $Code, $Message, $location))
    }
    $settings.Path = $fullPath

    if (-not [System.IO.File]::Exists($fullPath)) {
        & $add 'BYL5003' "Settings file '$fullPath' was not found."
        return $result
    }
    $data = $null
    try {
        $data = ConvertFrom-BylawJson -Json ([System.IO.File]::ReadAllText($fullPath))
    }
    catch {
        & $add 'BYL5001' "Settings file is not valid JSON: $($_.Exception.Message)"
        return $result
    }
    if ($data -isnot [System.Collections.IDictionary]) {
        & $add 'BYL5001' 'Settings file must contain a JSON object, e.g. { "languageVersion": "1.0" }.'
        return $result
    }

    foreach ($key in $data.Keys) {
        if ($key -cnotin $script:BylawSettingsKeys) {
            $suggestion = Get-BylawClosestMatch -Value $key -Candidates $script:BylawSettingsKeys
            $hint = if ($suggestion) { " Did you mean '$suggestion'?" } else { '' }
            & $add 'BYL5002' "Unknown settings key '$key'.$hint Valid keys: $($script:BylawSettingsKeys -join ', ')."
        }
    }

    if ($data.Contains('languageVersion')) {
        $version = $data['languageVersion']
        if ($version -isnot [string] -or $version -notin $script:BylawSupportedLanguageVersions) {
            & $add 'BYL5004' "languageVersion '$version' is not supported. Supported versions: $($script:BylawSupportedLanguageVersions -join ', ') (a string, e.g. ""1.0"")."
        }
        else {
            $settings.LanguageVersion = $version
        }
    }

    foreach ($entry in @(
            @{ Key = 'aliasCache'; Setting = 'AliasCache'; What = 'an alias snapshot file' }
            @{ Key = 'roleCache'; Setting = 'RoleCache'; What = 'a role map file' }
        )) {
        if (-not $data.Contains($entry.Key)) {
            continue
        }
        $value = $data[$entry.Key]
        if ($value -isnot [string] -or -not $value) {
            & $add 'BYL5005' "$($entry.Key) must be a path to $($entry.What), relative to bylaw.json."
        }
        else {
            $settings[$entry.Setting] = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($fullPath), $value))
        }
    }
    $result
}
