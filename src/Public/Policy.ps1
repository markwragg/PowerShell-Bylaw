function Policy {
    <#
    .SYNOPSIS
        Declares one Azure Policy definition.

    .DESCRIPTION
        The only top-level Bylaw DSL command. The scriptblock describes the compliant state of a
        resource using the inner keywords (Properties, Parameter, Resource, When, Require, Each,
        AnyOf, AllOf, Field, Element, Tag, ResourceGroupTag, Must, Effect, Modify, AddOrReplace,
        Add, Remove, Append, DenyAction, Manual, AuditIfNotExists, DeployIfNotExists, Deployment,
        Count, Current, Param, Arm), which exist only while the block runs.

        Errors inside the block are recorded as diagnostics with file, line and keyword, and are
        reported together by Build-Bylaw.

    .PARAMETER Name
        The definition name. It is the definition's identity and output file name, so renaming it
        creates a new definition. 1 to 64 characters, without < > * % & : \ ? . + / " | or control
        characters, and not starting or ending with a space (ADR-0010).

    .PARAMETER Body
        The policy description.

    .EXAMPLE
        Policy 'storage-deny-public-network-access' {
            Properties @{ DisplayName = 'Storage accounts should disable public network access' }
            Resource 'Microsoft.Storage/storageAccounts' {
                Require 'Public network access is disabled' {
                    Field publicNetworkAccess | Must -Be 'Disabled'
                }
            }
            Effect Deny
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Policy')

    $outer = Get-BylawCurrentFrame
    if ($null -ne $outer) {
        $what = if ($outer.Keyword -eq 'Policy') { 'another Policy' } else { $outer.Keyword }
        Add-BylawDiagnostic -Severity Error -Code 'BYL1003' -Location $location -Message (
            "Policy '$Name' is nested inside $what. Each Policy must be at the top level of the file."
        )
        return
    }

    $policy = [BylawPolicy]::new($Name)
    $policy.Location = $location
    $frame = Enter-BylawFrame -Keyword 'Policy' -Node $policy
    try {
        Invoke-BylawPolicyBody -Body $Body
    }
    catch {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1014' -Location (ConvertTo-BylawLocation -ErrorRecord $_) -Message (
            "Policy '$Name' stopped because of an error: $($_.Exception.Message)"
        )
    }
    finally {
        Exit-BylawFrame -Frame $frame
    }

    # A Resource or Effect that was written but rejected already has its own diagnostic, so only
    # report the ones that are absent from the source.
    if (-not $frame.Singletons.ContainsKey('Resource')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1005' -Location $location -Message (
            "Policy '$Name' has no Resource block. Use Resource '<type>' { ... } or Resource * { ... }."
        )
    }
    if (-not ($script:BylawEffectKeywordNames | Where-Object { $frame.Singletons.ContainsKey($_) })) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1006' -Location $location -Message (
            "Policy '$Name' has no Effect. Add for example: Effect Deny, Effect (Param Effect), a Modify or Append block, DenyAction Delete, Manual, or AuditIfNotExists or DeployIfNotExists -Type ... { }."
        )
    }

    $script:BylawCollectedPolicies.Add($policy)
}
