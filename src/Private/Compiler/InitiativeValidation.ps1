# Validation of an initiative on its own (ADR-0033). Checks that need the build's policies run
# after every file has compiled (ADR-0034).

# A policy definition ID: built-in, or a custom definition at a management group or subscription.
$script:BylawPolicyDefinitionIdPattern = '^(/providers/Microsoft\.Management/managementGroups/[^/]+|/subscriptions/[^/]+)?/providers/Microsoft\.Authorization/policyDefinitions/[^/]+$'

function Invoke-BylawInitiativeValidation {
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative)

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Code, [string] $Message, [BylawSourceLocation] $Location, [BylawSeverity] $Severity = [BylawSeverity]::Error)
        $diagnostics.Add([BylawDiagnostic]::new($Severity, $Code, $Message, $Location))
    }

    # Name (ADR-0010), properties and parameters, as for a policy.
    $nameProblem = Get-BylawNameProblem -Name $Initiative.Name
    if ($nameProblem) {
        & $add 'BYL3001' "Initiative name '$($Initiative.Name)' $nameProblem (ADR-0010)." $Initiative.Location
    }
    Test-BylawPolicyProperty -Policy $Initiative -Add $add
    Test-BylawPolicyParameter -Policy $Initiative -Add $add

    # Learn's limits for an initiative.
    if ($Initiative.Members.Count -gt 1000) {
        & $add 'BYL3115' "Initiative '$($Initiative.Name)' has $($Initiative.Members.Count) members; Azure allows at most 1000." $Initiative.Location
    }
    if ($Initiative.Parameters.Count -gt 400) {
        & $add 'BYL3115' "Initiative '$($Initiative.Name)' has $($Initiative.Parameters.Count) parameters; Azure allows at most 400." $Initiative.Location
    }

    # Groups: unique names, ignoring case.
    $groups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $Initiative.Groups) {
        if ($groups.ContainsKey($group.Name)) {
            & $add 'BYL3112' "Definition group '$($group.Name)' is declared more than once (first at line $($groups[$group.Name].Location.Line))." $group.Location
            continue
        }
        $groups[$group.Name] = $group
    }

    $referenceIds = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $usedGroups = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $Initiative.Members) {
        if ($referenceIds.ContainsKey($member.ReferenceId)) {
            $first = $referenceIds[$member.ReferenceId]
            & $add 'BYL3110' "Reference ID '$($member.ReferenceId)' is used by more than one member (first at line $($first.Location.Line)). Give each member its own -ReferenceId; a policy can be a member more than once with different ones." $member.Location
        }
        else {
            $referenceIds[$member.ReferenceId] = $member
        }

        if ($member.DefinitionId) {
            if ($member.DefinitionId -match '/providers/Microsoft\.Authorization/policySetDefinitions/') {
                & $add 'BYL3111' "Member -Id '$($member.DefinitionId)' is an initiative. An initiative can't include another initiative: include its policies instead." $member.Location
            }
            elseif ($member.DefinitionId -notmatch $script:BylawPolicyDefinitionIdPattern) {
                & $add 'BYL3111' "Member -Id '$($member.DefinitionId)' is not a policy definition ID. Use /providers/Microsoft.Authorization/policyDefinitions/<name>, optionally after a management group or subscription scope." $member.Location
            }
        }

        foreach ($entry in $member.Parameters.GetEnumerator()) {
            foreach ($reference in Get-BylawValueParameterReference -Value $entry.Value) {
                if ($null -eq $Initiative.FindParameter($reference.Name)) {
                    & $add 'BYL3020' "Parameter '$($reference.Name)' is passed to member '$($member.ReferenceId)' but not declared. Add a Parameter $($reference.Name) declaration to the initiative." $reference.Location
                }
            }
        }

        foreach ($groupName in $member.GroupNames) {
            $null = $usedGroups.Add($groupName)
            if (-not $groups.ContainsKey($groupName)) {
                & $add 'BYL3113' "Member '$($member.ReferenceId)' is in group '$groupName', which no DefinitionGroup declares. Add: DefinitionGroup '$groupName'." $member.Location
            }
        }
    }
    foreach ($group in $groups.Values) {
        if (-not $usedGroups.Contains($group.Name)) {
            & $add 'BYL3114' "Definition group '$($group.Name)' has no members. Add it to a Member with -Group '$($group.Name)', or remove it." $group.Location
        }
    }

    # Parameters no member uses (ADR-0021).
    $used = Get-BylawInitiativeUsedParameterName -Initiative $Initiative
    foreach ($parameter in $Initiative.Parameters) {
        if (-not $used.Contains($parameter.Name)) {
            & $add 'BYL3029' "Parameter '$($parameter.Name)' is declared but never passed to a member." $parameter.Location ([BylawSeverity]::Warning)
        }
    }

    foreach ($diagnostic in $diagnostics) {
        $diagnostic
    }
}

function Get-BylawValueParameterReference {
    # The Param references in a value: the value itself, or a ResourceGroupTag's tag name.
    param([AllowNull()] [BylawValue] $Value)

    if ($Value -is [BylawParamRef]) {
        $Value
    }
    elseif ($Value -is [BylawResourceGroupTag] -and $Value.TagName -is [BylawParamRef]) {
        $Value.TagName
    }
}

function Get-BylawInitiativeUsedParameterName {
    # DSL names of the initiative parameters its members' values use: Param, ResourceGroupTag
    # (Param X), and parameters('...') inside Arm expressions.
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative)

    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $Initiative.Members) {
        foreach ($value in $member.Parameters.Values) {
            foreach ($reference in Get-BylawValueParameterReference -Value $value) {
                $null = $used.Add($reference.Name)
            }
            if ($value -is [BylawExpr]) {
                foreach ($parameter in $Initiative.Parameters) {
                    $jsonName = Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
                    if ($value.Text -match ("parameters\(\s*'" + [regex]::Escape($jsonName) + "'\s*\)")) {
                        $null = $used.Add($parameter.Name)
                    }
                }
            }
        }
    }
    , $used
}
