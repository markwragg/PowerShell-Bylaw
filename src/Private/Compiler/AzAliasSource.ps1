# The only code in Bylaw that talks to Azure (ADR-0007): read-only alias metadata for
# Update-BylawAliasCache. Kept behind these two functions so tests can mock them without Az.

function Assert-BylawAzContext {
    # Imports Az.Resources on demand and checks there is a signed-in context.
    try {
        Import-Module -Name Az.Resources -ErrorAction Stop
    }
    catch {
        throw [System.InvalidOperationException]::new(
            "Update-BylawAliasCache needs the Az.Resources module (Install-Module Az.Resources). Compiling policies doesn't. $($_.Exception.Message)"
        )
    }
    $context = Az.Accounts\Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $context) {
        throw [System.InvalidOperationException]::new('Update-BylawAliasCache needs a signed-in Azure context. Run Connect-AzAccount first.')
    }
}

function Get-BylawAzPolicyAlias {
    # Resource provider alias data, as returned by Get-AzPolicyAlias.
    param([string] $NamespaceMatch)

    $query = @{ ErrorAction = 'Stop' }
    if ($NamespaceMatch) {
        $query['NamespaceMatch'] = $NamespaceMatch
    }
    Az.Resources\Get-AzPolicyAlias @query
}
