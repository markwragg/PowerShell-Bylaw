---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Effects supported in language version 1.0, and how they are validated

## Context and Problem Statement

The effect produces the policy rule's `then` block. Which effects are valid in language version 1.0, how are they written, and what does the compiler check?

## Considered Options

* `Audit`, `Deny` and `Disabled` with `Effect`, and each effect that needs a `details` block through its own keyword
* `Effect` for every effect, with a details hashtable
* Only the effects without details

## Decision Outcome

Chosen option: "`Audit`, `Deny` and `Disabled` with `Effect`, and each effect that needs a `details` block through its own keyword", because each detail can then be validated, and the keyword reads as what the policy does.

| Effect | Written as | ADR |
|---|---|---|
| `Audit`, `Deny`, `Disabled` | `Effect Deny`, or `Effect (Param Effect)` | this ADR |
| `Modify` | `Modify -Role ... { operations }` | [ADR-0024](0024-modify-effect.md) |
| `DenyAction` | `DenyAction Delete` | [ADR-0028](0028-denyaction-and-manual.md) |
| `Manual` | `Manual` | [ADR-0028](0028-denyaction-and-manual.md) |
| `Append` | `Append { Add operations }` | [ADR-0029](0029-append-effect.md) |
| `AuditIfNotExists`, `DeployIfNotExists` | `AuditIfNotExists -Type ... { }`, `DeployIfNotExists -Type ... { }` | [ADR-0030](0030-if-not-exists-effects.md), [ADR-0031](0031-deployment-templates.md) |

* `Effect Deny` emits a literal effect. `Effect (Param Effect)` emits `[parameters('effect')]`.
* Effect names are case-insensitive in the DSL and emitted in canonical casing (`Audit`, `Deny`, `Disabled`).
* `Effect` with the name of an effect that has its own keyword, such as `Effect Modify`, is a compile error that points to the keyword.
* A policy has exactly one of `Effect`, `Modify`, `Append`, `DenyAction`, `Manual`, `AuditIfNotExists` and `DeployIfNotExists`. None is a compile error (BYL1006), and so is a second one (BYL1026).
* Each keyword sets its own effect, and takes `-Effect (Param Effect)` to make it a parameter instead.
* When the effect is a parameter, the compiler checks that:
  * the parameter exists and is of type `String`,
  * `AllowedValues` is set and contains only effects the rule supports: `Audit`, `Deny` and `Disabled` with `Effect`; for a keyword, its own effect, `Disabled`, and any other values its ADR lists,
  * `Default`, if set, is one of `AllowedValues`.

### Consequences

* Good, because every effect the compiler accepts is fully validated.
* Bad, because each effect with details adds a keyword. They are named after the effects, so they're easy to find.

### Confirmation

Unit tests cover each valid effect, each rejected effect and each parameter check.

## Pros and Cons of the Options

### A keyword per effect with details

* Good, because each detail is typed and checked.
* Bad, because each new Azure effect needs a new keyword.

### `Effect` with a details hashtable

* Good, because there is one keyword.
* Bad, because the details aren't validated.

### Only the effects without details

* Good, because there is little to build.
* Bad, because 82 of the 149 custom definitions in the Azure Landing Zones Library couldn't be written.
