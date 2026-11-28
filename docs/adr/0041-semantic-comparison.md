---
status: accepted
date: 2026-11-28
decision-makers: Bylaw maintainers
---

# Definitions are compared by meaning, through a normal form and a truth table over their conditions

## Context and Problem Statement

The decompiler proves each file by compiling it and comparing the result with the input (ADR-0039), and the round-trip tests do the same over every golden file, example and Azure Landing Zones definition. The two are rarely identical as text: Bylaw orders conditions in its own way, flattens nested groups, writes full alias names, chooses `notEquals` over `not` + `equals`, and may emit `notEquals 0` where the input had `greater 0` on a count. A textual comparison would report almost every pair as different. How does Bylaw decide that two definitions mean the same thing, without claiming more than it can prove?

## Decision Drivers

* **Sound:** "equivalent" is only reported when it is true. A false "equivalent" would let the decompiler write a policy that means something else.
* Useful: the comparison proves the equivalences that Bylaw's own compiling and Azure's documented semantics produce, so real round trips pass.
* A difference is reported with where it is, so it can be fixed.
* No Azure connection.

## Considered Options

* A normal form, then a truth table over the conditions as propositions
* A normal form only
* Comparing behaviour with the local evaluator on generated resources (ADR-0038)

## Decision Outcome

Chosen option: "A normal form, then a truth table over the conditions as propositions".

### What is compared

* **The rule:** `if` by meaning, as below; `then` exactly, after normalising (key order, effect names' case, role definition IDs as GUIDs, and ARM expressions with insignificant whitespace removed).
* **Everything else** exactly, after normalising key order and the documented case-insensitivity: `mode`, `displayName`, `description`, `metadata` (ignoring `deployedBy`), and `parameters`, with type names' case and the generated metadata that Bylaw adds. An initiative's members are compared as a set by reference ID, with their parameters and groups.

### The normal form

Each condition tree is rewritten, by rules that hold in Azure Policy:

1. **Fields:** full alias names, compared ignoring case, as Azure does. Reserved fields keep their names.
2. **Negation:** `notEquals`, `notIn`, `notLike`, `notMatch`, `notMatchInsensitively`, `notContains`, `notContainsKey` and `exists: false` become `not` around their positive operator, and `not` is pushed to the leaves by De Morgan's laws.
3. **Groups:** nested `allOf` in `allOf`, and `anyOf` in `anyOf`, are flattened; a group of one is unwrapped; children are sorted by their canonical JSON; duplicates are removed.
4. **Values:** strings in `equals`, `in`, `like` and `contains` compared ignoring case, as Azure does; `match` and `matchInsensitively` as documented; `in` with one value is `equals`; booleans and numbers in their canonical form.
5. **Counts:** a comparison of a count with a whole number becomes a range over the non-negative integers, so `greater 0`, `greaterOrEquals 1` and `notEquals 0` are the same, and `lessOrEquals 0` and `equals 0` are their negation. The `where` is normalised recursively.

### The proof

After normalising, the two `if` conditions are compared:

* **Identical** normal forms are `Equivalent`.
* Otherwise, the distinct leaf conditions (atoms) are treated as independent propositions, and both formulas are evaluated for every assignment of them. If they agree on every one, the conditions are equivalent whatever the atoms mean, so the result is `Equivalent`. This catches what the normal form misses, such as absorption, `A or (A and B)` being `A`, and a requirement split differently between `When` and `Require`.
* If they disagree on some assignment, the result is **`Different`**, with that assignment as an example, e.g. "with `publicNetworkAccess equals Disabled` false and `kind in [...]` true, the input matches and the output doesn't". The atoms may not really be independent, for example `exists: false` and `equals 'x'` on the same field can't both be true, so a pair reported as different may be equivalent. The result says so, as **`Different as written`**, and the decompiler treats it as a failure.
* The truth table is limited to 16 atoms in each comparison, 65,536 assignments; above that, the result is **`Unproven`**, which also counts as a failure. Atoms inside a `count`'s `where` are compared inside that `count`, so they don't add to the outer table.

### Consequences

* Good, because "equivalent" is always true, and a difference comes with an example.
* Good, because the comparison needs nothing but the two definitions, and is fast.
* Bad, because the independence of atoms makes the check conservative: a correct conversion that relies on a relationship between atoms, such as a guard, is reported as different. The decompiler avoids this by reproducing guards exactly (ADR-0039), and the local evaluator, if built (ADR-0038), could settle such cases later.

### Confirmation

Unit tests cover each normalisation rule, with pairs that must be equivalent and pairs that must not; the truth table, including absorption and the 16-atom limit; and the report of the first difference. The round-trip tests use it on every golden file and example.

## Pros and Cons of the Options

### A normal form, then a truth table

* Good, because it is sound and proves the common rearrangements.
* Bad, because it can't use relationships between atoms.

### A normal form only

* Good, because it is simpler.
* Bad, because many correct round trips, such as different `When` and `Require` splits, would fail.

### Comparing behaviour with the local evaluator

* Good, because it would understand relationships between atoms.
* Bad, because the evaluator isn't built, and testing on generated resources shows equivalence only for the resources generated, not in general.
