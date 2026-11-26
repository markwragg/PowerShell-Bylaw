# DSL operator -> non-negated Azure Policy operator (ADR-0015).
$script:BylawMustOperators = [ordered]@{
    Be               = 'equals'
    BeIn             = 'in'
    BeLike           = 'like'
    Match            = 'matchInsensitively'
    MatchCase        = 'match'
    ContainText      = 'contains'
    ContainKey       = 'containsKey'
    Exist            = 'exists'
    BeGreaterThan    = 'greater'
    BeGreaterOrEqual = 'greaterOrEquals'
    BeLessThan       = 'less'
    BeLessOrEqual    = 'lessOrEquals'
}

function Must {
    <#
    .SYNOPSIS
        Asserts the compliant state of the piped field. Exactly one operator per Must.

    .EXAMPLE
        Field publicNetworkAccess | Must -Be 'Disabled'

    .EXAMPLE
        Each networkAcls.ipRules[*] { Field value | Must -Not -Be '0.0.0.0/0' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject,

        [AllowNull()] [object] $Be,
        [object[]] $BeIn,
        [object] $BeLike,
        [object] $Match,
        [object] $MatchCase,
        [object] $ContainText,
        [object] $ContainKey,
        [switch] $Exist,
        [object] $BeGreaterThan,
        [object] $BeGreaterOrEqual,
        [object] $BeLessThan,
        [object] $BeLessOrEqual,

        # Inverts the operator.
        [switch] $Not,

        # A missing field is compliant (top level only, ADR-0004).
        [switch] $IfPresent,

        # A missing element field is a violation (inside Each only, ADR-0004).
        [switch] $Strict
    )

    begin {
        $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Must')
        $frame = Test-BylawParent -Keyword 'Must' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf' -Location $location
        $received = $false
        $bound = $PSBoundParameters
    }

    process {
        if ($null -eq $frame) {
            return
        }
        if (-not $bound.ContainsKey('InputObject')) {
            return
        }
        $received = $true
        $assertion = New-BylawAssertion -InputObject $InputObject -Bound $bound -Frame $frame -Location $location
        if ($null -ne $assertion) {
            $frame.Node.Children.Add($assertion)
        }
    }

    end {
        if ($null -ne $frame -and -not $received) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1008' -Location $location -Message (
                'Must needs a field from the pipeline, e.g. Field publicNetworkAccess | Must -Be Disabled.'
            )
        }
    }
}

function New-BylawAssertion {
    # Builds a BylawAssertion from Must's bound parameters, or records diagnostics and returns $null.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory IR node only.')]
    param(
        [AllowNull()] [object] $InputObject,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Bound,
        [Parameter(Mandatory)] [BylawFrame] $Frame,
        [BylawSourceLocation] $Location
    )

    # A field, or an expression for a value condition (ADR-0025). A literal is constant, so it
    # can't be tested.
    $isSubject = $InputObject -is [BylawValue] -and $InputObject -isnot [BylawLiteral]
    if ($InputObject -isnot [BylawFieldRef] -and -not $isSubject) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1008' -Location $Location -Message (
            'Must needs a Field, Tag or Element, or an expression (ResourceGroupTag, Param or Arm), from the pipeline, e.g. Field publicNetworkAccess | Must -Be Disabled.'
        )
        return $null
    }
    if (-not $isSubject) {
        $null = $Frame.PendingFields.Remove($InputObject)
    }

    $operators = @($script:BylawMustOperators.Keys | Where-Object {
            $Bound.ContainsKey($_) -and -not ($_ -eq 'Exist' -and -not $Bound[$_])
        })
    if ($operators.Count -ne 1) {
        $found = if ($operators.Count -eq 0) { 'none' } else { '-' + ($operators -join ', -') }
        Add-BylawDiagnostic -Severity Error -Code 'BYL1009' -Location $Location -Message (
            "Must takes exactly one operator (found $found). Operators: -" + ($script:BylawMustOperators.Keys -join ', -') + '.'
        )
        return $null
    }
    $dslOperator = $operators[0]

    $ifPresent = $Bound.ContainsKey('IfPresent') -and $Bound['IfPresent']
    $strict = $Bound.ContainsKey('Strict') -and $Bound['Strict']
    # Inside AnyOf or AllOf, the rules of the enclosing When, Require or Each apply (ADR-0026).
    $context = Get-BylawConditionContext
    if (-not $context) {
        $context = $Frame.Keyword
    }
    if ($isSubject) {
        $subjectError = if ($context -eq 'Each') {
            "Testing an expression ($InputObject) isn't supported inside Each yet. Test it in a separate Require or in When, outside the Each."
        }
        elseif ($dslOperator -eq 'Exist') {
            "-Exist tests whether a field is present, so it doesn't apply to an expression ($InputObject). To require a value, use Must -Not -Be ''."
        }
        elseif ($ifPresent -or $strict) {
            "-IfPresent and -Strict don't apply to an expression ($InputObject): only fields can be missing."
        }
        if ($subjectError) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1024' -Location $Location -Message $subjectError
            return $null
        }
    }
    $modeError = if ($ifPresent -and $strict) {
        '-IfPresent and -Strict cannot be used together.'
    }
    elseif (($ifPresent -or $strict) -and $context -eq 'When') {
        '-IfPresent and -Strict are not valid in When, which is not inverted (ADR-0004).'
    }
    elseif ($ifPresent -and $context -eq 'Each') {
        '-IfPresent is not needed inside Each: element fields are already lenient. Use -Strict to make a missing element field a violation.'
    }
    elseif ($strict -and $context -ne 'Each') {
        '-Strict is only valid inside Each: fields in Require are already strict. Use -IfPresent to make a missing field compliant.'
    }
    elseif ($ifPresent -and $dslOperator -eq 'Exist') {
        '-IfPresent cannot be combined with -Exist.'
    }
    if ($modeError) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1010' -Location $Location -Message $modeError
        return $null
    }

    $assertion = [BylawAssertion]::new()
    $assertion.Location = $Location
    if ($isSubject) {
        $assertion.Subject = $InputObject
    }
    else {
        $assertion.Field = $InputObject
    }
    $assertion.DslOperator = $dslOperator
    $assertion.Operator = $script:BylawMustOperators[$dslOperator]
    $assertion.Negated = $Bound.ContainsKey('Not') -and $Bound['Not']
    $assertion.MissingMode = if ($ifPresent) {
        [BylawMissingMode]::IfPresent
    }
    elseif ($strict) {
        [BylawMissingMode]::Strict
    }
    else {
        [BylawMissingMode]::Default
    }

    if ($dslOperator -eq 'Exist') {
        $assertion.Value = [BylawLiteral]::new($true)
        $assertion.Value.Location = $Location
    }
    else {
        $raw = $Bound[$dslOperator]
        # -BeIn binds as object[]; a single Param/Arm reference stays a reference, not an array.
        if ($dslOperator -eq 'BeIn' -and $raw.Count -eq 1 -and $raw[0] -is [BylawValue]) {
            $raw = $raw[0]
        }
        $value = ConvertTo-BylawValue -Value $raw -Location $Location
        if ($null -eq $value) {
            return $null
        }
        $assertion.Value = $value
    }
    $assertion
}
