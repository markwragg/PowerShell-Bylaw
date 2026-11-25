function Update-BylawAliasCache {
    <#
    .SYNOPSIS
        Refreshes the Azure Policy alias snapshot that Bylaw validates field names against.

    .DESCRIPTION
        Reads alias metadata with Get-AzPolicyAlias (read-only) and writes a Bylaw alias snapshot.
        Requires Az.Resources and a signed-in context (Connect-AzAccount). Compiling policies never
        needs Az; it uses the snapshot offline (ADR-0008).

        By default the snapshot is written to the user cache ($HOME/.bylaw/aliases.json), which
        Build-Bylaw uses in preference to the snapshot bundled with the module.

    .PARAMETER OutputPath
        Where to write the snapshot. Defaults to the user cache.

    .PARAMETER ResourceType
        Only include these resource types, e.g. 'Microsoft.Storage/storageAccounts'.

    .PARAMETER Namespace
        Only include these resource provider namespaces, e.g. 'Microsoft.Storage'.

    .PARAMETER PassThru
        Return a summary object (path, type count, alias count).

    .EXAMPLE
        Connect-AzAccount
        Update-BylawAliasCache

    .EXAMPLE
        Update-BylawAliasCache -ResourceType 'Microsoft.Storage/storageAccounts' -OutputPath ./aliases.json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $OutputPath = (Get-BylawUserAliasCachePath),
        [string[]] $ResourceType,
        [string[]] $Namespace,
        [switch] $PassThru
    )

    Assert-BylawAzContext

    # With no filter, every type is included. Otherwise a type is included when its namespace is in
    # -Namespace or its full name is in -ResourceType.
    $comparer = [System.StringComparer]::OrdinalIgnoreCase
    $wantedTypes = [System.Collections.Generic.HashSet[string]]::new([string[]] @($ResourceType | Where-Object { $_ }), $comparer)
    $wantedNamespaces = [System.Collections.Generic.HashSet[string]]::new([string[]] @($Namespace | Where-Object { $_ }), $comparer)
    $filtered = $wantedTypes.Count -gt 0 -or $wantedNamespaces.Count -gt 0

    $queryNamespaces = [System.Collections.Generic.HashSet[string]]::new($wantedNamespaces, $comparer)
    foreach ($type in $wantedTypes) {
        $null = $queryNamespaces.Add($type.Split('/')[0])
    }
    $providers = if ($filtered) {
        foreach ($name in $queryNamespaces) {
            # NamespaceMatch is a loose match (it also returns e.g. Microsoft.StorageSync for
            # Microsoft.Storage), so the exact filter is applied below.
            Get-BylawAzPolicyAlias -NamespaceMatch $name
        }
    }
    else {
        Get-BylawAzPolicyAlias
    }

    $types = @{}
    $aliasCount = 0
    foreach ($provider in $providers) {
        $typeName = "$($provider.Namespace)/$($provider.ResourceType)"
        if ($filtered -and -not ($wantedNamespaces.Contains($provider.Namespace) -or $wantedTypes.Contains($typeName))) {
            continue
        }
        if (-not $provider.Aliases) {
            continue
        }

        $aliases = @{}
        foreach ($alias in $provider.Aliases) {
            $entry = [ordered]@{}
            $metadata = $alias.DefaultMetadata
            if ($metadata) {
                if ([string] $metadata.Attributes -match 'Modifiable') {
                    $entry['modifiable'] = $true
                }
                $dataType = [string] $metadata.Type
                if ($dataType -and $dataType -ne 'NotSpecified') {
                    $entry['type'] = $dataType
                }
            }
            $aliases[$alias.Name] = $entry
            $aliasCount++
        }
        $types[$typeName] = [ordered]@{ aliases = $aliases }
    }

    if ($types.Count -eq 0) {
        throw [System.InvalidOperationException]::new('Get-AzPolicyAlias returned no aliases for the requested types or namespaces. Nothing was written.')
    }

    $snapshot = [ordered]@{
        schemaVersion = $script:BylawAliasSnapshotSchemaVersion
        generatedAt   = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        types         = $types
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, "Write alias snapshot ($($types.Count) types, $aliasCount aliases)")) {
        Write-BylawJsonFile -Path $OutputPath -InputObject $snapshot -Confirm:$false
        Write-Verbose "Wrote $($types.Count) resource types and $aliasCount aliases to $OutputPath."
    }

    if ($PassThru) {
        [pscustomobject]@{
            Path       = [System.IO.Path]::GetFullPath($OutputPath)
            TypeCount  = $types.Count
            AliasCount = $aliasCount
        }
    }
}
