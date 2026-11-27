function Initiative {
    <#
    .SYNOPSIS
        Declares one Azure Policy initiative (policy set definition).

    .DESCRIPTION
        A top-level Bylaw DSL command, like Policy (ADR-0033). The scriptblock uses the inner
        keywords Properties, Parameter, PolicyDefinition and DefinitionGroup, with Param, Arm and
        ResourceGroupTag for values. They exist only while the block runs.

        Members are policies from the same build, by name, or other definitions by ID. Members from
        the build are checked against the compiled policies once every file has compiled
        (ADR-0034).

    .PARAMETER Name
        The definition name. It is the initiative's identity and output file name, so renaming it
        creates a new initiative. The same rule as for Policy names applies (ADR-0010), and names
        are unique across the policies and initiatives in a build.

    .PARAMETER Body
        The initiative description.

    .EXAMPLE
        Initiative 'tagging-baseline' {
            Properties @{ DisplayName = 'Tagging baseline'; Category = 'Tags'; Version = '1.0.0' }
            Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit

            PolicyDefinition 'tags-require-mandatory-tags' -Parameters @{ effect = Param Effect }
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $Body
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Initiative')

    $outer = Get-BylawCurrentFrame
    if ($null -ne $outer) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1003' -Location $location -Message (
            "Initiative '$Name' is nested inside $($outer.Keyword). Each Initiative must be at the top level of the file."
        )
        return
    }

    $initiative = [BylawInitiative]::new($Name)
    $initiative.Location = $location
    $frame = Enter-BylawFrame -Keyword 'Initiative' -Node $initiative
    try {
        Invoke-BylawPolicyBody -Body $Body
    }
    catch {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1014' -Location (ConvertTo-BylawLocation -ErrorRecord $_) -Message (
            "Initiative '$Name' stopped because of an error: $($_.Exception.Message)"
        )
    }
    finally {
        Exit-BylawFrame -Frame $frame
    }

    if ($initiative.Members.Count -eq 0 -and -not $frame.Singletons.ContainsKey('PolicyDefinition')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1054' -Location $location -Message (
            "Initiative '$Name' has no PolicyDefinition. Add the policies it includes, e.g. PolicyDefinition 'policy-name', or PolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/<guid>' -ReferenceId 'Name'."
        )
    }

    $script:BylawCollectedInitiatives.Add($initiative)
}
