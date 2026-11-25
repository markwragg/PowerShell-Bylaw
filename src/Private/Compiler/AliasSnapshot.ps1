# Alias snapshot loading and location (ADR-0008).

$script:BylawAliasSnapshotSchemaVersion = 1
$script:BylawAliasSnapshotCache = @{}

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

    try {
        $data = ConvertFrom-BylawJson -Json ([System.IO.File]::ReadAllText($fullPath))
    }
    catch {
        throw [System.IO.InvalidDataException]::new("BYL2010: Alias snapshot '$fullPath' is not valid JSON: $($_.Exception.Message)")
    }
    if ($data -isnot [System.Collections.IDictionary] -or $data['schemaVersion'] -ne $script:BylawAliasSnapshotSchemaVersion -or $data['types'] -isnot [System.Collections.IDictionary]) {
        throw [System.IO.InvalidDataException]::new(
            "BYL2010: Alias snapshot '$fullPath' is not a Bylaw alias snapshot (expected schemaVersion $($script:BylawAliasSnapshotSchemaVersion) and a 'types' object). Regenerate it with Update-BylawAliasCache."
        )
    }

    $snapshot = [BylawAliasSnapshot]::new($fullPath, [string] $data['generatedAt'], $data['types'])
    $script:BylawAliasSnapshotCache[$fullPath] = @{ Stamp = $stamp; Snapshot = $snapshot }
    $snapshot
}
