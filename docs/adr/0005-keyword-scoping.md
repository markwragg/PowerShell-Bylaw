---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Only Policy and the utility cmdlets are exported; inner keywords exist only inside Policy

## Context and Problem Statement

The DSL uses short, generic command names (`Field`, `Resource`, `When`, `Each`, `Effect`, `Param`, `Arm`). Authors will often have Pester and other modules loaded in the same session. Exporting these names globally would pollute the session and risk clashing with other modules. How do we make the keywords available to the code inside a `Policy` scriptblock without exporting them?

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

* **Exported:** `Policy`, `Build-Bylaw`, `Update-BylawAliasCache`, `Update-BylawRoleCache`, and in Milestone 4 `Initiative` ([ADR-0033](0033-initiatives.md)). `ConvertFrom-PolicyJson`, the decompiler, follows in Milestone 5.
* **Mechanism (revised after the spike).** `Policy` creates a small wrapper scriptblock inside the module, then rebinds it to the session state the author's `Policy` body is bound to, which is the caller's. It does this by setting the internal `ScriptBlock.SessionStateInternal` property through reflection, the same technique Pester uses. The wrapper runs in a new child scope of the caller. It defines each inner keyword there as a function whose body is the module-bound keyword implementation, so the keywords run in module scope with access to the compiler state. The wrapper then dot-sources the author's body into the same scope. When the wrapper's scope ends, normally or through an exception, the keywords disappear with it, so no cleanup code is needed. An author's own function with the same name is hidden inside `Policy` and visible again afterwards.
  * The first design added and removed the functions through `$PSCmdlet.SessionState`. The spike showed that this resolves to the **module's** session state, so it would have overwritten and then deleted the module's own functions.
  * The wrapper sets `$ErrorActionPreference = 'Stop'` for the body, so that PowerShell errors (for example a misspelt `-Bee` parameter) become terminating. `Policy` can then catch and report them.
* **Context stack.** Each keyword checks that its parent is valid, for example that `Field` is inside `When`, `Require` or `Each`, and that `Properties` is directly inside `Policy`. A violation does not throw. It records a diagnostic (`BYL1002`) with the file, line and keyword, and the build continues, so that every error is reported in one run (ADR-0013).
* **Outside `Policy`.** On import, the module registers a `CommandNotFoundAction` handler that recognises Bylaw keyword names. It replaces the generic error with "BYL1001: '`Field`' is a Bylaw keyword and can only be used inside a Policy block". The handler chains to any previously registered handler and is removed when the module is removed.
  * Known limitation: the handler only runs when no command of that name exists. Outside a `Policy`, a keyword name exported by another installed module resolves to that module's command (for example psake's `Properties`). Inside a `Policy` the keyword always wins, because it is defined in the nearest scope.
  * The keywords were originally `Item` and `Expr`. They were renamed to `Element` and `Arm` because, outside a `Policy`, `Item` resolved to `Get-Item` (PowerShell retries unknown commands with a `Get-` prefix) and `Expr` resolved to the native `expr` program on macOS and Windows.
* Nested `Policy` blocks are a compile error (`BYL1003`).

### Consequences

* Good, because the session stays clean, and file-level variables and helper functions work inside policies.
* Good, because misuse gives clear, located errors.
* Bad, because `Get-Help Field` and argument completers don't work outside a running policy. Help will be provided as `about_Bylaw_Keywords`. Editor completion (planned for later) will need a separate mechanism, such as registered completers or a language-server extension.
* Bad, because it depends on an internal PowerShell property (`ScriptBlock.SessionStateInternal`). Pester has relied on the same property for many years, which lowers the risk. A unit test fails loudly if a PowerShell release removes or changes it. The spike passed on Windows. CI runs the keyword tests on Linux and macOS.

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
