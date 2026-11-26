#Requires -Version 7.2

# Development loader. The release build (build/build.ps1 -Task Package) merges the source files,
# in the same load order, into one Bylaw.Module.ps1 for faster import (ADR-0014).
#
# Load order matters: IR classes first (classes that reference each other must be defined before
# use), then the remaining private code, then public commands.
#
# Files are parsed afresh on every import, never dot-sourced (ADR-0006). PowerShell caches
# dot-sourced scripts per process and shares them between runspaces, which would make every
# runspace use the classes of whichever import defined them first. Those classes run their
# methods in that runspace, which Build-Bylaw disposes after each file. The cache is also
# flushed when it fills up, leaving some cached functions bound to an earlier import's classes
# ('Cannot convert BylawPolicy to BylawPolicy').

Set-StrictMode -Version Latest

$loadOrder = @(
    'Private/IR'
    'Private/Compiler'
    'Private/Emitters'
    'Private/Keywords'
    'Private'
    'Public'
)

foreach ($folder in $loadOrder) {
    $folderPath = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $folderPath)) {
        continue
    }
    $files = Get-ChildItem -Path $folderPath -Filter '*.ps1' -File |
        Sort-Object -Property Name -Culture ([cultureinfo]::InvariantCulture)
    foreach ($file in $files) {
        # Parsed afresh on every import instead of dot-sourced (ADR-0006).
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)
        if ($parseErrors) {
            throw "$($file.FullName): $($parseErrors[0])"
        }
        . $ast.GetScriptBlock()
    }
}
