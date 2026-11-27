---
status: proposed
date: 2026-11-27
decision-makers: Bylaw maintainers
---

# Initiative is a top-level keyword like Policy, with Member for each policy it includes

## Context and Problem Statement

An initiative (policy set definition) groups policy definitions so they're assigned together, and passes its own parameters to theirs. Most real policy estates assign initiatives rather than single policies. The Azure Landing Zones Library has 60 custom initiatives with 685 members:

* 430 members (63%) are built-in definitions, referenced by ID. 255 (37%) are custom definitions from the same library.
* 511 members (75%) pin a `definitionVersion`, usually `1.*.*`.
* 2,365 of 2,496 member parameter values (95%) pass an initiative parameter straight through, as `[parameters('x')]`. 106 are ARM expressions, and 25 are literals. In 102 cases, one initiative parameter feeds several members.
* 15 members include a definition that another member of the same initiative also includes, with different parameters and a different reference ID.
* None uses policy definition groups. Groups belong to the Regulatory Compliance feature, which Learn marks as preview.

How is an initiative written in Bylaw?

## Decision Drivers

* An initiative reads like a policy: the same `Properties` and `Parameter` keywords, in the same kind of file.
* Members from the same build are referenced by policy name, the same identity `Policy 'name'` gives them (ADR-0010).
* Built-in members, which are most members, are as easy to include as custom ones.
* Mistakes that Azure only reports at deployment or assignment fail the build instead (ADR-0034).

## Considered Options

* An `Initiative` keyword with a `Member` keyword per member
* Initiatives as a hashtable or data file next to the policies
* A `Policy -Initiative` parameter that adds a policy to a named initiative

## Decision Outcome

Proposed: "An `Initiative` keyword with a `Member` keyword per member".

```powershell
Initiative 'tagging-baseline' {

    Properties @{
        DisplayName = 'Tagging baseline'
        Category    = 'Tags'
        Version     = '1.0.0'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Audit
    Parameter MandatoryTags -Type Array -Default @('CostCenter', 'Owner')

    # A policy from this build, by name.
    Member 'tags-require-mandatory-tags' -Parameters @{
        mandatoryTags = Param MandatoryTags
        effect        = Param Effect
    }

    # A built-in policy, by ID, pinned to its major version.
    Member -Id '/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54' -ReferenceId 'InheritCostCenter' -Version '1.*.*' -Parameters @{
        tagName = 'CostCenter'
    }
}
```

### Initiative

* `Initiative 'name' { }` is exported, like `Policy`, and can be in the same files as policies. Its inner keywords exist only inside it (ADR-0005).
* The name follows ADR-0010. Names are unique across a build, ignoring case, across policies and initiatives together: they are both definition names, and their output files can share a folder (ADR-0035).
* `Properties` takes `DisplayName` (required), `Description`, `Category`, `Version`, `Preview`, `Deprecated` and `Metadata`, with the same rules and limits as for a policy (ADR-0016). `Mode` is a compile error: it belongs to the members.
* `Parameter` declares initiative parameters, as for a policy. A parameter no member uses is a warning (ADR-0021).
* At most 1000 members and 400 parameters, as Learn documents. More is a compile error.
* Only `Properties`, `Parameter`, `Member` and `DefinitionGroup` are allowed inside. An initiative has no rule and no effect.

### Member

* `Member 'policy-name'` includes a policy from the same build, by its `Policy` name, matched ignoring case. Whether it exists is checked once every file has compiled (ADR-0034).
* `Member -Id '/providers/Microsoft.Authorization/policyDefinitions/<guid>'` includes a built-in policy. Any other definition ID, such as a custom definition deployed outside this build, is also accepted: `-Id` emits the ID as written.
* `-ReferenceId` is the member's `policyDefinitionReferenceId`. It defaults to the policy name for a member from the build, and is required for `-Id`. Reference IDs are unique within an initiative, ignoring case. A policy can be a member more than once, with different reference IDs, as 15 ALZ members are.
* `-Parameters @{ name = value }` passes values to the member's parameters. A value is a literal, `Param` (an initiative parameter), `Arm`, or `ResourceGroupTag`. Each is emitted as `{ "value": ... }`. An `[ordered]` hashtable keeps its order, and a plain one is sorted, as for `Deployment -Parameters` (ADR-0031). Names are emitted as written and matched against the member's parameters ignoring case, as ARM does (ADR-0034).
* `-Version '1.*.*'` emits `definitionVersion`. It is a major version, then a minor version or `*`, then a patch or `*`, with an optional `-preview` suffix: `^\d+\.(\d+|\*)\.(\d+|\*)(-preview)?$`. For a member from the build, the pattern must match the policy's `Version` (ADR-0034).
* `-Group` names the member's policy definition groups (`groupNames`).

### DefinitionGroup

* `DefinitionGroup 'name' -DisplayName ... -Category ... -Description ... -AdditionalMetadataId ...` declares a policy definition group. Only the name is required.
* A `Member -Group` value that no `DefinitionGroup` declares is a compile error, and so is a group no member uses.
* The name matches Azure's `policyDefinitionGroups` property and Learn's "policy definition group". `PolicyGroup` was considered, but reads as a group of policies in its own right, which is what an initiative is. Plain `Group` can't be used, because PowerShell's `group` alias for `Group-Object` would run instead of a function of that name (ADR-0005).

### Consequences

* Good, because initiatives and policies are written the same way, in the same files, and checked together.
* Good, because built-in members, most members in practice, need only an ID.
* Bad, because a built-in member's parameters can't be checked offline: Bylaw has no snapshot of built-in definitions. ADR-0034 explains what is checked.

### Confirmation

Unit tests cover each keyword, option and error, references to policies in the same file and in other files, built-in members, repeated members, versions and groups. Golden tests cover an initiative in EPAC and plain JSON.

## Pros and Cons of the Options

### `Initiative` with `Member`

* Good, because it reads like the rest of the language, and each member's options are validated.
* Bad, because it adds a top-level keyword.

### A hashtable or data file

* Good, because an initiative is mostly data.
* Bad, because parameters, versions and groups would be untyped, and errors would have no source location in the DSL.

### `Policy -Initiative`

* Good, because a policy says which initiatives it is in.
* Bad, because built-in members have no `Policy` block, and initiative parameters and groups would have nowhere to go.

## More Information

* [Initiative definition structure](https://learn.microsoft.com/azure/governance/policy/concepts/initiative-definition-structure), [Azure Policy limits](https://learn.microsoft.com/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-policy-limits)
* Related: [ADR-0005](0005-keyword-scoping.md), [ADR-0010](0010-definition-name-stability.md), [ADR-0016](0016-properties-mapping-and-defaults.md), [ADR-0021](0021-parameter-usage-validation.md), [ADR-0034](0034-initiative-member-checks.md), [ADR-0035](0035-initiative-output.md)
