#Requires -Version 7.2

# Development loader. The release build (build/build.ps1 -Task Package) replaces this file with
# a single merged module, in the same load order, for faster import (ADR-0014).
#
# Load order matters: IR classes first (classes that reference each other must be defined before
# use), then the remaining private code, then public commands.

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
        . $file.FullName
    }
}
