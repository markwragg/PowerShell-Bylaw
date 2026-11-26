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
* A declared effect parameter may allow `Modify`, `Audit` and `Disabled`, and nothing else (`BYL3062`). Learn doesn't document whether `Audit` is valid on a definition with a `modify` details block, so it was measured in the sandbox before being allowed (below).
* `Deny` in a Modify policy's effect parameter is a compile error (`BYL3062`).
* Measured in the sandbox on 2026-11-26:
  * Azure accepts a definition whose effect parameter allows `Modify`, `Audit` and `Disabled`.
  * It refuses to assign it without a managed identity (`ResourceIdentityRequired`), even with the effect set to `Audit`. So choosing Audit doesn't avoid the identity.
  * Assigned with a system-assigned identity and effect `Audit`, it evaluates: the matching resource reported NonCompliant.

### Validation

Errors found while the policy runs:

* `Effect` and `Modify` in the same policy (`BYL1026`). A second `Modify` is `BYL1004`, an empty or missing block `BYL1013`.
* `Add` or `AddOrReplace` without a value, or `Remove` with one (`BYL1027`).
* A `-Condition` that isn't an `Arm` expression (`BYL1028`).
* A `-ConflictEffect` other than `Audit`, `Deny` or `Disabled` (`BYL1029`).
* An `-Effect` that isn't a parameter or an `Arm` expression (`BYL1030`).
* An operation with no field piped to it, or with `Element` or a value piped to it (`BYL1031`).
* No `-Role` (`BYL1032`).

Errors found when compiling:

* A role that isn't in the role map (`BYL3060`), or the same role given twice in any form (`BYL3061`).
* `Remove` on a field that isn't a tag (`BYL3063`). Learn: "Only tags can be removed."
* A field that isn't a tag, isn't `identity.type` and isn't marked Modifiable in the alias snapshot (`BYL3064`). Reserved fields such as `location` can't be modified.
* `identity.type` on a resource type other than `Microsoft.Compute/virtualMachines` or `Microsoft.Compute/virtualMachineScaleSets` (`BYL3065`). Learn says evaluation is skipped for other types, so the policy would silently do nothing. Under `Resource *` the type isn't known, so it isn't checked.
* A field with `[*]` (`BYL3066`). Learn doesn't document modifying array elements.
* The same field in more than one operation (`BYL3067`).
* A `-Condition` that uses `field()`, `resourceGroup()` or `subscription()` (`BYL3068`), which Learn says aren't supported there.

Warnings:

* An operation on a tag in a policy whose `Mode` isn't `Indexed`, unless the resource type is `Microsoft.Resources/subscriptions/resourceGroups` (`BYL3069`). Learn: "For tags, a Modify policy should have mode set to `indexed` unless the target resource is a resource group."
* An operation on a field that no `Require` checks (`BYL3070`). The rule then doesn't depend on what the operation changes, so remediation can never make the resource compliant. `When` conditions don't count, because they decide where the policy applies, not whether a resource is compliant.
* `-ConflictEffect Deny`, or no conflict effect, on a policy that modifies an alias rather than a tag (`BYL3071`). Learn recommends `audit` for definitions that use aliases.

### Consequences

* Good, because the rule and the fix sit side by side and are checked against each other.
* Good, because errors Azure only shows at remediation time fail the build.
* Bad, because authors write the requirement and the operation separately, for example `Must -Be 'Production'` and `AddOrReplace 'Production'`. Inferring one from the other was rejected (below), and the warning catches the common mistake.

### Confirmation

* Unit tests cover each operation, each option, every error and warning above, and the generated effect parameter.
* Golden tests cover tag inheritance in both forms (`add` if missing, `addOrReplace` to match), an alias operation with `-ConflictEffect` and `-Condition`, and `Remove`.
* The sandbox script checks whether `Audit` works as an effect value on a Modify definition. It did on 2026-11-26.

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
