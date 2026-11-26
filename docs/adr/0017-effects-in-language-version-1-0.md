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
* The other effects need a `details` block, so each has its own keyword in place of `Effect` (Milestone 3): `DenyAction` and `Manual` (ADR-0029), `Append` (ADR-0030), `AuditIfNotExists` and `DeployIfNotExists` (ADR-0031, ADR-0032). `Effect` with any of their names is a compile error that points to the keyword. Each keyword's effect parameter may allow its own effect, `Disabled`, and the values its ADR lists.
* A policy has exactly one of `Effect`, `Modify`, `DenyAction`, `Manual`, `Append`, `AuditIfNotExists` and `DeployIfNotExists`. None is a compile error.

### Consequences

* Good, because every effect the compiler accepts is fully validated.
* Bad, because each effect with details adds a keyword. They are named after the effects.

### Confirmation

Unit tests cover each valid effect, each rejected effect and each parameter check.
