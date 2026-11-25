---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Only Policy and the utility cmdlets are exported; inner keywords exist only inside Policy

## Context and Problem Statement

The DSL uses short, generic command names (`Field`, `Resource`, `When`, `Each`, `Effect`, `Param`, `Expr`). Authors will often have Pester and other modules loaded in the same session. Exporting these names globally would pollute the session and risk clashing with other modules. How do we make the keywords available to the code inside a `Policy` scriptblock without exporting them?

## Decision Drivers

* No session pollution: `Get-Command Field` returns nothing outside a policy.
* The author's own variables and helper functions from the file must still be visible inside `Policy { }`.
* Calling a keyword in the wrong place gives a clear Bylaw error, not a generic "term not recognised".

## Considered Options

* Inject the keywords into the caller's session state for the duration of `Policy`
* Run the `Policy` scriptblock inside the module's session state (`NewBoundScriptBlock`)
* Export all keywords and have them throw outside a policy context

## Decision Outcome

Chosen option: "Inject into the caller's session state for the duration of `Policy`".

* **Exported:** `Policy`, `Build-Bylaw`, `Update-BylawAliasCache` (and `ConvertFrom-PolicyJson` in Milestone 3).
* When `Policy` runs, it creates function entries for each inner keyword in the **caller's** session state, through `$PSCmdlet.SessionState`. Each entry is a thin, module-bound proxy, so the keyword's implementation runs in module scope, with access to the compiler context. Then `Policy` invokes the author's scriptblock, and removes the entries in a `finally` block. If an entry with the same name already existed, it is saved and restored.
* **Context stack.** Each keyword checks that its parent is valid, for example that `Field` is inside `When`, `Require` or `Each`, and that `Properties` is directly inside `Policy`. A violation throws `BylawKeywordContextException`, with the file, line and keyword.
* **Outside `Policy`.** On import, the module registers a `CommandNotFoundAction` handler that recognises Bylaw keyword names. It replaces the generic error with "`Field` can only be used inside a `Policy` block". The handler chains to any previously registered handler and is removed when the module is removed.
* Nested `Policy` blocks are a compile error.

### Consequences

* Good, because the session stays clean, and file-level variables and helper functions work inside policies.
* Good, because misuse gives clear, located errors.
* Bad, because `Get-Help Field` and argument completers don't work outside a running policy. Help will be provided as `about_Bylaw_Keywords`. Editor completion (planned for later) will need a separate mechanism, such as registered completers or a language-server extension.
* Bad, because injecting into a session state goes slightly against the grain of PowerShell. A spike at the start of the keyword step will validate it on all three operating systems before anything is built on it.

### Confirmation

Tests check that the keywords are absent before and after `Policy`, including after an exception. They check that file-level variables and functions are visible inside `Policy`. They check the error text for calls outside `Policy` and for invalid nesting.

## Pros and Cons of the Options

### Inject into the caller's session state

* Good, because the author's scope behaves normally.
* Bad, because it is the most complex implementation.

### Module-bound scriptblock

* Good, because it is simple, and private functions are visible.
* Bad, because the author's file-level variables and functions are not visible, which breaks normal PowerShell expectations.

### Export everything with guards

* Good, because it is the simplest option, and help and completion work.
* Bad, because it contradicts the requirement not to export keywords, and pollutes the session with generic names.
