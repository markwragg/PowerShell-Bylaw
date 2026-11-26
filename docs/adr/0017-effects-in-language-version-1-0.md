---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Effects supported in Milestone 1, and how they are validated

## Context and Problem Statement

`Effect value` produces the `then` block. Which effects are valid in Milestone 1, and what does the compiler check?

## Considered Options

* `Audit`, `Deny` and `Disabled` only (`Modify` in Milestone 2, the `IfNotExists` effects later)
* All Azure effects from the start

## Decision Outcome

Chosen option: "`Audit`, `Deny` and `Disabled` only".

* `Effect Deny` emits a literal effect. `Effect (Param Effect)` emits `[parameters('effect')]`.
* Effect names are case-insensitive in the DSL and emitted in canonical casing (`Audit`, `Deny`, `Disabled`).
* When the effect is a parameter, the compiler checks that:
  * the parameter exists and is of type `String`,
  * `AllowedValues` is set and contains only effects the rule supports,
  * `Default`, if set, is one of `AllowedValues`.
* Effects that need a `details` block (`Append`, `Modify`, `AuditIfNotExists`, `DeployIfNotExists`, `DenyAction`, `Manual`) are compile errors in 1.0, with a message saying which milestone adds them. The IR's `EffectNode` already has room for `details`, so adding them later only adds things.
* A policy without an `Effect` is a compile error.

### Consequences

* Good, because the Milestone 1 scope is small and every effect it accepts is fully validated.
* Bad, because there is no `Append`. Users who need it use `Modify` from Milestone 2, which Azure recommends over `Append` anyway.

### Confirmation

Unit tests cover each valid effect, each rejected effect and each parameter check.
