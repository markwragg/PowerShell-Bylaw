---
status: proposed
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# AuditIfNotExists and DeployIfNotExists describe the related resource's compliant state

## Context and Problem Statement

`auditIfNotExists` and `deployIfNotExists` check a *related* resource: for a virtual machine, its antimalware extension; for a database, its encryption settings. `details.type` and the optional `name`, `resourceGroupName` and `existenceScope` say which related resources to look at. `details.existenceCondition` says what a related resource must look like. Learn: "If any matching related resource evaluates to true, the effect is satisfied". `deployIfNotExists` adds roles and a template deployment (ADR-0032). 74 of the 149 custom definitions in the Azure Landing Zones Library use `deployIfNotExists`. How are these effects written, and how is the existence condition compiled?

## Decision Drivers

* The existence condition is a *compliant* condition: true means the related resource is fine. Bylaw's `Require` already describes a compliant state, so authors should write it the same way.
* Field names in the existence condition refer to the related resource, so they resolve against its type.
* The same shape as `Modify` (ADR-0024): an effect with details has its own keyword, in place of `Effect`.

## Considered Options

* A keyword per effect, whose block holds `Require` blocks for the related resource
* A `Related` keyword inside `Resource`, plus a separate effect keyword
* The existence condition as raw JSON

## Decision Outcome

Proposed: "A keyword per effect, whose block holds `Require` blocks for the related resource".

```powershell
Resource 'Microsoft.Compute/virtualMachines' {
    When {
        Field storageProfile.osDisk.osType | Must -Be 'Windows'
    }
}

AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' {
    Require 'The antimalware extension is installed' {
        Field publisher | Must -Be 'Microsoft.Azure.Security'
        Field 'Microsoft.Compute/virtualMachines/extensions/type' | Must -Be 'IaaSAntimalware'
    }
}
```

### The resource being evaluated

* `Resource` and `When` select the resources whose related resources are checked, as for any policy.
* `Require` blocks in `Resource` are still allowed and still inverted: a resource that meets them is compliant whatever its related resources are. A resource is non-compliant only if it matches `When`, breaks a `Require`, and has no related resource that meets the existence condition. Most of these policies have no `Require` in `Resource`, so for these two effects BYL3041 ("no Require block") isn't reported.

### The related resource

* `-Type` is required and emitted as `details.type`. It's checked against the alias snapshot like a `Resource` type.
* `-Name`, a literal or an `Arm` or `Param` expression, emits `details.name`. Learn: when `-Type` is the same as the `Resource` type, `name` is required and must be `[field('name')]`, or `[field('fullName')]` for a child resource. Anything else is a compile error. For `AuditIfNotExists`, Bylaw also warns that Learn suggests the `audit` effect instead.
* `-ResourceGroupName` emits `details.resourceGroupName`.
* `-ExistenceScope ResourceGroup` or `Subscription` emits `details.existenceScope`, omitted when not set (Azure's default is `ResourceGroup`). Learn: `resourceGroupName` and `existenceScope` don't apply when the related type is a child of the `Resource` type, so setting either then is a warning.
* `-EvaluationDelay` takes `AfterProvisioning`, `AfterProvisioningSuccess`, `AfterProvisioningFailure`, or an ISO 8601 duration from 0 to 360 minutes, such as `PT30M`. Anything else is a compile error. It's omitted when not set (Azure's default is `PT10M`).

### The existence condition

* The block holds `Require` blocks, which all must hold, as in `Resource`. Inside them, `Field`, `Tag`, `Each`, `AnyOf`, `AllOf`, `Count` (ADR-0033) and value conditions work as they do in a `Resource`. `When` isn't allowed: there is no applicability for a related resource.
* Field names resolve against `-Type`, the related resource. Reserved fields such as `name` and `type` are the related resource's.
* The block is optional. Without it there is no `existenceCondition`, and any related resource of the type satisfies the effect.
* **The existence condition isn't inverted.** The `Require` blocks are emitted as the compliant condition they describe: `Must -Be 'x'` emits `equals 'x'`. This is the one place where `Require` compiles to the compliant form rather than the violation (ADR-0002).
* **Missing fields keep their meaning (ADR-0004).** In `Require`, a missing field doesn't satisfy the requirement, so a related resource without the field doesn't count. The compiler adds `exists: true` where the operator would otherwise be true on a missing field. `-IfPresent` makes a missing field satisfy it, adding `exists: false` where needed. Inside `Each`, element fields stay lenient, and `-Strict` makes them strict. An `Each` emits `count(where: violation) equals 0`, the compliant form of "every element".

### The effect

* `AuditIfNotExists` emits the effect `AuditIfNotExists`. `-Effect (Param Effect)` may allow `AuditIfNotExists` and `Disabled`.
* `DeployIfNotExists` emits the effect `DeployIfNotExists`, and also takes `-Role` (ADR-0022) and a deployment (ADR-0032). `-Effect (Param Effect)` may allow `DeployIfNotExists`, `AuditIfNotExists` and `Disabled`. Two ALZ policies allow all three.
* A literal effect gets a generated EPAC parameter: `AuditIfNotExists` and `Disabled`, or `DeployIfNotExists` and `Disabled`. These are the values built-in and ALZ policies use: 70 of the 74 ALZ DeployIfNotExists policies allow exactly those two.

### Consequences

* Good, because the existence condition reads like any other requirement, and its field names are checked against the right type.
* Good, because missing fields behave the same way inside and outside the existence condition.
* Bad, because `Require` compiles to the compliant form here and to the violation elsewhere. Authors don't see the difference, because both describe the compliant state. The README explains it.

### Confirmation

* Unit tests cover each option and error, field resolution against `-Type`, and the existence condition for each operator, with and without `-IfPresent`, and inside `Each`.
* Golden tests cover an `AuditIfNotExists` and a `DeployIfNotExists` policy in EPAC and plain JSON.
* The sandbox script measures one `AuditIfNotExists` policy: an existence condition on a related resource's property that is missing, to confirm that a missing field doesn't satisfy it.

## Pros and Cons of the Options

### A keyword per effect with `Require` blocks

* Good, because the existence condition is written like the rest of the language.
* Bad, because `Require` has two compilation modes.

### A separate `Related` block

* Good, because the related resource is visually separate from the effect.
* Bad, because the related resource only makes sense with these two effects, so splitting them adds rules about which goes with which.

### Raw JSON

* Good, because it is simple to implement.
* Bad, because nothing is validated, and the condition is the most error-prone part of these policies.

## More Information

* [AuditIfNotExists effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-audit-if-not-exists), [DeployIfNotExists effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-deploy-if-not-exists)
* Related: [ADR-0002](0002-desired-state-semantics.md), [ADR-0004](0004-strict-missing-field-behaviour.md), [ADR-0022](0022-modify-role-resolution.md), [ADR-0032](0032-deployment-templates.md), [ADR-0033](0033-count-expressions.md)
