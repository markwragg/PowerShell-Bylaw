---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Multiple Require blocks and multiple Must statements combine with AND

## Context and Problem Statement

A policy can have several `Require` blocks, and a `Require` (or `Each`) block can contain several `Must` statements. How are they combined?

## Considered Options

* AND at both levels
* OR between `Require` blocks, AND inside each block
* An explicit combinator keyword required everywhere

## Decision Outcome

Chosen option: "AND at both levels", because a compliant resource must meet *every* stated requirement. That matches how people read a list of requirements.

* `Require A { m1; m2 }` and `Require B { m3 }` mean compliant = `m1 AND m2 AND m3`.
* After inversion (ADR-0002), the violation is `anyOf[NOT m1, NOT m2, NOT m3]`, flattened into a single `anyOf`.
* The same rule applies to `Must` statements inside `Each`.
* Language version 1.0 has no OR keyword inside `Require`. An alternative such as "A or B is acceptable" needs either two policies or a future `AnyOf { }` keyword. The IR already supports `AnyOf` groups, so adding one later is additive.

### Consequences

* Good, because the semantics are simple and predictable.
* Good, because each `Require` description gives a named, documented reason for compliance.
* Bad, because "either/or" requirements cannot be expressed in 1.0 without the `Arm` escape hatch.

### Confirmation

Golden test: multiple `Require` blocks with multiple `Must` statements in one block.
