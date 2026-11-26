---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Each source file is compiled in a fresh runspace

## Context and Problem Statement

`.bylaw.ps1` files are PowerShell scripts. They can define variables and functions, import modules and change preferences. If they all ran in one session, state could leak between files, and the output would depend on file order.

## Considered Options

* A fresh runspace per file
* One shared runspace, cleaned between files
* The caller's session

## Decision Outcome

Chosen option: "A fresh runspace per file".

* Each file gets a runspace created from `InitialSessionState.CreateDefault2()`, with Bylaw imported from the same module path as the caller's copy. No profile scripts run in it.
* The file is invoked **by path**, not as script text, so `$MyInvocation` and error records carry the real file name and line numbers (ADR-0006).
* All compiler passes and the emitter run inside that runspace. Only plain data comes back: emitted text, diagnostics, and result data for `-PassThru` (ADR-0006).
* The runspace is disposed after use, including on failure.
* The runspace inherits the current working directory, set to the folder that contains the file, so relative paths inside the file resolve predictably.
* Several files compile at once, each in its own fresh runspace. `Build-Bylaw -ThrottleLimit` sets how many: by default the number of processors, at most 16, and `1` compiles one at a time. A `RunspacePool` is not used, because it reuses runspaces and state could then leak from one file into the next.
* Results are collected in file order (ADR-0013), not completion order, so output, warnings and errors are the same at any throttle limit.
* The alias snapshot is read once by the caller and passed to every runspace. Runspaces only read it, so sharing it across threads is safe.

### Consequences

* Good, because no state can leak between files, and output doesn't depend on file order.
* Bad, because importing the module once per file costs time: about 0.85 seconds per file, because each import parses Bylaw afresh (ADR-0006). Mitigation: files compile in parallel. A 12-file build takes 3.8 seconds on 12 processors, against 10.3 seconds one at a time.
* Bad, because files compiling at once share the process. Anything process-wide a file changes, such as environment variables or `[Environment]::CurrentDirectory`, is visible to the files compiling at the same time. Build files like that with `-ThrottleLimit 1`.
* Bad, because `.bylaw.ps1` files are still arbitrary code with the caller's permissions. Isolating them in a runspace is not a security sandbox. The README must say that compiling a policy file runs it, which matters for CI on pull requests from forks.

### Confirmation

A test defines a variable and a function in file A and checks they're not visible in file B. With several files at once, a test checks that no file sees state set by another. A test checks that the reported file and line numbers point into the source file. Tests check that builds at different throttle limits return the same results, warnings and errors in the same order, including when later files finish first.

## More Information

Parallel compilation depends on the two rules in ADR-0006. Before those rules, two runspaces importing Bylaw at the same moment defined the classes from one shared parse, and the definitions mixed: for example, a `BylawPolicy` ended up deriving from the other runspace's `BylawNode`. Now each runspace parses its own copy, so nothing is shared to race on. Before adopting parallel compilation, 30 builds of 12 files, 12 at a time and flushing PowerShell's script cache between rounds, all succeeded with identical output.
