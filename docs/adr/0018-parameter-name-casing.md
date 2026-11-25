---
status: proposed
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Parameter name casing in emitted JSON

## Context and Problem Statement

Authors declare parameters in PowerShell style (`Parameter Effect`, `Parameter AllowedLocations`). Built-in policies and EPAC guidance use camelCase (`effect`, `allowedLocations`), and EPAC recommends that the effect parameter is always called `effect`. How should DSL names map to JSON parameter names?

## Decision Drivers

* The output should match built-in and EPAC conventions.
* The mapping must be predictable: no surprising transformations of acronyms.
* Existing definitions with fixed parameter names must be representable, for the decompiler and for migration.

## Considered Options

* Lower-case the first character, with a `JsonName` override
* Emit names exactly as written
* Full camelCase conversion with acronym handling

## Decision Outcome

Proposed: "Lower-case the first character, with a `JsonName` override".

* `Effect` becomes `effect`, `AllowedLocations` becomes `allowedLocations`, and `VMSku` becomes `vMSku`.
* The hashtable form of `Parameter` accepts `JsonName` to set the emitted name exactly, for example `@{ Name = 'VmSku'; JsonName = 'vmSku' }`. The decompiler sets `JsonName` whenever the original name doesn't round-trip through the rule.
* `Param Effect` refers to parameters by their **DSL** name, ignoring case.
* Two parameters whose emitted names collide, ignoring case, is a compile error.

### Consequences

* Good, because the common case matches built-in conventions with no extra syntax.
* Bad, because names that start with an acronym come out awkwardly (`vMSku`) unless `JsonName` is set. A compile-time warning could suggest `JsonName` when a name starts with two capitals.

## Pros and Cons of the Options

### Lower-case the first character, with an override

* Good, because the rule is simple to explain, with an escape hatch.
* Bad, because of the acronym edge case.

### Exactly as written

* Good, because there is no surprise at all.
* Bad, because the output looks unlike built-in policies, and `Effect` would go against EPAC's guidance unless authors write `Parameter effect`, which reads oddly in PowerShell.

### Full camelCase with acronym handling

* Good, because it gives the nicest output.
* Bad, because the heuristics (`VMSku` to `vmSku`, but what about `IPv6Range`?) are unpredictable.
