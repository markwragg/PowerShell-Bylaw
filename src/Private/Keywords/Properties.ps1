function Properties {
    <#
    .SYNOPSIS
        Policy metadata: DisplayName, Description, Category, Version, Mode, Preview, Deprecated, Metadata.

    .DESCRIPTION
        DisplayName, Description, Category, Version and Mode are strings; Preview and Deprecated
        are $true or $false; Metadata is a hashtable of any other metadata. EPAC output needs
        Category and Version. Mode is All (the default) or Indexed. An initiative takes the same
        keys except Mode. Unknown keys fail the build.

    .EXAMPLE
        Properties @{
            DisplayName = 'Storage accounts require TLS 1.2'
            Category    = 'Storage'
            Version     = '1.0.0'
            Mode        = 'Indexed'
        }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'DSL keyword (ADR-0005).')]
    [CmdletBinding()]
    param(
        # The properties, as a hashtable.
        [Parameter(Mandatory, Position = 0)]
        [System.Collections.IDictionary] $Values
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Properties')
    $frame = Test-BylawParent -Keyword 'Properties' -Allowed 'Policy', 'Initiative' -Location $location
    if ($null -eq $frame -or -not (Test-BylawSingleton -Frame $frame -Keyword 'Properties' -Location $location)) {
        return
    }

    # An initiative has no rule, so no Mode: Mode belongs to its member policies (ADR-0033).
    $stringKeys = if ($frame.Keyword -eq 'Initiative') { @('DisplayName', 'Description', 'Category', 'Version') } else { @('DisplayName', 'Description', 'Category', 'Version', 'Mode') }
    $booleanKeys = @('Preview', 'Deprecated')
    $validKeys = $stringKeys + $booleanKeys + 'Metadata'

    $properties = [BylawProperties]::new()
    $properties.Location = $location

    foreach ($key in $Values.Keys) {
        $canonical = $validKeys | Where-Object { $_ -eq $key } | Select-Object -First 1
        $value = $Values[$key]
        if (-not $canonical) {
            $suggestion = Get-BylawClosestMatch -Value ([string] $key) -Candidates $validKeys
            $hint = if ($frame.Keyword -eq 'Initiative' -and $key -eq 'Mode') { " An initiative has no Mode: each member policy has its own." } elseif ($suggestion) { " Did you mean '$suggestion'?" } else { '' }
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
