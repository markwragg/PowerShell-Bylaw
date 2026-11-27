---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Count is piped to Must, for field counts and value counts

## Context and Problem Statement

`Each` covers one kind of count: every element of an array meets a condition, emitted as `count(where: violation) greater 0`. Azure Policy can do more with `count`, and the Azure Landing Zones Library uses it. Of the 67 ALZ definitions whose effects Bylaw supports, 11 use conditions Bylaw can't express:

* 7 count an array without `where`: "the array is empty", "has at least one element".
* 3 use a *value count*: they count the members of a list, such as a parameter of mandatory tags, that meet a condition, using `current()`.
* 1 uses a `[*]` field outside a count, which Bylaw rejects (BYL2005) because negating it isn't safe.

Learn also documents comparing a count with other numbers: "exactly one", "at least two", or the length of a parameter. How are these written?

## Decision Drivers

* A count is a number, so it should be tested with the same operators as other numbers.
* What to count is a selection, not a requirement, so it is written as is, like `When`.
* `Each` stays the simple way to say "every element".

## Considered Options

* A `Count` keyword whose result is piped to `Must`
* More `Each` variants: `EachOf`, `AnyOf` over elements, `None`
* Only the planned raw-condition escape hatch

## Decision Outcome

Chosen option: "A `Count` keyword whose result is piped to `Must`".

```powershell
Require 'At least one IP rule' {
    Count networkAcls.ipRules[*] | Must -BeGreaterThan 0
}

Require 'At most two rules allow inbound traffic' {
    Count securityRules[*] -Where {
        Field direction | Must -Be 'Inbound'
        Field access | Must -Be 'Allow'
    } | Must -BeLessOrEqual 2
}

Require 'Every mandatory tag is set' {
    Count -Value (Param MandatoryTags) -Name tagName -Where {
        Tag (Current tagName) | Must -Exist
    } | Must -Be (Arm "[length(parameters('mandatoryTags'))]")
}
```

### Count

* `Count path[*]` is a field count, emitted as `{ "count": { "field": "<alias>[*]" } }`. `Count -Value <array> [-Name <name>]` is a value count. The array is a literal, a `Param` or an `Arm` expression.
* `-Where { }` selects the elements to count, emitted as `count.where`. Without it, every element is counted. Statements in `-Where` are emitted **as written**, like `When`: they select elements, they aren't requirements, so they aren't inverted and get no missing-field guards. As in `When`, `-IfPresent` and `-Strict` are compile errors there. `AnyOf`, `AllOf` and nested `Count` work inside. `Each` isn't allowed inside `-Where`: use a nested `Count`.
* In a field count's `-Where`, field names are relative to the element, as in `Each`, and `Element` is the element itself.
* `Count` is piped to `Must` like a value condition (ADR-0025). In `Require` the assertion is inverted and never guarded, since a count is never missing. In `When` it is emitted as written. The operators are `-Be`, `-BeIn` and the four comparisons. Others are a compile error.
* `Count` works in `When`, `Require` and `Each`, and in an existence condition (ADR-0030). Inside `Each`, a field count's path is relative to the element, which gives the nested counts Learn allows.

### Current

* `Current name` is `[current('name')]`, the member a value count is at. `Current` with no name is `[current()]`, allowed only when the count isn't inside another count, as Learn requires. In a field count's `-Where`, `Current` is `[current('<array alias>[*]')]`.
* `Current` is allowed only inside a `-Where`. It can be used as a value, as a `Tag` name, as in `Tag (Current tagName)`, and as the subject of a value condition.
* `-Name` is letters and digits. Learn makes it required when the count is inside another count. Without it, Azure uses `default`.

### Limits

* At most 10 value counts per rule, and at most 100 iterations for a literal array, nested counts included, as Learn documents. Exceeding either is a compile error. The existing limit of 5 field counts per array (BYL3050) also counts `Count`.

### Relationship to Each and `[*]` fields

* `Each path[*] { P }` stays, and is the same as `Count path[*] -Where { violation of P } | Must -Be 0`. The README shows both.
* A `[*]` field outside `Each` or `Count` stays a compile error (BYL2005). Its message now suggests `Count`.

### Details

* A count is compared with whole numbers: literals, an `Integer` parameter (an `Array` one for `-BeIn`), or `Arm`.
* `Current name` refers to the value count with that `-Name` around it, so a nested count can use an outer count's member. A `Count -Value` inside another count, including inside `Each`, needs `-Name`.
* `Tag (Current name)` emits `[concat('tags[', current('name'), ']')]`, and `ResourceGroupTag (Current name)` emits `[resourceGroup().tags[current('name')]]`, as the ALZ tag policies write them. Both need a value count.
* `Element` in `-Where` is only for a field count; a value count's member is `Current`.

### Diagnostics

* Front end: BYL1047 (neither or both of a path and `-Value`, a path without `[*]`, or a `-Value` that is not a list), BYL1048 (`-Name` on a field count, or not letters and digits), BYL1049 (a nested value count without `-Name`), BYL1050 (`Current` outside `-Where`, with a name no count has, or without a name in a nested value count), BYL1051 (an operator a count doesn't take, or `-IfPresent` or `-Strict` on a count), BYL1052 (`Count` used as a value). `-IfPresent` and `-Strict` in `-Where` are BYL1010, an empty `-Where` is BYL1013, and `Each` in `-Where` is BYL1002.
* Validation: BYL3100 (a count compared with something other than a whole number), BYL3101 (a `-Value` parameter that is not an `Array`), BYL3052 (more than 10 value counts in a rule), BYL3053 (more than 100 iterations over literal lists, nested counts multiplied).

### Consequences

* Good, because every count form Learn documents can be written, and tested with the familiar operators.
* Good, because `Each` stays simple for the common case.
* Bad, because `-Where` is written as is, unlike `Require`. Its name says it selects, and the README explains the difference.

### Confirmation

Unit tests cover field and value counts with and without `-Where`, each operator in `When` and `Require`, nested counts, `Current` in each form and place, and the limits. Golden tests cover the ALZ patterns: an empty-array check, a value count over a parameter compared with its length, and a nested count.

## Pros and Cons of the Options

### `Count` piped to `Must`

* Good, because one keyword covers every count form.
* Bad, because there are now two ways to say "every element".

### More `Each` variants

* Good, because each pattern gets a readable name.
* Bad, because there is a keyword per pattern, and comparisons with numbers other than 0 still aren't covered.

### Escape hatch only

* Good, because there is nothing new to learn.
* Bad, because counts are common enough that raw JSON would be the usual way to write them, with no validation.

## More Information

* [Count expressions](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-policy-rule#count), [Authoring policies for arrays](https://learn.microsoft.com/azure/governance/policy/how-to/author-policies-for-arrays)
* Related: [ADR-0004](0004-strict-missing-field-behaviour.md), [ADR-0025](0025-value-conditions.md), [ADR-0026](0026-anyof-and-allof-groups.md)
