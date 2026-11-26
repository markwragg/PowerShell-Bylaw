function Update-BylawRoleCache {
    <#
    .SYNOPSIS
        Refreshes the built-in role map that Modify -Role resolves role names against.

    .DESCRIPTION
        Reads the built-in role definitions with Get-AzRoleDefinition (read-only) and writes a Bylaw
        role map of role names and GUIDs. Custom roles are not included: give them to Modify -Role
        by GUID or full role definition ID. Requires Az.Resources and a signed-in context
        (Connect-AzAccount). Compiling policies never needs Az (ADR-0022).

        Built-in role GUIDs are the same in every tenant, so the map is portable.

        By default the map is written to the user cache ($HOME/.bylaw/roles.json), which Build-Bylaw
        uses in preference to the starter map bundled with the module.

    .PARAMETER OutputPath
        Where to write the role map. Defaults to the user cache.

    .PARAMETER PassThru
        Return a summary object (path, role count).

    .EXAMPLE
        Connect-AzAccount
        Update-BylawRoleCache

    .EXAMPLE
        Update-BylawRoleCache -OutputPath ./roles.json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $OutputPath = (Get-BylawUserRoleCachePath),
        [switch] $PassThru
    )

    Assert-BylawAzContext -Command 'Update-BylawRoleCache'

    $byName = @{}
    foreach ($role in Get-BylawAzBuiltInRole) {
        $name = [string] $role.Name
        $id = [string] $role.Id
        if (-not $name -or $id -notmatch "^$($script:BylawGuidPattern)$") {
            continue
        }
        if ($byName.ContainsKey($name)) {
            Write-Warning "Built-in role name '$name' appears more than once; keeping $($byName[$name]) and skipping $id."
            continue
        }
        $byName[$name] = $id.ToLowerInvariant()
    }
    if ($byName.Count -eq 0) {
        throw [System.InvalidOperationException]::new('Get-AzRoleDefinition returned no built-in roles. Nothing was written.')
    }

    # Sorted by name, so a refresh only shows real changes in a diff.
    $roles = [ordered]@{}
    foreach ($name in ($byName.Keys | Sort-Object -Culture ([cultureinfo]::InvariantCulture))) {
        $roles[$name] = $byName[$name]
    }
    $map = [ordered]@{
        schemaVersion = $script:BylawRoleMapSchemaVersion
        generatedAt   = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        roles         = $roles
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, "Write role map ($($roles.Count) built-in roles)")) {
        Write-BylawJsonFile -Path $OutputPath -InputObject $map -Confirm:$false
        Write-Verbose "Wrote $($roles.Count) built-in roles to $OutputPath."
    }

    if ($PassThru) {
        [pscustomobject]@{
            Path      = [System.IO.Path]::GetFullPath($OutputPath)
            RoleCount = $roles.Count
        }
    }
}
