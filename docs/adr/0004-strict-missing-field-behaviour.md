---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Missing fields fail requirements by default (strict), with explicit leniency

## Context and Problem Statement

A resource often doesn't have the property a requirement checks: older API versions, optional properties, unset defaults. Should a missing field count as compliant or non-compliant?

Inversion makes this subtle. For some operators the inverted form already fires on a missing field, and for others it silently doesn't:

* `Must -Be 'Disabled'` inverts to `notEquals 'Disabled'`. A missing value is "not equal to Disabled", so the violation fires, which is strict.
* `Must -Not -Be 'X'` inverts to `equals 'X'`. A missing value doesn't equal `X`, so the violation does *not* fire, which is lenient by accident.

Microsoft Learn does not document how `equals`, `notEquals`, `in`, `like`, `contains` and the comparison operators evaluate against a missing scalar field. It says comparison operators throw an error on a type mismatch, but not what happens with null. The only documented missing-value behaviour is for arrays: a missing array referenced with `[*]` behaves as an empty collection. A condition on a `[*]` field evaluates to true for an empty array. See [Author policies for array properties](https://learn.microsoft.com/azure/governance/policy/how-to/author-policies-for-arrays).

## Decision Drivers

* Security policies should fail closed. A resource that doesn't state a secure setting should not pass.
* Output should stay minimal. Guards should only be added where they change the result.
* Behaviour must be predictable without knowing Azure Policy's undocumented null handling.

## Considered Options

* Strict by default, `-IfPresent` for leniency, guards added by the compiler where needed
* Lenient by default, `-Required` for strictness
* No guards: whatever the inverted operator happens to do

## Decision Outcome

Chosen option: "Strict by default, with `-IfPresent`", with these scoping rules:

| Context | Default | Opt-out / opt-in |
|---|---|---|
| `Require` (top level) | **Strict**: a missing field is a violation | `Must -IfPresent`: a missing field is compliant |
| Inside `Each` (element fields) | **Lenient**: a missing element field is compliant | `Must -Strict`: a missing element field is a violation |
| `When` | Not inverted, so no guards. Operators are emitted as written. | `-IfPresent` and `-Strict` are compile errors in `When` |
| The `Each` array itself | A missing or empty array is **compliant** (no element violates). This is Azure's native behaviour: `count` is 0. | Add `Field path | Must -Exist` in a `Require` if the array must exist |

Using `-IfPresent` inside `Each`, or `-Strict` outside it, is a compile error, because the switch would be redundant and may indicate a misunderstanding.

`Each` elements are lenient by default so that the common case ("no element has a bad value") compiles to the obvious `count`/`where` shape, as in the storage golden test.

### Compilation rule

For a compliant condition `P` on field `f`:

* **Strict:** violation = `anyOf[ {f exists: false}, inv(P) ]`
* **Lenient:** violation = `allOf[ {f exists: true}, inv(P) ]`

The guard is **omitted** when the inverted operator already gives the required result on a missing field. Omitting a guard is only an optimisation: adding a redundant guard never changes the result. So the compiler only omits a guard for operators whose missing-field behaviour is in the "omit" column below. Comparison operators always keep their guards, because their null behaviour is not documented and they may throw an error.

### Truth table (language version 1.0)

`inv(P)` on missing = what the inverted operator is *expected* to return for a missing field.

| Compliant (`Must ...`) | Inverted operator | `inv(P)` on missing | Strict violation | Lenient violation | Verified |
|---|---|---|---|---|---|
| `-Be v` | `notEquals` | true | `notEquals v` | `allOf[exists:true, notEquals v]` | pending |
| `-Not -Be v` | `equals` | false | `anyOf[exists:false, equals v]` | `equals v` | pending |
| `-BeIn a` | `notIn` | true | `notIn a` | `allOf[exists:true, notIn a]` | pending |
| `-Not -BeIn a` | `in` | false | `anyOf[exists:false, in a]` | `in a` | pending |
| `-BeLike p` | `notLike` | true | `notLike p` | `allOf[exists:true, notLike p]` | pending |
| `-Not -BeLike p` | `like` | false | `anyOf[exists:false, like p]` | `like p` | pending |
| `-Match p` | `notMatchInsensitively` | true | `notMatchInsensitively p` | `allOf[exists:true, notMatchInsensitively p]` | pending |
| `-Not -Match p` | `matchInsensitively` | false | `anyOf[exists:false, matchInsensitively p]` | `matchInsensitively p` | pending |
| `-MatchCase p` | `notMatch` | true | `notMatch p` | `allOf[exists:true, notMatch p]` | pending |
| `-Not -MatchCase p` | `match` | false | `anyOf[exists:false, match p]` | `match p` | pending |
| `-ContainText s` | `notContains` | true | `notContains s` | `allOf[exists:true, notContains s]` | pending |
| `-Not -ContainText s` | `contains` | false | `anyOf[exists:false, contains s]` | `contains s` | pending |
| `-ContainKey k` | `notContainsKey` | true | `notContainsKey k` | `allOf[exists:true, notContainsKey k]` | pending |
| `-Not -ContainKey k` | `containsKey` | false | `anyOf[exists:false, containsKey k]` | `containsKey k` | pending |
| `-BeGreaterThan n` | `lessOrEquals` | unknown | `anyOf[exists:false, lessOrEquals n]` | `allOf[exists:true, lessOrEquals n]` | pending |
| `-BeGreaterOrEqual n` | `less` | unknown | `anyOf[exists:false, less n]` | `allOf[exists:true, less n]` | pending |
| `-BeLessThan n` | `greaterOrEquals` | unknown | `anyOf[exists:false, greaterOrEquals n]` | `allOf[exists:true, greaterOrEquals n]` | pending |
| `-BeLessOrEqual n` | `greater` | unknown | `anyOf[exists:false, greater n]` | `allOf[exists:true, greater n]` | pending |
| `-Exist` | `exists: false` | n/a | `exists: false` | `-IfPresent` is an error | pending |
| `-Not -Exist` | `exists: true` | n/a | `exists: true` | `-IfPresent` is an error | pending |

The `-Not` forms of the comparison operators follow the same pattern. `-Not -BeGreaterThan n` inverts to `greater n`, with guards in both modes.

### Consequences

* Good, because policies fail closed unless the author opts out explicitly.
* Good, because the common cases compile to the same minimal JSON a careful human would write.
* Bad, because the guard-omission column relies on observed Azure behaviour, not documented behaviour. If verification shows a different result, the table and the golden files change.
* Bad, because the element-level default inside `Each` differs from the top-level default. This must be documented clearly in the README.

### Confirmation

* Unit tests cover every row of the table, in strict and lenient form.
* **Empirical verification is pending.** A verification script (added in a follow-up step) deploys one Audit-effect policy per row to a sandbox subscription, against a resource that lacks the field. It records the compliance results in the "Verified" column. It also checks whether `exists` treats a property that is present but `null` the same as a missing one. Until then, the "Verified" column reads `pending`.

## Pros and Cons of the Options

### Strict by default with `-IfPresent`

* Good, because it fails closed, which suits a governance tool.
* Bad, because it needs a guard table and empirical verification.

### Lenient by default

* Good, because the output is closer to the raw inverted operator.
* Bad, because it fails open: a missing security setting passes.

### No guards

* Good, because it is the simplest compiler.
* Bad, because the result depends on which operator was used. `-Be` is strict and `-Not -Be` is lenient, which is invisible to authors.

## More Information

* [Policy rule conditions](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-policy-rule#conditions)
* [Author policies for array properties](https://learn.microsoft.com/azure/governance/policy/how-to/author-policies-for-arrays)
* Related: [ADR-0002](0002-desired-state-semantics.md), [ADR-0015](0015-must-operator-vocabulary.md)
