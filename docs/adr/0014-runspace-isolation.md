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
* Files are compiled one after another in Milestone 1. Running them in parallel with a runspace pool is possible later and wouldn't change the output, because results are collected in a fixed order (ADR-0013).

### Consequences

* Good, because no state can leak between files, and output doesn't depend on file order.
* Bad, because importing the module once per file costs time. Mitigation: the release build merges the module into a single `.psm1` to speed up import, and a pool can be added later.
* Bad, because `.bylaw.ps1` files are still arbitrary code with the caller's permissions. Isolating them in a runspace is not a security sandbox. The README must say that compiling a policy file runs it, which matters for CI on pull requests from forks.

### Confirmation

A test defines a variable and a function in file A and checks they're not visible in file B. A test checks that the reported file and line numbers point into the source file.
