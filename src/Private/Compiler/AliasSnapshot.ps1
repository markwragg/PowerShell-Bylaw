# Alias snapshot loading and location (ADR-0008).

$script:BylawAliasSnapshotSchemaVersion = 1
$script:BylawAliasSnapshotCache = @{}
$script:BylawAliasSnapshotDataCache = @{}

function Get-BylawUserAliasCachePath {
    Join-Path -Path $HOME -ChildPath '.bylaw/aliases.json'
}

function Get-BylawBundledAliasSnapshotPath {
    Join-Path -Path $ExecutionContext.SessionState.Module.ModuleBase -ChildPath 'Data/aliases.json'
}

function Resolve-BylawAliasSnapshotPath {
    # First match wins: -AliasCachePath, bylaw.json 'aliasCache', the user cache, the bundled file.
    # An explicitly given path that does not exist is an error rather than a silent fallback.
    param(
        [string] $AliasCachePath,
        [string] $SettingsAliasCache
    )
    foreach ($explicit in @(
            @{ Path = $AliasCachePath; Source = '-AliasCachePath' }
            @{ Path = $SettingsAliasCache; Source = "bylaw.json 'aliasCache'" }
        )) {
        if ($explicit.Path) {
            if (-not (Test-Path -LiteralPath $explicit.Path -PathType Leaf)) {
                throw [System.IO.FileNotFoundException]::new("BYL2010: Alias snapshot '$($explicit.Path)' from $($explicit.Source) was not found.")
            }
            return (Resolve-Path -LiteralPath $explicit.Path).ProviderPath
        }
    }
    $userCache = Get-BylawUserAliasCachePath
    if (Test-Path -LiteralPath $userCache -PathType Leaf) {
        return $userCache
    }
    Get-BylawBundledAliasSnapshotPath
}

function Get-BylawAliasSnapshot {
    # Loads and caches a snapshot file. The cache is keyed on path and last write time, so a
    # refreshed file is picked up without restarting the session.
    param([Parameter(Mandatory)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw [System.IO.FileNotFoundException]::new("BYL2010: Alias snapshot '$fullPath' was not found.")
    }
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($fullPath).Ticks
    $cached = $script:BylawAliasSnapshotCache[$fullPath]
    if ($cached -and $cached.Stamp -eq $stamp) {
        return $cached.Snapshot
    }

    $snapshot = New-BylawAliasSnapshot -Data (Read-BylawAliasSnapshotData -Path $fullPath)
    $script:BylawAliasSnapshotCache[$fullPath] = @{ Stamp = $stamp; Snapshot = $snapshot }
    $snapshot
}

function Read-BylawAliasSnapshotData {
    # Parses and checks a snapshot file. Returns plain data (no Bylaw classes), so Build-Bylaw can
    # read the file once and hand it to every file's runspace (ADR-0014):
    #   @{ Path; GeneratedAt; Types = Dictionary[type name -> alias names] }
    # Only alias names are kept; walking the JSON directly is much faster than converting it all.
    # Cached on path and last write time.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw [System.IO.FileNotFoundException]::new("BYL2010: Alias snapshot '$fullPath' was not found.")
    }
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($fullPath).Ticks
    $cached = $script:BylawAliasSnapshotDataCache[$fullPath]
    if ($cached -and $cached.Stamp -eq $stamp) {
        return $cached.Data
    }

    $notSnapshot = "BYL2010: Alias snapshot '$fullPath' is not a Bylaw alias snapshot (expected schemaVersion $($script:BylawAliasSnapshotSchemaVersion) and a 'types' object). Regenerate it with Update-BylawAliasCache."
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($fullPath))
    }
    catch {
        throw [System.IO.InvalidDataException]::new("BYL2010: Alias snapshot '$fullPath' is not valid JSON: $($_.Exception.Message)")
    }
    try {
        $root = $document.RootElement
        # TryGetProperty's out parameter needs JsonElement variables, not $null.
        $schemaVersion = [System.Text.Json.JsonElement]::new()
        $typesElement = [System.Text.Json.JsonElement]::new()
        $generatedAt = [System.Text.Json.JsonElement]::new()
        $version = 0
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object -or
            -not $root.TryGetProperty('schemaVersion', [ref] $schemaVersion) -or
            $schemaVersion.ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or
            -not $schemaVersion.TryGetInt32([ref] $version) -or
            $version -ne $script:BylawAliasSnapshotSchemaVersion -or
            -not $root.TryGetProperty('types', [ref] $typesElement) -or
            $typesElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw [System.IO.InvalidDataException]::new($notSnapshot)
        }
        $generated = ''
        if ($root.TryGetProperty('generatedAt', [ref] $generatedAt) -and $generatedAt.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
            $generated = $generatedAt.GetString()
        }

        $types = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::Ordinal)
        foreach ($type in $typesElement.EnumerateObject()) {
            $names = [System.Collections.Generic.List[string]]::new()
            $aliases = [System.Text.Json.JsonElement]::new()
            if ($type.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Object -and
                $type.Value.TryGetProperty('aliases', [ref] $aliases) -and
                $aliases.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                foreach ($alias in $aliases.EnumerateObject()) {
                    $names.Add($alias.Name)
                }
            }
            $types[$type.Name] = $names.ToArray()
        }
    }
    finally {
        $document.Dispose()
    }

    $data = @{ Path = $fullPath; GeneratedAt = $generated; Types = $types }
    $script:BylawAliasSnapshotDataCache[$fullPath] = @{ Stamp = $stamp; Data = $data }
    $data
}
function New-BylawAliasSnapshot {
    # A snapshot object from Read-BylawAliasSnapshotData output. The data is only read, never
    # changed, so several runspaces can share it one after another.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object only.')]
    [CmdletBinding()]
    [OutputType([BylawAliasSnapshot])]
    param([Parameter(Mandatory)] [hashtable] $Data)

    [BylawAliasSnapshot]::new($Data.Path, $Data.GeneratedAt, $Data.Types)
}
