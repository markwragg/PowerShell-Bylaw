# Built-in role map for Modify -Role (ADR-0022).
#
#   { "schemaVersion": 1, "generatedAt": "...", "roles": { "<role name>": "<role GUID>" } }
#
# The bundled file is a starter set; Update-BylawRoleCache writes the full map. Built-in role GUIDs
# are the same in every tenant, so the map is portable.

$script:BylawRoleMapSchemaVersion = 1
$script:BylawRoleMapDataCache = @{}
$script:BylawRoleDefinitionPrefix = '/providers/Microsoft.Authorization/roleDefinitions/'
$script:BylawGuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-BylawUserRoleCachePath {
    Join-Path -Path $HOME -ChildPath '.bylaw/roles.json'
}

function Get-BylawBundledRoleMapPath {
    Join-Path -Path $ExecutionContext.SessionState.Module.ModuleBase -ChildPath 'Data/roles.json'
}

function Resolve-BylawRoleMapPath {
    # First match wins: -RoleCachePath, bylaw.json 'roleCache', the user cache, the bundled file.
    # An explicitly given path that does not exist is an error rather than a silent fallback.
    param(
        [string] $RoleCachePath,
        [string] $SettingsRoleCache
    )
    foreach ($explicit in @(
            @{ Path = $RoleCachePath; Source = '-RoleCachePath' }
            @{ Path = $SettingsRoleCache; Source = "bylaw.json 'roleCache'" }
        )) {
        if ($explicit.Path) {
            if (-not (Test-Path -LiteralPath $explicit.Path -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new("BYL2020: Role map '$($explicit.Path)' from $($explicit.Source) was not found.")
            }
            return (Resolve-Path -LiteralPath $explicit.Path).ProviderPath
        }
    }
    $userCache = Get-BylawUserRoleCachePath
    if (Test-Path -LiteralPath $userCache -PathType Leaf) {
        return $userCache
    }
    Get-BylawBundledRoleMapPath
}

function Read-BylawRoleMapData {
    # Parses and checks a role map file. Returns plain data (no Bylaw classes), so Build-Bylaw can
    # read the file once and hand it to every file's runspace (ADR-0014):
    #   @{ Path; GeneratedAt; Roles = Dictionary[role name -> GUID], ignoring case }
    # Cached on path and last write time.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw [System.IO.FileNotFoundException]::new("BYL2020: Role map '$fullPath' was not found.")
    }
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($fullPath).Ticks
    $cached = $script:BylawRoleMapDataCache[$fullPath]
    if ($cached -and $cached.Stamp -eq $stamp) {
        return $cached.Data
    }

    $notRoleMap = "BYL2020: Role map '$fullPath' is not a Bylaw role map (expected schemaVersion $($script:BylawRoleMapSchemaVersion) and a 'roles' object of role names and GUIDs). Regenerate it with Update-BylawRoleCache."
    $document = try {
        ConvertFrom-BylawJson -Json ([System.IO.File]::ReadAllText($fullPath))
    }
    catch {
        throw [System.IO.InvalidDataException]::new("BYL2020: Role map '$fullPath' is not valid JSON: $($_.Exception.Message)")
    }
    if ($document -isnot [System.Collections.IDictionary] -or
        $document['schemaVersion'] -ne $script:BylawRoleMapSchemaVersion -or
        $document['roles'] -isnot [System.Collections.IDictionary]) {
        throw [System.IO.InvalidDataException]::new($notRoleMap)
    }

    $roles = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $document['roles'].GetEnumerator()) {
        if ($entry.Value -isnot [string] -or $entry.Value -notmatch "^$($script:BylawGuidPattern)$") {
            throw [System.IO.InvalidDataException]::new("BYL2020: Role map '$fullPath' has role '$($entry.Key)' with '$($entry.Value)', which is not a GUID. Regenerate it with Update-BylawRoleCache.")
        }
        $roles[[string] $entry.Key] = $entry.Value
    }
    $generatedAt = if ($document['generatedAt'] -is [string]) { $document['generatedAt'] } else { '' }

    $data = @{ Path = $fullPath; GeneratedAt = $generatedAt; Roles = $roles }
    $script:BylawRoleMapDataCache[$fullPath] = @{ Stamp = $stamp; Data = $data }
    $data
}

function Resolve-BylawRoleDefinitionId {
    # The full role definition ID for one -Role value (ADR-0022): a full ID as written, a GUID with
    # the prefix added, or a built-in role name looked up in the map, ignoring case.
    # Returns @{ Id; Message }: Id is '' and Message explains why when the role can't be resolved.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Role,
        [Parameter(Mandatory)] [hashtable] $RoleData
    )

    $prefix = $script:BylawRoleDefinitionPrefix
    if ($Role -match "^(?i:$([regex]::Escape($prefix)))$($script:BylawGuidPattern)$") {
        return @{ Id = $Role; Message = $null }
    }
    if ($Role -match "^$($script:BylawGuidPattern)$") {
        return @{ Id = $prefix + $Role; Message = $null }
    }
    $guid = $null
    if ($Role -and $RoleData.Roles.TryGetValue($Role, [ref] $guid)) {
        return @{ Id = $prefix + $guid; Message = $null }
    }

    $hint = ''
    if ($Role -and $RoleData.Roles.Count -gt 0) {
        $closest = Get-BylawClosestMatch -Value $Role -Candidates @($RoleData.Roles.Keys)
        if ($closest) {
            $hint = " Did you mean '$closest'?"
        }
    }
    @{
        Id      = ''
        Message = "Role '$Role' is not a built-in role in the role map ($($RoleData.Path)).$hint Give a custom role by its GUID or full role definition ID, or refresh the map with Update-BylawRoleCache."
    }
}
