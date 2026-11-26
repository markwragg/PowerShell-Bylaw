---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# DenyAction and Manual are keywords that take the place of Effect

## Context and Problem Statement

`denyAction` blocks an action, currently only deletion, on matching resources. `manual` lets owners attest compliance by hand, and is used by regulatory compliance initiatives. Both need a small `details` block. How are they written, and what does the compiler check?

## Decision Drivers

* The same shape as `Modify` (ADR-0024): an effect with details has its own keyword, in place of `Effect`.
* Mistakes that Azure accepts but that make the policy do nothing should fail the build or warn.

## Considered Options

* A keyword per effect, with parameters for the details
* `Effect DenyAction -Details @{ ... }`

## Decision Outcome

Chosen option: "A keyword per effect, with parameters for the details", because it matches `Modify` and each detail can be validated.

### DenyAction

```powershell
DenyAction Delete -CascadeBehavior Deny
```

* The action is positional and required. Learn: "The only supported action today is `DELETE`." It is emitted as `"actionNames": ["delete"]`. Other actions are a compile error.
* `-CascadeBehavior Deny` or `Allow` emits `"cascadeBehaviors": { "resourceGroup": "deny" }` (or `"allow"`). It's omitted when not set, and Azure's default is `deny`. Learn: it is "only supported in policy definitions with mode set to `indexed`", so using it with any other `Mode` is a compile error.
* The effect is emitted as `DenyAction`.
* Warning: a `Resource` type that DenyAction never applies to. Learn lists `Microsoft.Authorization/policyAssignments`, `Microsoft.Authorization/denyAssignments`, `Microsoft.Blueprint/blueprintAssignments`, `Microsoft.Resources/deploymentStacks`, `Microsoft.Resources/subscriptions` and `Microsoft.Authorization/locks`.

### Manual

```powershell
Manual -DefaultState Unknown
```

* `-DefaultState` is `Unknown`, `Compliant` or `NonCompliant`. It is emitted as `"defaultState": "Unknown"`, `"Compliant"` or `"Non-compliant"`, the spellings Learn uses. Without it, there is no `details` block, and Azure's default is `Unknown`.
* The effect is emitted as `Manual`.

### Both

* `-Effect (Param Effect)` makes the effect a parameter. Its allowed values may be the keyword's effect and `Disabled`, and nothing else. A literal effect gets a generated EPAC effect parameter with those two values (ADR-0023).
* `Effect DenyAction` and `Effect Manual` are compile errors that point to the keywords.
* A policy has exactly one of `Effect`, `Modify`, `DenyAction`, `Manual`, `Append`, `AuditIfNotExists` or `DeployIfNotExists`.

### Consequences

* Good, because each effect is validated as fully as `Modify`.
* Bad, because there are more keywords. They are named after the effects, so they're easy to find.

### Confirmation

Unit tests cover each option, each error and warning, and the generated effect parameter. Golden tests cover both keywords in EPAC and plain JSON.

## Pros and Cons of the Options

### A keyword per effect

* Good, because the details are typed and checked.
* Bad, because each new Azure effect needs a new keyword.

### `Effect` with a details hashtable

* Good, because there is one keyword.
* Bad, because the details aren't validated, and it is unlike `Modify`.

## More Information

* [DenyAction effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-deny-action), [Manual effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-manual)
* Related: [ADR-0017](0017-effects-in-language-version-1-0.md), [ADR-0024](0024-modify-effect.md)
