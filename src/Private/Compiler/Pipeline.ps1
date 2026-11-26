function Invoke-BylawCompilerPass {
    # Runs the compiler passes on one policy from the front-end, in order:
    #   alias resolution -> validation -> inversion + flattening -> Azure limits.
    # Sets Policy.Rule when there are no errors, and returns every diagnostic.
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param(
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [BylawAliasSnapshot] $Snapshot,
        [switch] $AllowUnknownAlias
    )

    if ($null -eq $Policy.Resource -or $null -eq $Policy.Effect) {
        # The front-end already reported the missing block.
        return
    }

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    foreach ($diagnostic in Invoke-BylawAliasResolution -Policy $Policy -Snapshot $Snapshot -AllowUnknownAlias:$AllowUnknownAlias) {
        $diagnostics.Add($diagnostic)
    }
    foreach ($diagnostic in Invoke-BylawValidation -Policy $Policy) {
        $diagnostics.Add($diagnostic)
    }

    if (@($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -eq 0) {
        $Policy.Rule = ConvertTo-BylawPolicyRule -Policy $Policy
        foreach ($diagnostic in Test-BylawRuleLimit -Policy $Policy) {
            $diagnostics.Add($diagnostic)
        }
    }

    foreach ($diagnostic in $diagnostics) {
        $diagnostic
    }
}
