# Definition-level objects shared by the definition emitters (ADR-0009 key order, ADR-0016).
#
# Format-specific rules, such as EPAC's effect parameter conventions, belong in the emitter.

function Get-BylawCanonicalMode {
    # 'All' or 'Indexed', from Properties.Mode (validated earlier, ignoring case). Defaults to All.
    param([AllowNull()] [BylawProperties] $Properties)

    if ($null -ne $Properties -and $Properties.Mode -and $Properties.Mode -eq 'Indexed') {
        return 'Indexed'
    }
    'All'
}

function ConvertTo-BylawMetadataObject {
    # metadata: version, category, preview, deprecated, then the author's Metadata keys (ADR-0016).
    param([AllowNull()] [BylawProperties] $Properties)

    $metadata = [ordered]@{}
    if ($null -eq $Properties) {
        return $metadata
    }
    if ($Properties.Version) {
        $metadata['version'] = $Properties.Version
    }
    if ($Properties.Category) {
        $metadata['category'] = $Properties.Category
    }
    if ($null -ne $Properties.Preview) {
        $metadata['preview'] = [bool] $Properties.Preview
    }
    if ($null -ne $Properties.Deprecated) {
        $metadata['deprecated'] = [bool] $Properties.Deprecated
    }
    foreach ($key in (Get-BylawDictionaryKey -Dictionary $Properties.Metadata)) {
        $metadata[$key] = ConvertTo-BylawJsonCompatibleValue -Value $Properties.Metadata[$key]
    }
    $metadata
}

function ConvertTo-BylawParameterObject {
    # One entry of 'parameters': type, metadata (displayName, description, then other keys),
    # allowedValues, defaultValue.
    param(
        [Parameter(Mandatory)] [BylawParameter] $Parameter,
        [string] $DisplayName,
        [string] $Description
    )

    $metadata = [ordered]@{}
    if ($DisplayName) {
        $metadata['displayName'] = $DisplayName
    }
    if ($Description) {
        $metadata['description'] = $Description
    }
    foreach ($key in (Get-BylawDictionaryKey -Dictionary $Parameter.Metadata)) {
        if ($key -in 'displayName', 'description') {
            continue
        }
        $metadata[$key] = ConvertTo-BylawJsonCompatibleValue -Value $Parameter.Metadata[$key]
    }

    $result = [ordered]@{ type = $Parameter.Type }
    if ($metadata.Count -gt 0) {
        $result['metadata'] = $metadata
    }
    if ($null -ne $Parameter.AllowedValues -and $Parameter.AllowedValues.Count -gt 0) {
        $result['allowedValues'] = @($Parameter.AllowedValues | ForEach-Object { ConvertTo-BylawJsonCompatibleValue -Value $_ })
    }
    if ($Parameter.HasDefault) {
        $result['defaultValue'] = ConvertTo-BylawJsonCompatibleValue -Value $Parameter.DefaultValue
    }
    $result
}

function Get-BylawParameterMetadataText {
    # A parameter's displayName or description: the keyword value, else the Metadata entry.
    param([Parameter(Mandatory)] [BylawParameter] $Parameter, [Parameter(Mandatory)] [ValidateSet('displayName', 'description')] [string] $Key)

    $direct = if ($Key -eq 'displayName') { $Parameter.DisplayName } else { $Parameter.Description }
    if ($direct) {
        return $direct
    }
    if ($null -ne $Parameter.Metadata) {
        foreach ($candidate in $Parameter.Metadata.Keys) {
            if ([string] $candidate -eq $Key -and $Parameter.Metadata[$candidate] -is [string]) {
                return $Parameter.Metadata[$candidate]
            }
        }
    }
    ''
}

function Get-BylawGeneratedDisplayName {
    # A display name from a parameter name, in sentence case:
    # AllowedLocations -> 'Allowed locations', TLSVersion -> 'TLS version', max_count -> 'Max count'.
    param([Parameter(Mandatory)] [string] $Name)

    $words = @([regex]::Split($Name, '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|_') | Where-Object { $_ })
    $parts = for ($i = 0; $i -lt $words.Count; $i++) {
        $word = $words[$i]
        if ($word.Length -gt 1 -and $word -cmatch '^[A-Z0-9]+$') {
            $word
        }
        elseif ($i -eq 0) {
            $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1).ToLowerInvariant()
        }
        else {
            $word.ToLowerInvariant()
        }
    }
    $parts -join ' '
}

function Get-BylawDictionaryKey {
    # Keys in emitted order: insertion order for ordered dictionaries, ordinal order otherwise.
    param([AllowNull()] [System.Collections.IDictionary] $Dictionary)

    if ($null -eq $Dictionary -or $Dictionary.Count -eq 0) {
        return
    }
    $keys = [string[]] @($Dictionary.Keys)
    if ($Dictionary -isnot [System.Collections.Specialized.IOrderedDictionary]) {
        [array]::Sort($keys, [System.StringComparer]::Ordinal)
    }
    $keys
}

function ConvertTo-BylawJsonCompatibleValue {
    # Dates as ISO 8601 round-trip strings; everything else as is. Arrays stay arrays.
    param([AllowNull()] [object] $Value)

    if ($Value -is [datetime]) {
        return $Value.ToString('o', [cultureinfo]::InvariantCulture)
    }
    if ($Value -is [System.Array]) {
        return , @($Value | ForEach-Object { ConvertTo-BylawJsonCompatibleValue -Value $_ })
    }
    , $Value
}
