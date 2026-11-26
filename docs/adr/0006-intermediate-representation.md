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
* Bad, because PowerShell caches type names per process. A type name that contains a Bylaw class, such as `List[BylawDiagnostic]` or `BylawCondition[]`, keeps pointing at the old class after Bylaw's classes are defined again, for example after PowerShell flushes its script cache. Code then fails with errors such as 'Cannot find an overload for "Add"'. Bylaw classes are therefore never used inside generic or array type names: collections are `List[object]` and `[object[]]`. A repository test enforces this, and a `Build-Bylaw` test flushes the script cache and builds again.
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
