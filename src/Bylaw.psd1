@{
    RootModule           = 'Bylaw.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '48713c6a-b8d3-4f37-b1c0-2f988b83a3bc'
    Author               = 'Mark Wragg'
    Copyright            = '(c) 2026 Mark Wragg. MIT licence.'
    Description          = 'A Pester-style PowerShell DSL that compiles desired-state policy descriptions to Azure Policy definition JSON (EPAC-compatible).'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    # Only Policy and the build/utility cmdlets are exported (ADR-0005).
    # Entries are added as each command is implemented.
    FunctionsToExport    = @('Build-Bylaw', 'Policy', 'Update-BylawAliasCache', 'Update-BylawRoleCache')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Azure', 'AzurePolicy', 'Policy', 'DSL', 'EPAC', 'Governance', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://opensource.org/license/mit'
            Prerelease = 'alpha'
        }
    }
}
