function ConvertTo-BylawValue {
    # Wraps a keyword argument as an IR value. Param and Arm already return BylawValue objects;
    # everything else becomes a literal. Returns $null (after recording a diagnostic) when an array
    # mixes literals with Param/Arm references, which language version 1.0 cannot express.
    param(
        [AllowNull()] [object] $Value,
        [BylawSourceLocation] $Location
    )
    if ($Value -is [BylawCount]) {
        # A count is tested, not compared with (ADR-0032).
        Remove-BylawPendingField -Field $Value
        Add-BylawDiagnostic -Severity Error -Code 'BYL1052' -Location $Location -Message (
            "A count ($Value) can't be used as a value. Pipe it to Must instead, e.g. $Value | Must -BeGreaterThan 0."
        )
        return $null
    }
    if ($Value -is [BylawValue]) {
        return $Value
    }
    if ($Value -is [BylawFieldRef]) {
        # Field and Tag are only consumed by Must; as a value they would be emitted as nonsense.
        Remove-BylawPendingField -Field $Value
        Add-BylawDiagnostic -Severity Error -Code 'BYL1025' -Location $Location -Message (
            "A field ($Value) can't be used as a value. Pipe it to Must instead, or compare two fields with Arm, e.g. Arm `"[field('name')]`"."
        )
        return $null
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) {
        $items = @($Value)
        if (@($items | Where-Object { $_ -is [BylawValue] }).Count -gt 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1020' -Location $Location -Message (
                'An array value cannot mix literals with Param or Arm. Use a single array parameter instead, e.g. (Param AllowedValues).'
            )
            return $null
        }
        if (Test-BylawNestedValue -Value $items) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1020' -Location $Location -Message (
                'A hashtable value cannot contain Param or Arm. Use a parameter of type Object or Array for the whole value instead, e.g. (Param IpRules).'
            )
            return $null
        }
        $literal = [BylawLiteral]::new([object[]] $items)
        $literal.Location = $Location
        return $literal
    }
    if ($Value -is [System.Collections.IDictionary] -and (Test-BylawNestedValue -Value $Value)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1020' -Location $Location -Message (
            'A hashtable value cannot contain Param or Arm. Use a parameter of type Object for the whole value instead, e.g. (Param IpRule).'
        )
        return $null
    }
    $literal = [BylawLiteral]::new($Value)
    $literal.Location = $Location
    $literal
}

function Test-BylawNestedValue {
    # True when a hashtable or array literal contains a Param, Arm or other IR value at any depth.
    param([AllowNull()] [object] $Value)

    if ($Value -is [BylawValue] -or $Value -is [BylawFieldRef]) {
        return $true
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) {
            if (Test-BylawNestedValue -Value $item) {
                return $true
            }
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            if (Test-BylawNestedValue -Value $item) {
                return $true
            }
        }
    }
    $false
}
