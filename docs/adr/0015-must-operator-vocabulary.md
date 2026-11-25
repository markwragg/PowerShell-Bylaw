---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Must operator names follow PowerShell expectations, not raw Azure operator names

## Context and Problem Statement

`Must` is deliberately Pester-like, so authors will bring Pester and PowerShell expectations with them. Two Azure operators behave differently from their Pester namesakes:

* Azure `match` is **not** a regular expression. `#` matches a digit, `?` a letter and `.` any character, and every other character matches itself. It is also **case-sensitive**. Pester's `-Match` is a case-insensitive regex. Azure provides `matchInsensitively` for case-insensitive matching.
* Pester's `-Contain` checks whether a collection includes an item. Azure `contains` is a text test on the value, and Learn doesn't document its behaviour on arrays.

## Considered Options

* PowerShell-flavoured names that state the Azure semantics
* The spec's original one-to-one names (`-Match` maps to `match`, `-Contain` maps to `contains`)

## Decision Outcome

Chosen option: "PowerShell-flavoured names that state the Azure semantics".

| DSL | Policy operator | Inverted | Compile-time validation |
|---|---|---|---|
| `-Be v` | `equals` | `notEquals` | `v` must be a single value |
| `-BeIn a` | `in` | `notIn` | `a` must be an array, or an array-typed parameter |
| `-BeLike p` | `like` | `notLike` | at most one `*` in `p` |
| `-Match p` | `matchInsensitively` | `notMatchInsensitively` | `p` is an Azure match pattern, not a regex |
| `-MatchCase p` | `match` | `notMatch` | as above |
| `-ContainText s` | `contains` | `notContains` | no `*` in `s` |
| `-ContainKey k` | `containsKey` | `notContainsKey` | |
| `-Exist` | `exists: true` | `exists: false` | takes no value |
| `-BeGreaterThan n` | `greater` | `lessOrEquals` | |
| `-BeGreaterOrEqual n` | `greaterOrEquals` | `less` | |
| `-BeLessThan n` | `less` | `greaterOrEquals` | |
| `-BeLessOrEqual n` | `lessOrEquals` | `greater` | |
| `-Not` | flips the operator | | |
| `-IfPresent` | lenient missing-field handling (ADR-0004) | | not valid inside `Each`, with `-Exist`, or in `When` |
| `-Strict` | strict missing-field handling inside `Each` (ADR-0004) | | only valid inside `Each` |

* Each `Must` takes exactly one operator. Zero or several is a compile error.
* `Must` takes a field reference (`Field`, or `Element` inside `Each`) from the pipeline. Anything else is a compile error.
* A literal, `Param` or `Arm` is accepted wherever a value is expected.
* A `-Match` or `-MatchCase` pattern that looks like a regex (it contains `^`, `$`, `\d`, `[`, `(` or `+`) produces a warning, because Azure treats those characters literally.

### Consequences

* Good, because the names don't silently mislead Pester users. `-Match` is case-insensitive, as in PowerShell.
* Bad, because the DSL names no longer map one to one onto Azure operator names. The README operator table and `about_Bylaw_Operators` document the mapping.

### Confirmation

Unit tests cover each operator and its inversion, every validation error, and the regex-lookalike warning.

## More Information

* [Policy rule conditions](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-policy-rule#conditions)
