---
status: proposed
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Compile-time validation of parameter declarations and usage

## Context and Problem Statement

Azure accepts definitions whose parameter usage is wrong, for example an `Array` parameter used with `equals`, or a `String` parameter used with `in`. The mistake only shows up at evaluation time, as an error or a policy that never matches. Bylaw knows each parameter's type and every place it is used, so it can catch many of these mistakes. How strict should it be?

## Decision Drivers

* Catch definite mistakes at compile time.
* Avoid false positives that push authors towards `Arm`.

## Considered Options

* Errors for definite mismatches, warnings for likely mistakes
* Warnings only
* No validation beyond checking that the parameter exists

## Decision Outcome

Proposed: "Errors for definite mismatches, warnings for likely mistakes".

**Errors:**

* `Param X` where `X` is not declared.
* An `Array` parameter used with an operator that takes a single value: `-Be`, `-BeLike`, `-Match`, `-MatchCase`, `-ContainText`, `-ContainKey`, or the comparison operators.
* A non-`Array` parameter used with `-BeIn`.
* A `Boolean` or `Object` parameter used with `-BeLike`, `-Match`, `-MatchCase` or `-ContainText`.
* A comparison operator used with a parameter that isn't `Integer`, `Float`, `String` or `DateTime`.
* A `Default` that doesn't match the declared `Type`, or isn't in `AllowedValues`.
* `AllowedValues` whose items don't match the declared `Type`.
* Effect parameter rules (ADR-0017).

**Warnings:**

* A parameter that is declared but never used.
* A `String` parameter with no `AllowedValues` that is used as an effect. This is already an error under ADR-0017, so it is listed here only for completeness.

Parameter types follow Azure: `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float`, `DateTime`. The one-line `Parameter` form infers `Type` from `-Default` and `-AllowedValues` when it isn't given. If inference is ambiguous, the build fails and asks for an explicit `-Type`.

### Consequences

* Good, because the most common parameter bugs become build errors.
* Bad, because `Arm` usage can't be checked. Parameters referenced only inside `Arm` count as used, and are not validated.

## Pros and Cons of the Options

### Errors and warnings

* Good, because it gives the best defect detection.
* Bad, because the rule set has to be maintained.

### Warnings only

* Good, because it never blocks a build.
* Bad, because warnings get ignored in CI.

### Existence only

* Good, because it is trivial.
* Bad, because it misses the bugs that matter.
