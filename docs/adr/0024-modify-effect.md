---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Modify is a block that replaces Effect, with operations that take their field from the pipeline

## Context and Problem Statement

The `modify` effect changes resources when they are created or updated, and through remediation tasks for existing resources. Its `then.details` block has `roleDefinitionIds`, an optional `conflictEffect`, and a list of `operations`. Each operation has `operation` (`addOrReplace`, `add` or `remove`), `field`, `value` (required except for `remove`) and an optional `condition`. How do authors write this in Bylaw, and what does the compiler check?

## Decision Drivers

* It should read like the rest of the DSL: `Must` takes its field from the pipeline.
* The rule and the operations must agree. After remediation, a resource should be compliant. Otherwise it is remediated again on every evaluation and never becomes compliant.
* Mistakes that Azure only reports at deployment or remediation time should fail the build: a missing value, `remove` on a non-tag field, a field that can't be modified.

## Considered Options

* A `Modify` block with pipeline operations: `Tag Environment | AddOrReplace 'Production'`
* A `Modify` block with named parameters: `AddOrReplace -Field (Tag Environment) -Value 'Production'`
* Infer the operations from the `Require` blocks

## Decision Outcome

Chosen option: "A `Modify` block with pipeline operations", because it matches `Must` and reads as a sentence.

```powershell
Modify -Role 'Tag Contributor' {
    Tag Environment | AddOrReplace 'Production'
    Tag CostCenter | Add (ResourceGroupTag CostCenter)
    Tag TempResource | Remove
}
```

### The keyword

* `Modify` takes the place of `Effect`. A policy has exactly one of them. Both, or neither, is a compile error.
* `-Role` is required and takes one or more roles (ADR-0022).
* `-ConflictEffect` is optional and takes `Audit`, `Deny` or `Disabled`. It is emitted in lower case, as Learn documents it, and omitted when it isn't set (Azure's default is `deny`).
* `-Effect (Param Effect)` makes the effect a parameter. Without it, the effect is `Modify`.
* The block holds one or more operations. An empty block is a compile error.

### Operations

| DSL | Emitted `operation` | Value |
|---|---|---|
| `... \| AddOrReplace v` | `addOrReplace` | required |
| `... \| Add v` | `add` | required |
| `... \| Remove` | `remove` | not allowed |

* The field comes from the pipeline: `Field name` or `Tag name`. `Element` is a compile error.
* The value can be a literal, `Param`, `Arm` or `ResourceGroupTag`.
* `-Condition (Arm '[...]')` adds the operation's `condition`.
* Operations are emitted in the order written. Operation names are emitted as `addOrReplace`, `add` and `remove`. Learn uses mixed casing in its examples, and Azure treats them the same.

### Effect

* With a literal effect, EPAC output gets a generated effect parameter (ADR-0023), with allowed values `Modify` and `Disabled` and a default of `Modify`. These are the values built-in Modify policies use.
* A declared effect parameter may allow only `Modify` and `Disabled`. Whether `Audit` is valid on a definition with a `modify` details block isn't documented. It will be measured in the sandbox, and allowed only if it works.
* `Deny` in a Modify policy's effect parameter is a compile error.

### Validation

Errors:

* `Add` or `AddOrReplace` without a value, or `Remove` with one.
* `Remove` on a field that isn't a tag. Learn: "Only tags can be removed."
* A field that isn't a tag and isn't marked Modifiable in the alias snapshot.
* `identity.type` on a resource type other than `Microsoft.Compute/virtualMachines` or `Microsoft.Compute/virtualMachineScaleSets`. Learn says evaluation is skipped for other types, so the policy would silently do nothing.
* A field with `[*]`. Learn doesn't document modifying array elements.
* The same field in more than one operation.
* A `-Condition` that uses `field()`, `resourceGroup()` or `subscription()`, which Learn says aren't supported there.
* A `-Condition` that isn't an `Arm` expression.

Warnings:

* An operation on a tag in a policy whose `Mode` isn't `Indexed`, unless the resource type is `Microsoft.Resources/subscriptions/resourceGroups`. Learn: "For tags, a Modify policy should have mode set to `indexed` unless the target resource is a resource group."
* An operation on a field that no `Require` checks. The rule then doesn't depend on what the operation changes, so remediation can never make the resource compliant.
* `-ConflictEffect Deny`, or no conflict effect, on a policy that modifies an alias rather than a tag. Learn recommends `audit` for definitions that use aliases.

### Consequences

* Good, because the rule and the fix sit side by side and are checked against each other.
* Good, because errors Azure only shows at remediation time fail the build.
* Bad, because authors write the requirement and the operation separately, for example `Must -Be 'Production'` and `AddOrReplace 'Production'`. Inferring one from the other was rejected (below), and the warning catches the common mistake.

### Confirmation

* Unit tests cover each operation, each option, every error and warning above, and the generated effect parameter.
* Golden tests cover tag inheritance in both forms (`add` if missing, `addOrReplace` to match), an alias operation with `-ConflictEffect` and `-Condition`, and `Remove`.
* The sandbox script checks whether `Audit` works as an effect value on a Modify definition.

## Pros and Cons of the Options

### Pipeline operations

* Good, because it is consistent with `Must`.
* Bad, because `Remove` takes no argument, which looks slightly odd at the end of a pipeline.

### Named parameters

* Good, because every part is labelled.
* Bad, because it is longer and unlike the rest of the DSL.

### Inferring operations from `Require`

* Good, because nothing is written twice.
* Bad, because the mapping is ambiguous: `Must -Be` could be `add` or `addOrReplace`, and `Must -BeIn` has no single value to set. It would also hide what the policy changes, which reviewers need to see.

## More Information

* [Modify effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-modify)
* Related: [ADR-0017](0017-effects-in-language-version-1-0.md), [ADR-0022](0022-modify-role-resolution.md), [ADR-0023](0023-epac-schema-conformance.md), [ADR-0025](0025-value-conditions.md)
