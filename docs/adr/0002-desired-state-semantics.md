---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Authors describe the compliant state; the compiler inverts it

## Context and Problem Statement

An Azure Policy `if` block describes the *non-compliant* state: when it evaluates to true, the effect fires. Authors naturally think in terms of what a good resource looks like, and hand-inverting conditions, especially `count`/`where`, is a common source of bugs. How should Bylaw map author intent onto `policyRule.if`?

## Decision Drivers

* Authors should write the rule the way they would explain it ("public network access is disabled").
* The emitted JSON must stay readable and look like idiomatic hand-written policy.
* The transformation must be mechanical and testable.

## Considered Options

* Desired-state authoring, inverted by the compiler, with negation pushed inward
* Desired-state authoring, emitted as `{ "not": { ... } }` around the requirements
* Violation-state authoring, as in raw Azure Policy

## Decision Outcome

Chosen option: "Desired-state authoring, inverted by the compiler, with negation pushed inward".

The compiled rule is:

```
if = allOf[
  type condition            (omitted for Resource *)
  When conditions...        (emitted as written, not inverted)
  NOT( R1 AND R2 AND ... )  (Require blocks, see ADR-0003)
]
then = effect
```

`NOT(...)` is never emitted as a `not` wrapper. It is pushed inward:

* De Morgan: `NOT(a AND b)` becomes `anyOf[NOT a, NOT b]`, and `NOT(a OR b)` becomes `allOf[NOT a, NOT b]`.
* Operators are inverted using the table in [ADR-0015](0015-must-operator-vocabulary.md), for example `equals` becomes `notEquals`.
* `Each path[*] { P }` means "every element satisfies P". Its negation is "at least one element violates P", which is emitted as `{ "count": { "field": "<path>[*]", "where": NOT P }, "greater": 0 }`. The negation is pushed into `where` with the same rules.
* Missing-field guards are added as described in [ADR-0004](0004-strict-missing-field-behaviour.md).

Every operator Bylaw supports in language version 1.0 has an inverse, so `not` is never needed. The IR keeps a `Not` node anyway, so that a future decompiler can read hand-written JSON that uses `not`. Emitters only produce `not` for IR that cannot be pushed further. That cannot happen in 1.0, and if it ever does it is a compiler bug, caught by tests.

Edge cases:

* **No `Require` blocks.** This is allowed. Every resource that matches the type and `When` conditions is non-compliant, which is how a "deny this resource type" policy is written. The compiler emits a warning so the omission is visible.
* **Empty `Require` or `Each` block.** This is a compile error.
* **Single-element groups** are unwrapped and nested same-kind groups are merged (flattening pass).

### Consequences

* Good, because authors write what "good" looks like and the compiler handles the inversion, including the easy-to-get-wrong `count` form.
* Good, because the output reads like idiomatic policy JSON (see the storage golden test).
* Bad, because the emitted JSON no longer mirrors the DSL statement by statement. The IR keeps provenance (which `Require` each condition came from) so tooling and the decompiler can map between them.

### Confirmation

Unit tests check each inversion rule. Golden tests check complete compiled rules, starting with `storage-deny-public-network-access`.

## Pros and Cons of the Options

### Inverted with negation pushed inward

* Good, because the output is idiomatic and easy to review.
* Bad, because the compiler must know an exact inverse for every operator.

### `not` wrapper

* Good, because it is trivial to implement.
* Bad, because the output is harder to read, and `not` around `[*]` fields is easy to misunderstand.

### Violation-state authoring

* Good, because it is a one-to-one mapping with no inversion risk.
* Bad, because it removes one of Bylaw's main reasons to exist.
