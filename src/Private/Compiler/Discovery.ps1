# Source discovery and build errors (ADR-0013).

function Find-BylawSourceFile {
    # Source files for -Path: folders are searched recursively for *.bylaw.ps1; files are taken as
    # given. Each file has File (full path), Root (the folder output is mirrored from) and
    # Relative (its path below Root). Files keep the order of -Path, then ordinal order of Relative.
    # Returns @{ Files; Diagnostics }.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string[]] $Path)

    $files = [System.Collections.Generic.List[object]]::new()
    $diagnostics = [System.Collections.Generic.List[BylawDiagnostic]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $Path) {
        $resolved = @(Resolve-Path -Path $item -ErrorAction SilentlyContinue | Where-Object { $_.Provider.Name -eq 'FileSystem' })
        if ($resolved.Count -eq 0) {
            $diagnostics.Add([BylawDiagnostic]::new([BylawSeverity]::Error, 'BYL5040', "Path '$item' was not found.", [BylawSourceLocation]::new($item, 0, 0, $null)))
            continue
        }
        foreach ($entry in $resolved) {
            $full = $entry.ProviderPath
            $candidates = if ([System.IO.Directory]::Exists($full)) {
                $root = $full
                [System.IO.Directory]::EnumerateFiles($full, '*.bylaw.ps1', [System.IO.SearchOption]::AllDirectories) |
                    Where-Object { $_.EndsWith('.bylaw.ps1', [System.StringComparison]::OrdinalIgnoreCase) }
            }
            else {
                $root = [System.IO.Path]::GetDirectoryName($full)
                $full
            }
            $found = foreach ($file in $candidates) {
                [pscustomobject]@{
                    File     = $file
                    Root     = $root
                    Relative = [System.IO.Path]::GetRelativePath($root, $file)
                    SortKey  = [System.IO.Path]::GetRelativePath($root, $file).Replace('\', '/')
                }
            }
            $sorted = [System.Collections.Generic.List[object]]::new()
            foreach ($file in $found) {
                $sorted.Add($file)
            }
            $sorted.Sort([System.Comparison[object]] { param($left, $right) [string]::CompareOrdinal($left.SortKey, $right.SortKey) })
            foreach ($file in $sorted) {
                if ($seen.Add($file.File)) {
                    $files.Add($file)
                }
            }
        }
    }
    @{ Files = $files; Diagnostics = $diagnostics }
}

function New-BylawErrorRecord {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory error record only.')]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter(Mandatory)] [string] $Id,
        [System.Management.Automation.ErrorCategory] $Category = [System.Management.Automation.ErrorCategory]::NotSpecified
    )

    [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new($Message), $Id, $Category, $null)
}

function New-BylawBuildErrorRecord {
    # One error for a failed build, listing every error diagnostic (file:line [Keyword] CODE: message).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory error record only.')]
    param([Parameter(Mandatory)] [BylawDiagnostic[]] $Diagnostics)

    $exception = [BylawCompileException]::new($Diagnostics)
    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'BylawBuildFailed', [System.Management.Automation.ErrorCategory]::InvalidData, $null)
    $count = $Diagnostics.Count
    $noun = if ($count -eq 1) { 'error' } else { 'errors' }
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("Build failed with $count ${noun}:`n$($exception.Message)")
    $record
}
