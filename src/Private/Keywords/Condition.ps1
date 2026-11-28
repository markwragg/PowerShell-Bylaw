function Condition {
    <#
    .SYNOPSIS
        A raw Azure Policy condition, for what the language can't express (ADR-0040).

    .DESCRIPTION
        Condition takes one policy condition, as a hashtable or JSON text, in the shape of policy
        JSON: a field or value condition, a count, or allOf, anyOf or not. Field names are resolved
        like Field: a short name against the Resource type, or relative to the element inside Each.
        A full alias, a [*] field or an ARM expression is used as written. Values can be Param or
        Arm.

        In When and Count -Where, the condition is emitted as written. In Require and Each,
        statements describe the compliant state and are inverted, which Bylaw can't do correctly
        for a raw condition, so say which form it is: -Violation for the condition that finds a
        non-compliant resource, emitted as written, or -Compliant for the compliant state, emitted
        as not(...). Neither adds missing-field checks. Prefer the language where it can express
        the condition: it handles missing fields for you.

    .EXAMPLE
        When {
            Condition @{ value = "[requestContext().apiVersion]"; less = '2021-01-01' }
        }

    .EXAMPLE
        Require 'Diagnostic logs are enabled' {
            Condition -Violation @{
                count   = @{ field = 'logs[*]'; where = @{ field = 'logs[*].enabled'; equals = 'false' } }
                greater = 0
            }
        }

    .EXAMPLE
        Require 'The SKU is allowed' {
            Condition -Compliant '{ "field": "Microsoft.Compute/virtualMachines/sku.name", "in": ["Standard_D2s_v5", "Standard_D4s_v5"] }'
        }
    #>
    [CmdletBinding()]
    param(
        # The condition: a hashtable, an [ordered] hashtable, or JSON text.
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object] $Value,

        # In Require and Each: the condition finds a non-compliant resource, and is emitted as written.
        [switch] $Violation,

        # In Require and Each: the condition is the compliant state, and is emitted as not(...).
        [switch] $Compliant
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Condition')
    $frame = Test-BylawParent -Keyword 'Condition' -Allowed 'When', 'Require', 'Each', 'AnyOf', 'AllOf', 'Where' -Location $location
    if ($null -eq $frame) {
        return
    }

    # Which form: Require and Each are inverted, so they need a switch; When and Count -Where are
    # emitted as written, so a switch would mean nothing there.
    $context = Get-BylawConditionContext
    $inverted = $context -in 'Require', 'Each'
    $form = if ($Violation -and $Compliant) {
        $null
    }
    elseif ($Violation) {
        'Violation'
    }
    elseif ($Compliant) {
        'Compliant'
    }
    else {
        'AsWritten'
    }
    $formError = if ($null -eq $form) {
        'Condition takes -Violation or -Compliant, not both.'
    }
    elseif ($inverted -and $form -eq 'AsWritten') {
        "Condition in $context needs -Violation (the condition finds a non-compliant resource, and is emitted as written) or -Compliant (it is the compliant state, and is emitted as not(...))."
    }
    elseif (-not $inverted -and $form -ne 'AsWritten') {
        $block = if ($context -eq 'Where') { 'Count -Where' } else { $context }
        "Condition -$form is only for Require and Each. In $block, conditions are emitted as written, so leave out -$form."
    }
    if ($formError) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1061' -Location $location -Message $formError
        return
    }

    $object = $Value
    if ($Value -is [string]) {
        try {
            # Bylaw's reader keeps key order and rejects duplicate keys (JsonReader.ps1).
            $object = ConvertFrom-BylawJson -Json $Value
        }
        catch {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1060' -Location $location -Message (
                "Condition's JSON is not valid: $($_.Exception.Message)"
            )
            return
        }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $condition = ConvertFrom-BylawConditionObject -Object $object -Errors $errors -Location $location
    if ($errors.Count -gt 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1060' -Location $location -Message (
            "Condition isn't a valid policy condition: $($errors -join ' ')"
        )
        return
    }
    if ($null -eq $condition) {
        # A value problem, such as Param inside an array, was already reported (BYL1020).
        return
    }

    $statement = [BylawRawCondition]::new($condition, $form)
    $statement.Location = $location
    $frame.Node.Children.Add($statement)
}
