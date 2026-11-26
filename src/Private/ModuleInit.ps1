# Runs at module import, after all functions are defined.
#
# Outside a Policy block the inner keywords don't exist, so PowerShell would report a generic
# "term not recognized" error. This CommandNotFoundAction handler replaces that with a clear Bylaw
# message (ADR-0005). It chains to any handler that was registered before, and is removed when the
# module is removed.

$script:BylawPreviousCommandNotFoundAction = $ExecutionContext.InvokeCommand.CommandNotFoundAction

$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param([string] $CommandName, [System.Management.Automation.CommandLookupEventArgs] $LookupEventArgs)

    # PowerShell also retries unknown commands with a 'get-' prefix; match either form.
    $name = $CommandName -replace '^get-', ''
    $keyword = $script:BylawKeywordNames | Where-Object { $_ -eq $name } | Select-Object -First 1
    if ($keyword) {
        $message = "BYL1001: '$keyword' is a Bylaw keyword and can only be used inside a Policy block."
        $LookupEventArgs.CommandScriptBlock = { throw $message }.GetNewClosure()
        $LookupEventArgs.StopSearch = $true
        return
    }
    if ($script:BylawPreviousCommandNotFoundAction) {
        & $script:BylawPreviousCommandNotFoundAction $CommandName $LookupEventArgs
    }
}

$ExecutionContext.SessionState.Module.OnRemove = {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = $script:BylawPreviousCommandNotFoundAction
}
