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

if ($null -eq ('Bylaw.KeywordLookup' -as [type])) {
    # Compiled once per process: Build-Bylaw imports the module in a runspace per file (ADR-0014).
    Add-Type -Language CSharp -TypeDefinition @'
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
}

$script:BylawKeywordLookup = [Bylaw.KeywordLookup]::new(
    [string[]] $script:BylawKeywordNames,
    $ExecutionContext.InvokeCommand.CommandNotFoundAction
)
$ExecutionContext.InvokeCommand.CommandNotFoundAction = [System.EventHandler[System.Management.Automation.CommandLookupEventArgs]] $script:BylawKeywordLookup.OnCommandNotFound

$ExecutionContext.SessionState.Module.OnRemove = {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = $script:BylawKeywordLookup.Previous
}
