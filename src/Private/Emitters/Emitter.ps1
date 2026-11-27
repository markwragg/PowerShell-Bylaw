# Emitter registry (ADR-0011).
#
# Each output format names the functions that implement the emitter contract:
#   Test      [BylawPolicy] -> diagnostics: format rules the policy must meet
#   Emit      [BylawPolicy] -> document: the output as ordered objects
#   Serialize document      -> text: bytes on disk (a Bicep emitter can bring its own)
#   TestInitiative, EmitInitiative: the same for an initiative (ADR-0035)
# plus FileExtension for the output file. A Bicep emitter would add an entry here.

$script:BylawEmitters = [ordered]@{
    Epac      = [pscustomobject]@{
        Name           = 'Epac'
        FileExtension  = '.json'
        Test           = 'Test-BylawEpacPolicy'
        Emit           = 'ConvertTo-BylawEpacDocument'
        Serialize      = 'ConvertTo-BylawJson'
        TestInitiative = 'Test-BylawEpacInitiative'
        EmitInitiative = 'ConvertTo-BylawEpacInitiativeDocument'
    }
    # ADR-0027.
    PlainJson = [pscustomobject]@{
        Name           = 'PlainJson'
        FileExtension  = '.json'
        Test           = 'Test-BylawPlainJsonPolicy'
        Emit           = 'ConvertTo-BylawPlainJsonDocument'
        Serialize      = 'ConvertTo-BylawJson'
        TestInitiative = 'Test-BylawPlainJsonInitiative'
        EmitInitiative = 'ConvertTo-BylawPlainJsonInitiativeDocument'
    }
}

function Get-BylawEmitter {
    # The emitter for a format name, ignoring case.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Format)

    foreach ($name in $script:BylawEmitters.Keys) {
        if ([string]::Equals($name, $Format, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $script:BylawEmitters[$name]
        }
    }
    throw [System.ArgumentException]::new("Unknown output format '$Format'. Valid formats: $($script:BylawEmitters.Keys -join ', ').")
}

function Invoke-BylawEmitter {
    # Runs one emitter on a compiled policy. Returns the file name, document, text and the
    # emitter's diagnostics; Document and Text are $null when the emitter reports errors.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [string] $Format = 'Epac'
    )

    $emitter = Get-BylawEmitter -Format $Format
    $diagnostics = @(& $emitter.Test -Policy $Policy)
    $document = $null
    $text = $null
    if (@($diagnostics | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count -eq 0) {
        $document = & $emitter.Emit -Policy $Policy
        $text = & $emitter.Serialize -InputObject $document
    }
    [pscustomobject]@{
        Format      = $emitter.Name
        FileName    = $Policy.Name + $emitter.FileExtension
        Document    = $document
        Text        = $text
        Diagnostics = $diagnostics
    }
}
