---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Must can test an expression as well as a field, emitting a value condition

## Context and Problem Statement

Azure Policy conditions can test the result of an expression instead of a field: `{ "value": "[resourceGroup().tags['owner']]", "notEquals": "" }`. Both of Azure's built-in tag-inheritance policies need this, to apply only when the resource group has the tag. Until now, only `Field` and `Element` could be piped to `Must`. How should value conditions be written?

## Decision Drivers

* The tag inheritance golden test should reproduce the built-in policies' logic.
* No new keyword if an existing one can express it.
* Missing-field guards (ADR-0004) are about fields. An expression has no `exists` to guard with.

## Considered Options

* `ResourceGroupTag`, `Param` and `Arm` can be piped into `Must`
* A `Value` keyword that wraps the expression: `Value (ResourceGroupTag Owner) | Must -Not -Be ''`
* Value conditions only through `Arm` on the right-hand side, with no left-hand form

## Decision Outcome

Chosen option: "`ResourceGroupTag`, `Param` and `Arm` can be piped into `Must`", because the expression helpers already exist and the pipeline form reads naturally.

```powershell
When {
    ResourceGroupTag CostCenter | Must -Not -Be ''
}
```

emits:

```json
{
  "value": "[resourceGroup().tags['CostCenter']]",
  "notEquals": ""
}
```

* Allowed in `When` and `Require`, at the top level or inside `AnyOf` and `AllOf` (ADR-0026).
* Not allowed inside `Each` in this release. A value condition inside `where` is evaluated once per element and usually needs `current()`. That needs its own design.
* Every operator is allowed except `-Exist`.
* **No missing-field guards.** In `Require`, the condition is inverted as usual, but no `exists` guard is added. `-IfPresent` and `-Strict` are compile errors.
* A literal piped into `Must` is a compile error, because it is constant.
* The errors for value conditions are `BYL1024`. A field used as a value, such as `Must -Be (Tag Owner)`, is `BYL1025`, and `ResourceGroupTag` with `-BeIn` is `BYL3017`.
* A missing resource group tag compares as an empty string, which is what the built-in policies rely on with `notEquals: ""`. It hasn't been measured directly, so the sandbox script will check it.

### Consequences

* Good, because tag inheritance can be written exactly as Azure's built-in policies do it.
* Good, because no new keyword is added.
* Bad, because an author might expect `-IfPresent` to work. The error message explains that expressions have no missing state.

### Confirmation

Unit tests cover each subject in `When` and `Require`, inversion without guards, and the errors for `-Exist`, `-IfPresent`, `-Strict`, a literal subject, and a value condition inside `Each`.

## Pros and Cons of the Options

### Expression helpers piped into `Must`

* Good, because it reuses existing keywords.
* Bad, because `Must` accepts more kinds of input, so its error messages need care.

### A `Value` keyword

* Good, because a value condition is obvious when reading.
* Bad, because it adds a keyword that only wraps another one.

### Right-hand side only

* Good, because there is nothing to add.
* Bad, because it can't express "the resource group has this tag".

## More Information

* [Policy rule conditions: value](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-policy-rule#value)
* Built-in "Inherit a tag from the resource group" and "Inherit a tag from the resource group if missing" in the Azure/azure-policy repository.
