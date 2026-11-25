# Shared helpers for Bylaw tests. Dot-source from BeforeAll.

function Invoke-BylawTestScript {
    # Writes a .bylaw.ps1 file to TestDrive, runs it as an author would (from outside the module),
    # and returns the policies and diagnostics collected by the front-end.
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $FileName = 'test.bylaw.ps1'
    )
    $path = Join-Path $TestDrive $FileName
    Set-Content -Path $path -Value $Script -Encoding utf8NoBOM
    InModuleScope Bylaw { Reset-BylawFrontEnd }
    $thrown = $null
    try {
        $null = & $path
    }
    catch {
        $thrown = $_
    }
    InModuleScope Bylaw -Parameters @{ Path = $path; Thrown = $thrown } {
        param($Path, $Thrown)
        [pscustomobject]@{
            Path        = $Path
            Policies    = @(Get-BylawCollectedPolicy)
            Diagnostics = @(Get-BylawFrontEndDiagnostic)
            Codes       = @(Get-BylawFrontEndDiagnostic | ForEach-Object Code)
            Thrown      = $Thrown
        }
    }
}

function Format-BylawTestPolicy {
    # Wraps requirement/When text in a minimal valid policy, so tests can focus on one keyword.
    param(
        [string] $Requirements = "Require 'r' { Field publicNetworkAccess | Must -Be 'Disabled' }",
        [string] $Extra = '',
        [string] $Type = 'Microsoft.Storage/storageAccounts'
    )
    @"
Policy 'test-policy' {
    Properties @{ DisplayName = 'Test policy' }
    $Extra
    Resource '$Type' {
        $Requirements
    }
    Effect Deny
}
"@
}
