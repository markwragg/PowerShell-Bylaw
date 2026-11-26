# Count and Current (ADR-0032). Count is piped to Must, like a value condition; its -Where block
# selects the elements to count and is emitted as written, like When. Current is the member a count
# is at, inside -Where.

# Operators a count can be tested with: a count is a number.
$script:BylawCountOperators = @('Be', 'BeIn', 'BeGreaterThan', 'BeGreaterOrEqual', 'BeLessThan', 'BeLessOrEqual')

function Count {
    <#
    .SYNOPSIS
        The number of array elements, or of members of a list, that match -Where. Pipe it to Must.

    .EXAMPLE
        Count networkAcls.ipRules[*] | Must -BeGreaterThan 0

    .EXAMPLE
        Count securityRules[*] -Where { Field access | Must -Be 'Allow' } | Must -BeLessOrEqual 2

    .EXAMPLE
        Count -Value (Param MandatoryTags) -Name tagName -Where {
            Tag (Current tagName) | Must -Exist
        } | Must -Be (Arm "[length(parameters('mandatoryTags'))]")
    #>
    [CmdletBinding()]
    param(
        # An array path ending in [*], for a field count.
        [Parameter(Position = 0)]
        [string] $Path,

        # The list to count the members of, for a value count: an array, Param or Arm.
        [object] $Value,

        # The name Current uses for a value count's member. Letters and digits.
        [string] $Name,

        # Selects the elements or members to count. Without it, all are counted.
        [scriptblock] $Where
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Count')
    $frame = Test-BylawParent -Keyword 'Count' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Where' -Location $location
    if ($null -eq $frame) {
        return
    }

    $isField = $PSBoundParameters.ContainsKey('Path')
    $isValue = $PSBoundParameters.ContainsKey('Value')
    if ($isField -eq $isValue) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1047' -Location $location -Message (
            'Count takes an array path or -Value, not both: Count networkAcls.ipRules[*], or Count -Value (Param AllowedTags).'
        )
        return
    }

    $node = [BylawCount]::new()
    $node.Location = $location
    $enclosing = @(Get-BylawEnclosingCount)
    if ($isField) {
        if (-not $Path.EndsWith('[*]')) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1047' -Location $location -Message (
                "Count needs an array path ending in [*], e.g. Count networkAcls.ipRules[*] (got '$Path')."
            )
            return
        }
        if ($PSBoundParameters.ContainsKey('Name')) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1048' -Location $location -Message (
                "-Name is for a value count. In a field count, Current refers to the element: Current, or Field <name> for one of its fields."
            )
            return
        }
        $field = [BylawFieldRef]::new($Path)
        $field.Location = $location
        $node.Field = $field
    }
    else {
        $source = Get-BylawCountSource -Value $Value -Location $location
        if ($null -eq $source) {
            return
        }
        $node.ValueSource = $source
        if ($PSBoundParameters.ContainsKey('Name')) {
            if ($Name -notmatch '^[A-Za-z0-9]+$') {
                Add-BylawDiagnostic -Severity Error -Code 'BYL1048' -Location $location -Message (
                    "-Name '$Name' is not valid: use letters and digits only, e.g. -Name tagName."
                )
                return
            }
            $node.Name = $Name
        }
        elseif ($enclosing.Count -gt 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1049' -Location $location -Message (
                'A value count inside another count (Count -Where, or Each) needs -Name, as Azure requires, e.g. Count -Value ... -Name item.'
            )
            return
        }
    }

    if ($PSBoundParameters.ContainsKey('Where')) {
        $diagnosticsBefore = $script:BylawDiagnostics.Count
        $whereFrame = Enter-BylawFrame -Keyword 'Where' -Node $node
        try {
            Invoke-BylawBlock -Body $Where
        }
        finally {
            Exit-BylawFrame -Frame $whereFrame
        }
        $innerErrors = @($script:BylawDiagnostics | Select-Object -Skip $diagnosticsBefore | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count
        if ($node.Children.Count -eq 0 -and $innerErrors -eq 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1013' -Location $location -Message (
                "Count -Where is empty. Add the condition the elements must meet to be counted, or leave out -Where to count them all."
            )
            return
        }
    }

    $frame.PendingFields.Add($node)
    $node
}

function Current {
    <#
    .SYNOPSIS
        The member a count is at, inside Count -Where: Current name for a named value count, or
        Current for the innermost count.

    .EXAMPLE
        Count -Value (Param MandatoryTags) -Name tagName -Where { Tag (Current tagName) | Must -Exist } | Must -Be 0
    #>
    [CmdletBinding()]
    param(
        # The -Name of the value count, or nothing for the innermost count.
        [Parameter(Position = 0)]
        [string] $Name
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Current')
    if ($null -eq (Get-BylawCurrentFrame)) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $location -Message (
            "'Current' can only be used inside a Policy block."
        )
        return
    }
    $counts = @(Get-BylawEnclosingCount -WhereOnly)
    if ($counts.Count -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1050' -Location $location -Message (
            'Current can only be used inside Count -Where, where it is the element or member being counted.'
        )
        return
    }

    $node = [BylawCurrent]::new()
    $node.Location = $location
    if ($PSBoundParameters.ContainsKey('Name') -and $Name) {
        $count = $counts | Where-Object { $_.Name -and [string]::Equals($_.Name, $Name, [System.StringComparison]::Ordinal) } | Select-Object -First 1
        if ($null -eq $count) {
            $names = @($counts | Where-Object Name | ForEach-Object Name)
            $known = if ($names.Count -gt 0) { " Counts here are named: $($names -join ', ')." } else { ' No count here has -Name.' }
            Add-BylawDiagnostic -Severity Error -Code 'BYL1050' -Location $location -Message (
                "Current $Name doesn't match the -Name of a value count around it.$known"
            )
            return
        }
        $node.Name = $Name
        $node.Count = $count
        return $node
    }

    # The innermost count. Learn: current() without a name is only allowed in a value count that
    # isn't inside another count; in a field count it is current('<array alias>[*]').
    $innermost = $counts[0]
    if (-not $innermost.IsFieldCount() -and @(Get-BylawEnclosingCount).Count -gt 1) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1050' -Location $location -Message (
            'Current without a name is ambiguous in a value count inside another count. Give the count -Name and use Current <name>.'
        )
        return
    }
    $node.Count = $innermost
    $node
}

function Get-BylawEnclosingCount {
    # The counts around the current statement, innermost first: BylawCount nodes of Count -Where
    # blocks, and with Each blocks too unless -WhereOnly (each Each compiles to a count).
    param([switch] $WhereOnly)

    for ($index = $script:BylawFrames.Count - 1; $index -ge 0; $index--) {
        $frame = $script:BylawFrames[$index]
        if ($frame.Keyword -eq 'Where') {
            $frame.Node
        }
        elseif ($frame.Keyword -eq 'Each' -and -not $WhereOnly) {
            $frame.Node
        }
    }
}

function Get-BylawCountSource {
    # The list a value count counts: a literal array, Param or Arm. $null after BYL1047.
    param([AllowNull()] [object] $Value, [BylawSourceLocation] $Location)

    if ($Value -is [BylawParamRef] -or $Value -is [BylawExpr]) {
        return $Value
    }
    if ($Value -is [System.Collections.IList] -and @($Value).Count -gt 0) {
        return ConvertTo-BylawValue -Value $Value -Location $Location
    }
    Add-BylawDiagnostic -Severity Error -Code 'BYL1047' -Location $Location -Message (
        "Count -Value takes a list to count the members of: an array such as @('a', 'b'), a Param or an Arm expression."
    )
    $null
}
