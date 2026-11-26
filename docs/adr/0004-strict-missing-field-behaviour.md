---
status: accepted
date: 2026-11-26
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

The guard is **omitted** when the inverted operator already gives the required result on a missing field. Omitting a guard is only an optimisation, because a redundant guard never changes the result.

When several conditions in the same `anyOf` need the same guard, for example several negated checks on one field in one `Require`, the guard is emitted once. A repeated guard in an `anyOf` never changes the result.

### Observed behaviour on a missing field

These results come from two sandbox runs, on 2026-11-25 and 2026-11-26. A missing tag and a missing alias property of the resource's own type gave identical results. The full table is in [assets/0004-missing-field-results.md](assets/0004-missing-field-results.md).

* Every operator pair is an exact complement on a missing field: one side is true and the other is false. Every pair is also a complement on a present value.
* These operators are **false** on a missing field: `equals`, `in`, `like`, `match`, `matchInsensitively`, `contains`, `containsKey`, `greater`, `less` and `exists: true`.
* Their complements are **true** on a missing field: `notEquals`, `notIn`, `notLike`, `notMatch`, `notMatchInsensitively`, `notContains`, `notContainsKey`, `lessOrEquals`, `greaterOrEquals` and `exists: false`.
* The comparison operators are the surprising case. `greaterOrEquals` and `lessOrEquals` are *true* on a missing field, with string and numeric operands alike, and no error is raised. They behave as "not less" and "not greater".
* **Comparing types that don't match** (a numeric operand against a present string value) gives the compliance state `Error`. The bundled alias snapshot doesn't record property types, so this can't be caught at compile time.
* **An empty value (`""`) is present, not missing.** `exists` is true for it, and every other operator treats it as an ordinary string. Bylaw's "missing" means *absent*. An author who wants a non-empty value writes `Must -Not -Be ''` in addition.

This gives a single guard rule:

* **Strict:** add `exists: false` when the inverted operator is one that is false on a missing field.
* **Lenient:** add `exists: true` when the inverted operator is one that is true on a missing field.

### Truth table (language version 1.0)

| Compliant (`Must ...`) | Inverted operator | `inv(P)` on missing | Strict violation | Lenient violation | Verified |
|---|---|---|---|---|---|
| `-Be v` | `notEquals` | true | `notEquals v` | `allOf[exists:true, notEquals v]` | tag, alias |
| `-Not -Be v` | `equals` | false | `anyOf[exists:false, equals v]` | `equals v` | tag, alias |
| `-BeIn a` | `notIn` | true | `notIn a` | `allOf[exists:true, notIn a]` | tag, alias |
| `-Not -BeIn a` | `in` | false | `anyOf[exists:false, in a]` | `in a` | tag, alias |
| `-BeLike p` | `notLike` | true | `notLike p` | `allOf[exists:true, notLike p]` | tag, alias |
| `-Not -BeLike p` | `like` | false | `anyOf[exists:false, like p]` | `like p` | tag, alias |
| `-Match p` | `notMatchInsensitively` | true | `notMatchInsensitively p` | `allOf[exists:true, notMatchInsensitively p]` | tag, alias |
| `-Not -Match p` | `matchInsensitively` | false | `anyOf[exists:false, matchInsensitively p]` | `matchInsensitively p` | tag, alias |
| `-MatchCase p` | `notMatch` | true | `notMatch p` | `allOf[exists:true, notMatch p]` | tag, alias |
| `-Not -MatchCase p` | `match` | false | `anyOf[exists:false, match p]` | `match p` | tag, alias |
| `-ContainText s` | `notContains` | true | `notContains s` | `allOf[exists:true, notContains s]` | tag, alias |
| `-Not -ContainText s` | `contains` | false | `anyOf[exists:false, contains s]` | `contains s` | tag, alias |
| `-ContainKey k` | `notContainsKey` | true | `notContainsKey k` | `allOf[exists:true, notContainsKey k]` | tag, alias |
| `-Not -ContainKey k` | `containsKey` | false | `anyOf[exists:false, containsKey k]` | `containsKey k` | tag, alias |
| `-BeGreaterThan n` | `lessOrEquals` | true | `lessOrEquals n` | `allOf[exists:true, lessOrEquals n]` | tag, alias |
| `-Not -BeGreaterThan n` | `greater` | false | `anyOf[exists:false, greater n]` | `greater n` | tag, alias |
| `-BeGreaterOrEqual n` | `less` | false | `anyOf[exists:false, less n]` | `less n` | tag, alias |
| `-Not -BeGreaterOrEqual n` | `greaterOrEquals` | true | `greaterOrEquals n` | `allOf[exists:true, greaterOrEquals n]` | tag, alias |
| `-BeLessThan n` | `greaterOrEquals` | true | `greaterOrEquals n` | `allOf[exists:true, greaterOrEquals n]` | tag, alias |
| `-Not -BeLessThan n` | `less` | false | `anyOf[exists:false, less n]` | `less n` | tag, alias |
| `-BeLessOrEqual n` | `greater` | false | `anyOf[exists:false, greater n]` | `greater n` | tag, alias |
| `-Not -BeLessOrEqual n` | `lessOrEquals` | true | `lessOrEquals n` | `allOf[exists:true, lessOrEquals n]` | tag, alias |
| `-Exist` | `exists: false` | true | `exists: false` | `-IfPresent` is an error | tag, alias |
| `-Not -Exist` | `exists: true` | false | `exists: true` | `-IfPresent` is an error | tag, alias |

"tag, alias" in the Verified column means the row was measured on a missing **tag** (`tags['x']`) and on a missing **alias property** of the resource's own type, with the same result.

### Consequences

* Good, because policies fail closed unless the author opts out explicitly.
* Good, because the common cases compile to the same minimal JSON a careful human would write.
* Bad, because the guard-omission rule relies on observed Azure behaviour, not documented behaviour. If Azure changes, the table and the golden files change. The verification script can be re-run at any time.
* Bad, because the element-level default inside `Each` differs from the top-level default. This must be documented clearly in the README.

### Confirmation

* Unit tests cover every row of the table, in strict and lenient form.
* **Empirical verification.** [build/verify-missing-field](../../build/verify-missing-field/README.md) deploys one Audit-effect policy per operator and field case to a sandbox subscription. The first run (2026-11-25) gave valid results: every control answer on the present tag matched expectations. That run verified every row of the table for a missing tag.
* **Missing alias properties.** The second run (2026-11-26) added `Microsoft.Network/routeTables/subnets`, which is missing on the route table. Every row gave the same result as the missing tag. The cross-type alias case (`Microsoft.Storage/storageAccounts/publicNetworkAccess` against a route table) again had no compliance state, more than 12 hours after deployment. Azure doesn't evaluate a condition on another type's alias, so that case says nothing about missing values.
* Properties that are present but `null` remain unmeasured.

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
* Milestone 3: in an existence condition, which isn't inverted, the same rules are applied to the compliant form, so a missing field still doesn't satisfy a requirement unless `-IfPresent` is used ([ADR-0031](0031-if-not-exists-effects.md)). A `Count -Where` selection is written as is and gets no guards ([ADR-0033](0033-count-expressions.md)).
