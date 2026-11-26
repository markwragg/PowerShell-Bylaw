---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Effects supported in language version 1.0, and how they are validated

## Context and Problem Statement

`Effect value` produces the `then` block. Which effects are valid in language version 1.0, and what does the compiler check?

## Considered Options

* `Audit`, `Deny` and `Disabled` with `Effect`, and `Modify` through its own keyword (Milestone 2). The `IfNotExists` effects come later.
* All Azure effects from the start

## Decision Outcome

Chosen option: "`Audit`, `Deny` and `Disabled` with `Effect`, and `Modify` through its own keyword".

* `Effect Deny` emits a literal effect. `Effect (Param Effect)` emits `[parameters('effect')]`.
* Effect names are case-insensitive in the DSL and emitted in canonical casing (`Audit`, `Deny`, `Disabled`, `Modify`).
* `Modify` is written with the `Modify` block, not `Effect Modify`, because it needs a `details` block (ADR-0024). `Effect Modify` is a compile error that points to the `Modify` keyword.
* When the effect is a parameter, the compiler checks that:
  * the parameter exists and is of type `String`,
  * `AllowedValues` is set and contains only effects the rule supports: `Audit`, `Deny` and `Disabled` with `Effect`, and the values in ADR-0024 with `Modify`,
  * `Default`, if set, is one of `AllowedValues`.
* The other effects that need a `details` block (`Append`, `AuditIfNotExists`, `DeployIfNotExists`, `DenyAction`, `Manual`) are compile errors, with a message saying they aren't supported yet. The IR's `EffectNode` has room for `details`, so adding them later only adds things.
* A policy without an `Effect` or `Modify` is a compile error.

### Consequences

* Good, because every effect the compiler accepts is fully validated.
* Bad, because there is no `Append`. Users who need it use `Modify`, which Azure recommends over `Append` anyway.

### Confirmation

Unit tests cover each valid effect, each rejected effect and each parameter check.
