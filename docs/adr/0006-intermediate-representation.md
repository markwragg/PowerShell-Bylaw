---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Keywords build an IR of PowerShell classes; passes transform it; emitters serialise it

## Context and Problem Statement

Keywords could write JSON fragments directly, but then it would be hard to add inversion, alias resolution, validation, multiple output formats and, later, decompiling. What should the internal architecture look like?

## Decision Drivers

* Each compiler concern should be testable on its own.
* Several emitters (EPAC, plain JSON, later Bicep).
* Decompiling (JSON to DSL) in Milestone 3 needs an IR that can represent any supported policy JSON.
* Precise error locations during later compiler passes, not just in the keywords.

## Considered Options

* IR as PowerShell classes
* IR as C# types compiled with `Add-Type`
* Hashtables and PSCustomObjects with no formal IR

## Decision Outcome

Chosen option: "IR as PowerShell classes".

Pipeline: **front-end** (keywords) produces the IR, then the **passes** run (validation, alias resolution, inversion, flattening), then an **emitter** produces an ordered document, then the **canonical writer** (ADR-0009) produces bytes.

Rules:

* No keyword writes JSON.
* Every IR node carries a `SourceLocation` (file, line, column, keyword), which compiler errors report.
* **Lossless.** The IR keeps the DSL names (for example the short alias as written), `Require` descriptions, whether a condition came from `When` or `Require`, declaration order, and `Arm` text exactly as written. It also has `Not` and generic group nodes that the front-end never produces, but which the decompiler needs.
* Passes return new or annotated nodes. They don't change the source IR in place, so the "as written" form remains available.
* **Classes and runspaces.** PowerShell class types are compiled per runspace, so IR objects can't be passed between runspaces without losing their type identity. Since every file is compiled in its own runspace (ADR-0014), all passes and the emitter run **inside** that runspace. Only plain data crosses back to the caller: emitted text, diagnostics and summary PSCustomObjects.
* All IR classes live in one ordered source file, because class definitions that reference each other must be parsed together.

### Consequences

* Good, because passes and emitters are small and unit-testable.
* Good, because contributors can read and change the IR without knowing C#.
* Bad, because PowerShell classes have known limitations: no reload without restarting the session, type identity per runspace, limited interfaces. `-PassThru` therefore returns plain objects, not IR instances.
* Bad, because PowerShell's per-process caches don't keep classes apart between imports or runspaces. Two rules follow, found when `Build-Bylaw` started failing after about 1,000 scripts had run in a session (on macOS, and only by luck not elsewhere):
  * **Module files are parsed afresh on every import, never dot-sourced.** PowerShell caches dot-sourced scripts per process and shares them between runspaces. With shared parses, every runspace used the classes of whichever import defined them first. Their methods ran in that runspace, which could be the caller's session or a `Build-Bylaw` runspace that had already been disposed. When the cache filled up and was flushed, some cached functions stayed bound to an earlier import's classes ('Cannot convert BylawPolicy to BylawPolicy'). `src/Bylaw.psm1` and the packaged `Bylaw.psm1` both use `Parser.ParseFile` and `GetScriptBlock()`, so each import defines its own classes. This makes each runspace import slower, by about 0.2 seconds.
  * **Bylaw classes are never used inside generic or array type names.** PowerShell also caches type names such as `List[BylawDiagnostic]` per process, and they keep pointing at the first import's class ('Cannot find an overload for "Add"'). Collections are `List[object]` and `[object[]]`. A repository test enforces this.
  * A `Build-Bylaw` test flushes the script cache and builds again. The package task builds the examples with the packaged module in a new process.
  * The class attribute `[NoRunspaceAffinity()]` would also fix the method problem, but it needs PowerShell 7.4, and fresh parsing makes it unnecessary.
* Bad, because files can't be compiled in parallel runspaces of one process (ADR-0014).

### Confirmation

Tests build IR directly, without keywords, to test passes and emitters. A test asserts that no file under `Private/Keywords` calls a JSON serialiser.

## Pros and Cons of the Options

### PowerShell classes

* Good, because it is approachable for the target audience.
* Bad, because of the runspace and reload limitations.

### C# with `Add-Type`

* Good, because types are shared across the whole process and it performs better.
* Bad, because it raises the contribution barrier and adds compile time on import. Revisit this if performance becomes an issue.

### Hashtables

* Good, because there is nothing to define.
* Bad, because there is no structure, no validation and no clear contract between passes.
