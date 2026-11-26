# Keyword host: front-end state, keyword scoping and diagnostics (ADR-0005).
#
# Inner keywords are private module functions. While a Policy block runs, they are defined in a
# fresh scope of the *caller's* session state, and the Policy body is dot-sourced into that scope.
# When the scope ends (normally or by exception) the keywords disappear with it, so nothing leaks.
#
# This needs a module-created scriptblock rebound to the caller's session state, which PowerShell
# only exposes through the internal ScriptBlock.SessionStateInternal property (Pester relies on the
# same property). tests/Unit/Keywords/KeywordHost.Tests.ps1 fails loudly if it ever disappears.

$script:BylawKeywordNames = @(
    'Properties', 'Parameter', 'Resource', 'When', 'Require', 'Each',
    'Field', 'Element', 'Must', 'Effect', 'Param', 'Arm'
)

$script:BylawSessionStateProperty = [scriptblock].GetProperty(
    'SessionStateInternal',
    [System.Reflection.BindingFlags] 'NonPublic, Instance'
)

# Defines the keywords in its own scope, makes errors terminating so the Policy can report them as
# diagnostics, then dot-sources the body into the same scope. Variable names are prefixed to avoid
# colliding with the author's variables.
$script:BylawWrapperText = {
    param($__bylawDefinitions, $__bylawBody)
    foreach ($__bylawEntry in $__bylawDefinitions.GetEnumerator()) {
        Microsoft.PowerShell.Management\Set-Item -LiteralPath ('function:local:' + $__bylawEntry.Key) -Value $__bylawEntry.Value
    }
    $ErrorActionPreference = 'Stop'
    $null = . $__bylawBody
}.ToString()

$script:BylawKeywordDefinitions = $null

function Reset-BylawFrontEnd {
    # Clears collected policies, diagnostics and the keyword frame stack.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Resets in-memory module state only.')]
    param()

    $script:BylawCollectedPolicies = [System.Collections.Generic.List[object]]::new()
    $script:BylawDiagnostics = [System.Collections.Generic.List[object]]::new()
    $script:BylawFrames = [System.Collections.Generic.List[object]]::new()
}

function Get-BylawCollectedPolicy {
    $script:BylawCollectedPolicies.ToArray()
}

function Get-BylawFrontEndDiagnostic {
    $script:BylawDiagnostics.ToArray()
}

function Add-BylawDiagnostic {
    param(
        [Parameter(Mandatory)] [BylawSeverity] $Severity,
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Message,
        [BylawSourceLocation] $Location
    )
    $script:BylawDiagnostics.Add([BylawDiagnostic]::new($Severity, $Code, $Message, $Location))
}

function Get-BylawCurrentFrame {
    if ($script:BylawFrames.Count -eq 0) {
        return $null
    }
    $script:BylawFrames[$script:BylawFrames.Count - 1]
}

function Enter-BylawFrame {
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [BylawNode] $Node
    )
    $frame = [BylawFrame]::new($Keyword, $Node)
    $script:BylawFrames.Add($frame)
    $frame
}

function Exit-BylawFrame {
    # Pops the given frame and reports any Field that was never piped to Must.
    param([Parameter(Mandatory)] [BylawFrame] $Frame)

    $index = $script:BylawFrames.LastIndexOf($Frame)
    if ($index -ge 0) {
        $script:BylawFrames.RemoveRange($index, $script:BylawFrames.Count - $index)
    }
    foreach ($field in $Frame.PendingFields) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1007' -Location $field.Location -Message (
            "Field '{0}' is not piped to Must. Write: Field {0} | Must ..." -f $field
        )
    }
}

function Test-BylawParent {
    # Returns the current frame when the keyword is used inside one of the allowed parents;
    # otherwise records a diagnostic and returns $null.
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [string[]] $Allowed,
        [BylawSourceLocation] $Location
    )
    $frame = Get-BylawCurrentFrame
    if ($null -eq $frame) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1001' -Location $Location -Message (
            "'$Keyword' can only be used inside a Policy block."
        )
        return $null
    }
    if ($Allowed -notcontains $frame.Keyword) {
        $where = ($Allowed | ForEach-Object { "'$_'" }) -join ' or '
        Add-BylawDiagnostic -Severity Error -Code 'BYL1002' -Location $Location -Message (
            "'$Keyword' cannot be used inside '$($frame.Keyword)'. It must be directly inside $where."
        )
        return $null
    }
    $frame
}

function Test-BylawSingleton {
    # Records a diagnostic and returns $false when the keyword already appeared in this frame.
    param(
        [Parameter(Mandatory)] [BylawFrame] $Frame,
        [Parameter(Mandatory)] [string] $Keyword,
        [BylawSourceLocation] $Location
    )
    if ($Frame.Singletons.ContainsKey($Keyword)) {
        $first = $Frame.Singletons[$Keyword]
        Add-BylawDiagnostic -Severity Error -Code 'BYL1004' -Location $Location -Message (
            "'$Keyword' can only appear once in '$($Frame.Keyword)' (first used at line $($first.Line))."
        )
        return $false
    }
    $Frame.Singletons[$Keyword] = $Location
    $true
}

function Get-BylawKeywordDefinition {
    if ($null -eq $script:BylawKeywordDefinitions) {
        $definitions = @{}
        foreach ($name in $script:BylawKeywordNames) {
            $definitions[$name] = (Get-Item -LiteralPath "function:$name").ScriptBlock
        }
        $script:BylawKeywordDefinitions = $definitions
    }
    $script:BylawKeywordDefinitions
}

function Invoke-BylawPolicyBody {
    # Runs a Policy body in the caller's session state with the inner keywords in scope.
    param([Parameter(Mandatory)] [scriptblock] $Body)

    $wrapper = [scriptblock]::Create($script:BylawWrapperText)
    $script:BylawSessionStateProperty.SetValue($wrapper, $script:BylawSessionStateProperty.GetValue($Body))
    & $wrapper (Get-BylawKeywordDefinition) $Body
}

function Invoke-BylawBlock {
    # Runs a nested keyword block (Resource, When, Require, Each). The body is bound to the caller,
    # so it runs in the caller's scope chain, where the keywords are visible.
    param([Parameter(Mandatory)] [scriptblock] $Body)

    $null = & $Body
}

function ConvertTo-BylawLocation {
    # Location of a PowerShell error raised while running a Policy body: the first place in the
    # author's code, not in Bylaw's own module files (errors are re-raised through nested blocks).
    param([Parameter(Mandatory)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
    $isAuthorFile = {
        param([string] $Path)
        $Path -and -not $Path.StartsWith($moduleBase, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $candidates = @()
    if ($ErrorRecord.Exception -is [System.Management.Automation.IContainsErrorRecord] -and $ErrorRecord.Exception.ErrorRecord) {
        $candidates += $ErrorRecord.Exception.ErrorRecord.InvocationInfo
    }
    $candidates += $ErrorRecord.InvocationInfo
    foreach ($invocation in $candidates) {
        if ($invocation -and (& $isAuthorFile $invocation.ScriptName)) {
            $keyword = if ($invocation.MyCommand) { $invocation.MyCommand.Name } else { $null }
            return [BylawSourceLocation]::FromInvocation($invocation, $keyword)
        }
    }

    # Fall back to the script stack trace: "at <ScriptBlock>, C:\path\file.bylaw.ps1: line 12".
    foreach ($line in ([string] $ErrorRecord.ScriptStackTrace) -split "`n") {
        if ($line -match ', (?<file>.+): line (?<line>\d+)\s*$' -and (& $isAuthorFile $Matches.file)) {
            return [BylawSourceLocation]::new($Matches.file, [int] $Matches.line, 0, $null)
        }
    }
    [BylawSourceLocation]::new($null, 0, 0, $null)
}

Reset-BylawFrontEnd
