function Properties {
    <#
    .SYNOPSIS
        Policy metadata: DisplayName, Description, Category, Version, Mode, Preview, Deprecated, Metadata.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'DSL keyword (ADR-0005).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Collections.IDictionary] $Values
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Properties')
    $frame = Test-BylawParent -Keyword 'Properties' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawSingleton -Frame $frame -Keyword 'Properties' -Location $location)) {
        return
    }

    $stringKeys = @('DisplayName', 'Description', 'Category', 'Version', 'Mode')
    $booleanKeys = @('Preview', 'Deprecated')
    $validKeys = $stringKeys + $booleanKeys + 'Metadata'

    $properties = [BylawProperties]::new()
    $properties.Location = $location

    foreach ($key in $Values.Keys) {
        $canonical = $validKeys | Where-Object { $_ -eq $key } | Select-Object -First 1
        $value = $Values[$key]
        if (-not $canonical) {
            $suggestion = Get-BylawClosestMatch -Value ([string] $key) -Candidates $validKeys
            $hint = if ($suggestion) { " Did you mean '$suggestion'?" } else { '' }
            Add-BylawDiagnostic -Severity Error -Code 'BYL1011' -Location $location -Message (
                "Unknown Properties key '$key'.$hint Valid keys: $($validKeys -join ', ')."
            )
            continue
        }
        if ($canonical -in $stringKeys) {
            if ($value -isnot [string]) {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1012' -Location $location -Message (
                    "Properties key '$canonical' must be a string."
                )
                continue
            }
            $properties.$canonical = $value
        }
        elseif ($canonical -in $booleanKeys) {
            if ($value -isnot [bool]) {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1012' -Location $location -Message (
                    "Properties key '$canonical' must be `$true or `$false."
                )
                continue
            }
            $properties.$canonical = $value
        }
        else {
            if ($value -isnot [System.Collections.IDictionary]) {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1012' -Location $location -Message (
                    "Properties key 'Metadata' must be a hashtable."
                )
                continue
            }
            $properties.Metadata = $value
        }
    }

    $frame.Node.Properties = $properties
}

function Get-BylawClosestMatch {
    # Closest candidate by edit distance, ignoring case, or $null when nothing is close.
    param(
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [string[]] $Candidates
    )
    $best = $null
    $bestDistance = [int]::MaxValue
    foreach ($candidate in $Candidates) {
        $distance = Get-BylawEditDistance -Left $Value.ToLowerInvariant() -Right $candidate.ToLowerInvariant()
        if ($distance -lt $bestDistance) {
            $best = $candidate
            $bestDistance = $distance
        }
    }
    if ($bestDistance -le [Math]::Max(2, [Math]::Floor($Value.Length / 3))) {
        return $best
    }
    $null
}

function Get-BylawEditDistance {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Left,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Right
    )
    $previous = [int[]] (0..$Right.Length)
    for ($i = 1; $i -le $Left.Length; $i++) {
        $current = [int[]]::new($Right.Length + 1)
        $current[0] = $i
        for ($j = 1; $j -le $Right.Length; $j++) {
            $cost = if ($Left[$i - 1] -eq $Right[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min([Math]::Min($current[$j - 1] + 1, $previous[$j] + 1), $previous[$j - 1] + $cost)
        }
        $previous = $current
    }
    $previous[$Right.Length]
}
