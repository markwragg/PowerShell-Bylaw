$script:BylawParameterTypes = @('String', 'Array', 'Object', 'Boolean', 'Integer', 'Float', 'DateTime')

function Parameter {
    <#
    .SYNOPSIS
        Declares a policy parameter.

    .DESCRIPTION
        One-line form:  Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny
        Hashtable form: Parameter Locations @{ Type = 'Array'; Metadata = @{ strongType = 'location' } }
                        Parameter @{ Name = 'Locations'; Type = 'Array' }

        The hashtable form takes the same options as keys, one per line if you like (ADR-0021).
        When -Type is omitted it is inferred from -Default or -AllowedValues.

    .EXAMPLE
        Parameter AllowedValues @{
            Type        = 'Array'
            Default     = 'Public', 'Private', 'Confidential', 'Restricted'
            DisplayName = 'Allowed values'
            Description = 'Allowed classifications'
        }
    #>
    [CmdletBinding()]
    param(
        # Parameter name, or a hashtable with the keys Name, Type, AllowedValues, Default,
        # DisplayName, Description, JsonName and Metadata.
        [Parameter(Mandatory, Position = 0)]
        [object] $Name,

        # The options as a hashtable, after the name: the same keys as above, without Name.
        [Parameter(Position = 1)]
        [object] $Options,

        [string] $Type,
        [object[]] $AllowedValues,
        [AllowNull()] [object] $Default,
        [string] $DisplayName,
        [string] $Description,
        [string] $JsonName,
        [System.Collections.IDictionary] $Metadata
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Parameter')
    $frame = Test-BylawParent -Keyword 'Parameter' -Allowed 'Policy', 'Initiative' -Location $location
    if ($null -eq $frame) {
        return
    }

    $spec = @{}
    $nameIsTable = $Name -is [System.Collections.IDictionary]
    $hasOptions = $PSBoundParameters.ContainsKey('Options')
    if ($hasOptions -and $nameIsTable) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
            "Give the name before one hashtable, or inside it as Name, e.g. Parameter Locations @{ Type = 'Array' }."
        )
        return
    }
    if ($hasOptions -and $Options -isnot [System.Collections.IDictionary]) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
            "Parameter takes its options as named parameters or a hashtable, e.g. Parameter $Name -Default x or Parameter $Name @{ Default = 'x' }."
        )
        return
    }

    if ($nameIsTable -or $hasOptions) {
        $table = if ($nameIsTable) { $Name } else { $Options }
        $form = if ($nameIsTable) { 'Name' } else { 'Options' }
        $extra = @($PSBoundParameters.Keys | Where-Object { $_ -notin 'Name', $form })
        if ($extra.Count -gt 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                'Use either the hashtable form or parameters, not both (found -' + ($extra -join ', -') + ').'
            )
            return
        }
        $validKeys = @('Name', 'Type', 'AllowedValues', 'Default', 'DisplayName', 'Description', 'JsonName', 'Metadata')
        foreach ($key in $table.Keys) {
            $canonical = $validKeys | Where-Object { $_ -eq $key } | Select-Object -First 1
            if (-not $canonical) {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                    "Unknown Parameter key '$key'. Valid keys: $($validKeys -join ', ')."
                )
                return
            }
            if ($hasOptions -and $canonical -eq 'Name') {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                    "Parameter '$Name' has its name twice. Give it before the hashtable or as the Name key, not both."
                )
                return
            }
            $spec[$canonical] = $table[$key]
        }
        if ($hasOptions) {
            $spec['Name'] = $Name
        }
        if (-not ($spec['Name'] -is [string] -and $spec['Name'])) {
            $message = if ($nameIsTable) {
                "The Parameter hashtable must include a non-empty 'Name'."
            }
            else {
                "Parameter needs a name before the hashtable, e.g. Parameter Locations @{ Type = 'Array' }."
            }
            Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message $message
            return
        }
    }
    else {
        if ($Name -isnot [string] -or -not $Name) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                'Parameter needs a name, e.g. Parameter Effect -AllowedValues Audit, Deny.'
            )
            return
        }
        foreach ($key in $PSBoundParameters.Keys) {
            $spec[$key] = $PSBoundParameters[$key]
        }
    }

    $parameterName = $spec['Name']
    if ($parameterName -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
            "Parameter name '$parameterName' must start with a letter and contain only letters, digits and underscores."
        )
        return
    }
    if ($null -ne $frame.Node.FindParameter($parameterName)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
            "Parameter '$parameterName' is declared more than once."
        )
        return
    }

    $parameter = [BylawParameter]::new($parameterName)
    $parameter.Location = $location
    $parameter.JsonName = $spec['JsonName']
    $parameter.DisplayName = $spec['DisplayName']
    $parameter.Description = $spec['Description']
    $parameter.Metadata = $spec['Metadata']
    if ($spec.ContainsKey('AllowedValues')) {
        $parameter.AllowedValues = @($spec['AllowedValues'])
    }
    if ($spec.ContainsKey('Default')) {
        $parameter.HasDefault = $true
        $parameter.DefaultValue = $spec['Default']
    }

    if ($spec['Type']) {
        $canonicalType = $script:BylawParameterTypes | Where-Object { $_ -eq $spec['Type'] } | Select-Object -First 1
        if (-not $canonicalType) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                "Parameter '$parameterName' has unknown type '$($spec['Type'])'. Valid types: $($script:BylawParameterTypes -join ', ')."
            )
            return
        }
        $parameter.Type = $canonicalType
    }
    else {
        $inferred = Get-BylawInferredParameterType -Parameter $parameter
        if (-not $inferred) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1015' -Location $location -Message (
                "Cannot infer the type of parameter '$parameterName'. Add -Type ($($script:BylawParameterTypes -join ', '))."
            )
            return
        }
        $parameter.Type = $inferred
    }

    $frame.Node.Parameters.Add($parameter)
}

function Get-BylawInferredParameterType {
    # Infers the Azure parameter type from the default value, else from the allowed values.
    param([Parameter(Mandatory)] [BylawParameter] $Parameter)

    $hasDefault = $Parameter.HasDefault -and $null -ne $Parameter.DefaultValue
    if (-not $hasDefault -and -not $Parameter.AllowedValues) {
        return $null
    }

    # Avoid building a collection of samples here: PowerShell would unroll an array default into
    # its elements and infer the element type instead of Array.
    $types = if ($hasDefault) {
        Get-BylawValueTypeName -Value $Parameter.DefaultValue
    }
    else {
        foreach ($sample in $Parameter.AllowedValues) {
            Get-BylawValueTypeName -Value $sample
        }
    }
    $distinct = @($types | Select-Object -Unique)
    if ($distinct.Count -eq 1 -and $distinct[0] -ne 'Unknown') {
        return $distinct[0]
    }
    $null
}

function Get-BylawValueTypeName {
    # Azure parameter type name for a PowerShell value.
    param([AllowNull()] [object] $Value)

    if ($Value -is [string]) { 'String' }
    elseif ($Value -is [bool]) { 'Boolean' }
    elseif ($Value -is [int] -or $Value -is [long]) { 'Integer' }
    elseif ($Value -is [double] -or $Value -is [decimal]) { 'Float' }
    elseif ($Value -is [datetime]) { 'DateTime' }
    elseif ($Value -is [System.Collections.IDictionary]) { 'Object' }
    elseif ($Value -is [System.Collections.IEnumerable]) { 'Array' }
    else { 'Unknown' }
}
