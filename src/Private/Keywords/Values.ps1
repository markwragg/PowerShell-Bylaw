function ConvertTo-BylawValue {
    # Wraps a keyword argument as an IR value. Param and Expr already return BylawValue objects;
    # everything else becomes a literal. Returns $null (after recording a diagnostic) when an array
    # mixes literals with Param/Expr references, which language version 1.0 cannot express.
    param(
        [AllowNull()] [object] $Value,
        [BylawSourceLocation] $Location
    )
    if ($Value -is [BylawValue]) {
        return $Value
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) {
        $items = @($Value)
        if (@($items | Where-Object { $_ -is [BylawValue] }).Count -gt 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1020' -Location $Location -Message (
                'An array value cannot mix literals with Param or Expr. Use a single array parameter instead, e.g. (Param AllowedValues).'
            )
            return $null
        }
        $literal = [BylawLiteral]::new([object[]] $items)
        $literal.Location = $Location
        return $literal
    }
    $literal = [BylawLiteral]::new($Value)
    $literal.Location = $Location
    $literal
}
