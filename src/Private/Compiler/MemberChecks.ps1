# Checks of initiative members against the build's policies (ADR-0034).
#
# Each file compiles alone (ADR-0014), so the checks run in Build-Bylaw once every file has compiled,
# over plain data each file returns: for a policy, the parameters it emitted (which differ by format:
# EPAC generates an effect parameter for a literal effect) and its Version; for an initiative, its
# parameters and members.

function ConvertTo-BylawPlainParameterList {
    # The parameters of an emitted document, as plain hashtables: Name, Type, HasDefault, Default,
    # AllowedValues. Runs in the file's runspace.
    [OutputType([hashtable])]
    param([AllowNull()] [System.Collections.IDictionary] $Document)

    if ($null -eq $Document -or -not $Document['properties'].Contains('parameters')) {
        return
    }
    foreach ($entry in $Document['properties']['parameters'].GetEnumerator()) {
        $definition = $entry.Value
        @{
            Name          = [string] $entry.Key
            Type          = [string] $definition['type']
            HasDefault    = $definition.Contains('defaultValue')
            Default       = if ($definition.Contains('defaultValue')) { $definition['defaultValue'] } else { $null }
            AllowedValues = if ($definition.Contains('allowedValues')) { [object[]] @($definition['allowedValues']) } else { $null }
        }
    }
}

function ConvertTo-BylawPlainMemberList {
    # An initiative's members as plain hashtables, with each passed value's kind. Runs in the file's
    # runspace.
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [BylawInitiative] $Initiative)

    foreach ($member in $Initiative.Members) {
        $parameters = foreach ($entry in $member.Parameters.GetEnumerator()) {
            $value = $entry.Value
            if ($value -is [BylawLiteral]) {
                @{ Name = [string] $entry.Key; Kind = 'Literal'; Value = $value.Value }
            }
            elseif ($value -is [BylawParamRef]) {
                $parameter = $Initiative.FindParameter($value.Name)
                $jsonName = if ($parameter) { Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName } else { $value.Name }
                @{ Name = [string] $entry.Key; Kind = 'Param'; Parameter = $jsonName }
            }
            else {
                # Arm or ResourceGroupTag: only known when the policy is evaluated.
                @{ Name = [string] $entry.Key; Kind = 'Expression' }
            }
        }
        @{
            ReferenceId  = $member.ReferenceId
            PolicyName   = $member.PolicyName
            DefinitionId = $member.DefinitionId
            Version      = $member.Version
            Line         = if ($member.Location) { $member.Location.Line } else { 0 }
            Parameters   = [object[]] @($parameters)
        }
    }
}

function Test-BylawInitiativeMemberSet {
    # The cross-file checks for every initiative in the build. Policies: build results with Name,
    # Version and Parameters. Initiatives: build results with Name, File, Parameters and Members.
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param(
        [AllowEmptyCollection()] [object[]] $Policies = @(),
        [AllowEmptyCollection()] [object[]] $Initiatives = @()
    )

    $index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in $Policies) {
        if (-not $index.ContainsKey($policy.Name)) {
            $index[$policy.Name] = $policy
        }
    }
    $policyNames = [string[]] @($index.Keys)

    foreach ($initiative in $Initiatives) {
        $initiativeParameters = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($parameter in @($initiative.Parameters)) {
            $initiativeParameters[$parameter.Name] = $parameter
        }
        foreach ($member in @($initiative.Members)) {
            if (-not $member.PolicyName) {
                # A member by -Id: its parameters can't be checked offline.
                continue
            }
            $location = [BylawSourceLocation]::new($initiative.File, $member.Line, 0, 'PolicyDefinition')
            $new = {
                param([string] $Code, [string] $Message, [BylawSeverity] $Severity = [BylawSeverity]::Error)
                [BylawDiagnostic]::new($Severity, $Code, $Message, $location)
            }

            if (-not $index.ContainsKey($member.PolicyName)) {
                $suggestion = if ($policyNames.Count -gt 0) { Get-BylawClosestMatch -Value $member.PolicyName -Candidates $policyNames } else { $null }
                $hint = if ($suggestion) { " Did you mean '$suggestion'?" } else { '' }
                & $new 'BYL3120' "Initiative '$($initiative.Name)' includes policy '$($member.PolicyName)', which isn't in this build.$hint For a policy outside the build, use PolicyDefinition -Id."
                continue
            }
            $policy = $index[$member.PolicyName]
            if ($policy.Name -cne $member.PolicyName) {
                & $new 'BYL3127' "PolicyDefinition '$($member.PolicyName)' is emitted as written, but the policy is named '$($policy.Name)'. Write the name as the policy does, so tools that match it exactly find it." ([BylawSeverity]::Warning)
            }

            $parameters = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parameter in @($policy.Parameters)) {
                $parameters[$parameter.Name] = $parameter
            }
            $passed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($value in @($member.Parameters)) {
                $null = $passed.Add($value.Name)
                if (-not $parameters.ContainsKey($value.Name)) {
                    $known = if ($parameters.Count -gt 0) { " Its parameters: $(@($policy.Parameters | ForEach-Object Name) -join ', ')." } else { ' It has no parameters.' }
                    & $new 'BYL3121' "PolicyDefinition '$($member.ReferenceId)' passes '$($value.Name)', which is not a parameter of policy '$($policy.Name)'.$known"
                    continue
                }
                foreach ($problem in Get-BylawPassedValueProblem -Value $value -Parameter $parameters[$value.Name] -InitiativeParameters $initiativeParameters) {
                    $severity = if ($problem.ContainsKey('Warning')) { [BylawSeverity]::Warning } else { [BylawSeverity]::Error }
                    & $new $problem.Code "PolicyDefinition '$($member.ReferenceId)' passes $($problem.Message)" $severity
                }
            }
            foreach ($parameter in @($policy.Parameters)) {
                if (-not $parameter.HasDefault -and -not $passed.Contains($parameter.Name)) {
                    & $new 'BYL3122' "PolicyDefinition '$($member.ReferenceId)' doesn't pass '$($parameter.Name)', which policy '$($policy.Name)' requires: it has no default. Add it to -Parameters."
                }
            }

            if ($member.Version) {
                # Azure matches definitionVersion against a definition's top-level version, which
                # Bylaw doesn't emit while custom versioning is in preview (ADR-0016).
                & $new 'BYL3129' "PolicyDefinition '$($member.ReferenceId)' pins version $($member.Version), but Azure matches definitionVersion against a definition's top-level version property, which Bylaw doesn't emit: Version goes to metadata.version (ADR-0016). The pin may not select the version you expect." ([BylawSeverity]::Warning)
                if (-not $policy.Version) {
                    & $new 'BYL3126' "PolicyDefinition '$($member.ReferenceId)' asks for version $($member.Version), but policy '$($policy.Name)' has no Version. Add Version to its Properties, or remove -Version."
                }
                elseif (-not (Test-BylawDefinitionVersionMatch -Pattern $member.Version -Version $policy.Version)) {
                    & $new 'BYL3126' "PolicyDefinition '$($member.ReferenceId)' asks for version $($member.Version), but policy '$($policy.Name)' is version $($policy.Version), so the assignment would use a version this build doesn't produce."
                }
            }
        }
    }
}

function Get-BylawPassedValueProblem {
    # Why a passed value doesn't fit the member's parameter: @{ Code; Message; Warning? }, for each
    # problem.
    param(
        [Parameter(Mandatory)] [hashtable] $Value,
        [Parameter(Mandatory)] [hashtable] $Parameter,
        [Parameter(Mandatory)] [System.Collections.Generic.Dictionary[string, object]] $InitiativeParameters
    )

    $name = $Parameter.Name
    $allowed = $Parameter.AllowedValues
    $isArray = $Parameter.Type -eq 'Array'
    $outside = {
        param($Candidate)
        $items = if ($isArray) { @($Candidate) } else { , $Candidate }
        @($items | Where-Object { -not (Test-BylawValueIn -Value $_ -Values $allowed) })
    }

    if ($Value.Kind -eq 'Literal') {
        if (-not (Test-BylawParameterValueType -Value $Value.Value -Type $Parameter.Type)) {
            @{ Code = 'BYL3123'; Message = "'$($Value.Value)' to '$name', which is of type $($Parameter.Type)." }
        }
        elseif ($allowed) {
            $bad = @(& $outside $Value.Value)
            if ($bad.Count -gt 0) {
                @{ Code = 'BYL3123'; Message = "'$($bad -join ', ')' to '$name', which allows only $($allowed -join ', ')." }
            }
        }
        return
    }
    if ($Value.Kind -ne 'Param') {
        return
    }
    if (-not $InitiativeParameters.ContainsKey($Value.Parameter)) {
        # The initiative's own checks report an undeclared parameter.
        return
    }
    $source = $InitiativeParameters[$Value.Parameter]
    if ($source.Type -ne $Parameter.Type) {
        @{ Code = 'BYL3124'; Message = "initiative parameter '$($source.Name)', of type $($source.Type), to '$name', which is of type $($Parameter.Type)." }
        return
    }
    if (-not $allowed) {
        return
    }
    if ($source.HasDefault) {
        $bad = @(& $outside $source.Default)
        if ($bad.Count -gt 0) {
            @{ Code = 'BYL3125'; Message = "initiative parameter '$($source.Name)', whose default '$($bad -join ', ')' isn't one of the values '$name' allows ($($allowed -join ', '))." }
        }
    }
    if ($source.AllowedValues) {
        $bad = @($source.AllowedValues | Where-Object { -not (Test-BylawValueIn -Value $_ -Values $allowed) })
        if ($bad.Count -gt 0) {
            @{ Code = 'BYL3125'; Message = "initiative parameter '$($source.Name)', which allows '$($bad -join ', ')', to '$name', which doesn't ($($allowed -join ', ')). An assignment could pass a value the policy rejects." }
        }
    }
    elseif ($null -ne $allowed) {
        @{ Code = 'BYL3128'; Warning = $true; Message = "initiative parameter '$($source.Name)', which allows any value, to '$name', which allows only $($allowed -join ', '). Give '$($source.Name)' -AllowedValues within those, so an assignment can't pass a value the policy rejects." }
    }
}

function Test-BylawDefinitionVersionMatch {
    # True when a version such as 1.4.0 matches a definitionVersion pattern such as 1.*.*. A -preview
    # suffix on either is ignored.
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Pattern, [Parameter(Mandatory)] [string] $Version)

    $wanted = ($Pattern -replace '-preview$', '').Split('.')
    $actual = ($Version -replace '-preview$', '').Split('.')
    for ($index = 0; $index -lt 3; $index++) {
        if ($wanted[$index] -ne '*' -and $wanted[$index] -ne $actual[$index]) {
            return $false
        }
    }
    $true
}
