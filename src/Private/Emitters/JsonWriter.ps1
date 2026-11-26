# Canonical JSON writer (ADR-0009).
#
# Byte-identical output on every OS and PowerShell version: 2-space indent, one key or item per
# line, LF line endings, a single trailing newline, minimal string escaping, invariant numbers.
# Ordered dictionaries and PSCustomObjects keep their order; other dictionaries (hashtables) are
# sorted by ordinal key comparison. Anything that has no stable JSON form is an error.

function ConvertTo-BylawJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject
    )

    $builder = [System.Text.StringBuilder]::new()
    Write-BylawJsonValue -Builder $builder -Value $InputObject -Depth 0
    $null = $builder.Append("`n")
    $builder.ToString()
}

function Write-BylawJsonFile {
    # Writes the canonical JSON for InputObject to Path as UTF-8 without BOM, creating the folder.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowNull()] [object] $InputObject
    )

    $json = ConvertTo-BylawJson -InputObject $InputObject
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($PSCmdlet.ShouldProcess($fullPath, 'Write JSON file')) {
        $folder = [System.IO.Path]::GetDirectoryName($fullPath)
        if ($folder -and -not [System.IO.Directory]::Exists($folder)) {
            $null = [System.IO.Directory]::CreateDirectory($folder)
        }
        [System.IO.File]::WriteAllText($fullPath, $json, [System.Text.UTF8Encoding]::new($false))
    }
}

function Write-BylawJsonValue {
    param(
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [int] $Depth
    )

    if ($Depth -gt 100) {
        throw [System.InvalidOperationException]::new('JSON nesting is deeper than 100 levels; the value may be self-referencing.')
    }

    if ($null -eq $Value) {
        $null = $Builder.Append('null')
        return
    }

    # The -is checks below see through PowerShell's PSObject wrapper, so wrapped values work too.
    if ($Value -is [string] -or $Value -is [char]) {
        Write-BylawJsonString -Builder $Builder -Value ([string] $Value)
        return
    }
    if ($Value -is [bool]) {
        $null = $Builder.Append($(if ($Value) { 'true' } else { 'false' }))
        return
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64] -or
        $Value -is [bigint]) {
        $null = $Builder.Append($Value.ToString([cultureinfo]::InvariantCulture))
        return
    }
    if ($Value -is [double] -or $Value -is [single]) {
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
            throw [System.ArgumentException]::new("'$Value' has no JSON representation.")
        }
        # 'R' gives the shortest string that round-trips on .NET Core 3.0 and later.
        $null = $Builder.Append(([double] $Value).ToString('R', [cultureinfo]::InvariantCulture))
        return
    }
    if ($Value -is [decimal]) {
        $null = $Builder.Append($Value.ToString([cultureinfo]::InvariantCulture))
        return
    }

    # A typed list, so PowerShell never unrolls a single key/value pair into its parts.
    $entries = [System.Collections.Generic.List[object[]]]::new()
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        foreach ($key in $keys) {
            if ($key -isnot [string]) {
                throw [System.ArgumentException]::new("JSON object keys must be strings (found $($key.GetType().Name)).")
            }
        }
        if ($Value -isnot [System.Collections.Specialized.IOrderedDictionary]) {
            $sorted = [string[]] $keys
            [array]::Sort($sorted, [System.StringComparer]::Ordinal)
            $keys = $sorted
        }
        foreach ($key in $keys) {
            $entries.Add([object[]] @($key, $Value[$key]))
        }
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $entries.Add([object[]] @($property.Name, $property.Value))
        }
    }

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        if ($entries.Count -eq 0) {
            $null = $Builder.Append('{}')
            return
        }
        $null = $Builder.Append("{`n")
        $indent = '  ' * ($Depth + 1)
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $null = $Builder.Append($indent)
            Write-BylawJsonString -Builder $Builder -Value $entries[$i][0]
            $null = $Builder.Append(': ')
            Write-BylawJsonValue -Builder $Builder -Value $entries[$i][1] -Depth ($Depth + 1)
            if ($i -lt $entries.Count - 1) {
                $null = $Builder.Append(',')
            }
            $null = $Builder.Append("`n")
        }
        $null = $Builder.Append('  ' * $Depth).Append('}')
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $items.Add($item)
        }
        if ($items.Count -eq 0) {
            $null = $Builder.Append('[]')
            return
        }
        $null = $Builder.Append("[`n")
        $indent = '  ' * ($Depth + 1)
        for ($i = 0; $i -lt $items.Count; $i++) {
            $null = $Builder.Append($indent)
            Write-BylawJsonValue -Builder $Builder -Value $items[$i] -Depth ($Depth + 1)
            if ($i -lt $items.Count - 1) {
                $null = $Builder.Append(',')
            }
            $null = $Builder.Append("`n")
        }
        $null = $Builder.Append('  ' * $Depth).Append(']')
        return
    }

    throw [System.ArgumentException]::new("Values of type [$($Value.GetType().FullName)] have no canonical JSON form.")
}

function Write-BylawJsonString {
    param(
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )

    $null = $Builder.Append('"')
    # Fast path: most strings (alias names, effects) need no escaping.
    if ($Value -notmatch '["\\\x00-\x1f]') {
        $null = $Builder.Append($Value).Append('"')
        return
    }
    # Compare character codes explicitly: PowerShell's switch statement coerces chars in ways that
    # matched [char] 1 against the backspace case.
    foreach ($character in $Value.ToCharArray()) {
        $code = [int] $character
        $escaped = if ($code -eq 0x22) { '\"' }
        elseif ($code -eq 0x5C) { '\\' }
        elseif ($code -eq 0x08) { '\b' }
        elseif ($code -eq 0x0C) { '\f' }
        elseif ($code -eq 0x0A) { '\n' }
        elseif ($code -eq 0x0D) { '\r' }
        elseif ($code -eq 0x09) { '\t' }
        elseif ($code -lt 0x20) { '\u' + $code.ToString('x4', [cultureinfo]::InvariantCulture) }
        else { $null }
        if ($null -ne $escaped) {
            $null = $Builder.Append($escaped)
        }
        else {
            $null = $Builder.Append($character)
        }
    }
    $null = $Builder.Append('"')
}
