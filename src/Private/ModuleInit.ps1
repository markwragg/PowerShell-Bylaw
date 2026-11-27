# Runs at module import, after all functions are defined.
#
# Outside a Policy block the inner keywords don't exist, so PowerShell would report a generic
# "term not recognized" error. A CommandNotFoundAction handler replaces that with a clear Bylaw
# message (ADR-0005). It chains to any handler that was registered before, and is removed when the
# module is removed.
#
# The handler is compiled C#, not a scriptblock. PowerShell calls it for every command name it can't
# find, including during tab completion. A scriptblock created here belongs to the importing
# runspace, and when a lookup comes from another thread while that runspace is busy, PowerShell waits
# for the runspace, so tab completion hung. The compiled handler runs no PowerShell for other names,
# and for a keyword gives an unbound scriptblock that throws.
#
# Where Add-Type isn't allowed, as in Constrained Language Mode, the module imports without the
# handler, and a keyword outside a Policy gets PowerShell's usual "term not recognized" error.

$script:BylawKeywordLookupSource = @'
using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Bylaw
{
    public sealed class KeywordLookup
    {
        private readonly Dictionary<string, string> _keywords = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private readonly EventHandler<CommandLookupEventArgs> _previous;

        public KeywordLookup(string[] keywords, EventHandler<CommandLookupEventArgs> previous)
        {
            foreach (string keyword in keywords)
            {
                _keywords[keyword] = keyword;
            }
            _previous = previous;
        }

        public EventHandler<CommandLookupEventArgs> Previous
        {
            get { return _previous; }
        }

        public void OnCommandNotFound(object sender, CommandLookupEventArgs e)
        {
            // PowerShell also retries unknown commands with a 'get-' prefix; match either form.
            string name = e.CommandName;
            if (name.StartsWith("get-", StringComparison.OrdinalIgnoreCase))
            {
                name = name.Substring(4);
            }
            string keyword;
            if (_keywords.TryGetValue(name, out keyword))
            {
                string message = "BYL1001: '" + keyword + "' is a Bylaw keyword and can only be used inside a Policy block.";
                e.CommandScriptBlock = ScriptBlock.Create("throw '" + message.Replace("'", "''") + "'");
                e.StopSearch = true;
                return;
            }
            if (_previous != null)
            {
                _previous(sender, e);
            }
        }
    }
}
'@

function Register-BylawKeywordLookup {
    # Compiles Bylaw.KeywordLookup once per process (Build-Bylaw imports the module in a runspace
    # per file, ADR-0014) and registers it as the handler. Returns $false, leaving the handler as it
    # was, when the type can't be compiled.
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $TypeName = 'Bylaw.KeywordLookup')

    $type = $TypeName -as [type]
    if ($null -eq $type) {
        try {
            Add-Type -Language CSharp -TypeDefinition $script:BylawKeywordLookupSource -ErrorAction Stop
            $type = $TypeName -as [type]
        }
        catch {
            Write-Verbose "Bylaw: no keyword handler, because Add-Type failed: $($_.Exception.Message)"
        }
        if ($null -eq $type) {
            return $false
        }
    }
    $script:BylawKeywordLookup = $type::new([string[]] $script:BylawKeywordNames, $ExecutionContext.InvokeCommand.CommandNotFoundAction)
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = [System.EventHandler[System.Management.Automation.CommandLookupEventArgs]] $script:BylawKeywordLookup.OnCommandNotFound
    $true
}

$script:BylawKeywordLookup = $null
$null = Register-BylawKeywordLookup

$ExecutionContext.SessionState.Module.OnRemove = {
    if ($null -ne $script:BylawKeywordLookup) {
        $ExecutionContext.InvokeCommand.CommandNotFoundAction = $script:BylawKeywordLookup.Previous
    }
}
