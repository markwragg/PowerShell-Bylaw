---
status: accepted
date: 2026-11-28
decision-makers: Bylaw maintainers
---

# Condition writes a raw policy condition, for what the language can't express

## Context and Problem Statement

Language version 1.0 covers the conditions the Azure Landing Zones Library uses most, but not everything Azure Policy accepts: for example a `field()` call inside a `count`'s `where`, a `value` condition over an expression Bylaw can't check, an operator on a field the alias snapshot doesn't know the shape of, or a combination the inversion can't reproduce exactly. Without a way to write those, a policy that needs one can't be written in Bylaw at all, and the decompiler (ADR-0039) would fail the whole definition for one condition. ADR-0032 deferred this as "the raw-condition escape hatch". How does a policy include a condition as raw JSON, and how does it fit with Bylaw's inversion?

## Decision Drivers

* A policy can always be written, even when a part of it can't be expressed in the language.
* The rest of the policy keeps its checks and readability: the escape hatch is per condition, not per policy.
* It's obvious in the source where the escape hatch is used, and what it does.
* Bylaw doesn't pretend to understand what it can't: no inversion or guards it can't get right.

## Considered Options

* `Condition`, a statement that takes a raw condition, with `-Violation` in `Require`
* `Condition`, inverted with `not` in `Require`
* A raw `if` for the whole policy

## Decision Outcome

Chosen option: "`Condition`, a statement that takes a raw condition, with `-Violation` in `Require`".

### The keyword

```powershell
When {
    Condition @{ value = "[requestContext().apiVersion]"; less = '2021-01-01' }
}

Require 'Diagnostic logs are kept' {
    Condition -Violation @{
        count = @{ field = 'Microsoft.Insights/diagnosticSettings/logs[*]'; where = @{ field = 'Microsoft.Insights/diagnosticSettings/logs[*].enabled'; equals = 'false' } }
        greater = 0
    }
}
```

* `Condition` takes one policy condition as a hashtable, an `[ordered]` hashtable, or a JSON string, in the same shape as policy JSON: field conditions, value conditions, `count`, `allOf`, `anyOf` and `not`. It is a statement, like `Must`, and can be used wherever `Must` can: `When`, `Require`, `Each`, `AnyOf`, `AllOf` and `Count -Where`.
* **In `When` and `Count -Where`**, where statements are emitted as written, it is emitted as written.
* **In `Require` and `Each`**, statements describe the compliant state and are inverted. Bylaw can't invert a raw condition correctly in general (ADR-0002, ADR-0004), so `Condition` there must say which form it is:
  * `Condition -Violation @{ ... }` is the condition that finds a non-compliant resource, and is emitted as written, as that `Require`'s violation. This is what the decompiler writes, since the JSON holds violations.
  * `Condition -Compliant @{ ... }` is the compliant state, and is emitted as `{ "not": ... }`, with no missing-field guards: the author is responsible for how a missing field behaves.
  * Without either switch, `Condition` in `Require` or `Each` is an error, so the choice is always visible.
* Values can include `Param` and `Arm`, which are emitted as their expressions, so parameters are still declared and checked.

### What is checked

* The hashtable is a condition: exactly one of the condition forms, with known operator names, and values with a JSON form.
* Field names that are plain strings are resolved like `Field`, so an unknown alias is still an error (BYL2001), unless `-AllowUnknownAlias` is set. Short names are expanded, and full names are kept.
* `Param` references must be declared (BYL3020).
* The condition counts towards Azure's limits: conditions per rule, field counts per array, value counts (ADR-0032).
* Nothing else: Bylaw doesn't check that the condition means what the `Require` says.

### Consequences

* Good, because no policy is impossible to write, and the decompiler can convert a definition with one unusual condition and keep everything else readable.
* Good, because the escape hatch is easy to find, with `Condition`, and the switch says what the condition means.
* Bad, because a raw condition loses Bylaw's inversion and missing-field handling. The README will say to prefer the language, and the decompiler reports each use, so they can be replaced as the language grows.
* Bad, because a second way to write a condition exists. Diagnostics (BYL3xxx) can suggest the language form when a raw condition has one, such as a plain `field` and `equals`.

### Confirmation

Unit tests cover `Condition` in each block, with each switch and each value form, alias resolution inside it, the errors, and the limits. Golden tests cover a raw condition in `When`, `Require` and `Count -Where`.

## Pros and Cons of the Options

### `Condition`, with `-Violation` in `Require`

* Good, because the decompiler can write exactly what the JSON has, and a reader sees that it is a violation.
* Bad, because authors must think about which form they're writing.

### `Condition`, inverted with `not` in `Require`

* Good, because it reads like the rest of `Require`: compliant state.
* Bad, because decompiled conditions would need `not` around their violation, emitted as `not(not(...))` and simplified, which is harder to read, and the missing-field behaviour would be easy to get wrong.

### A raw `if` for the whole policy

* Good, because it is simple.
* Bad, because one unusual condition would lose every check and all readability for the whole policy.
