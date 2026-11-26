---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# How Properties keys map into the definition, and their defaults

## Context and Problem Statement

`Properties @{ }` accepts `DisplayName`, `Description`, `Category`, `Version`, `Mode`, `Preview`, `Deprecated` and `Metadata`. Where does each key go, which keys are required, and what are the defaults? Azure has also added a top-level `version` property for custom policy versioning, which is in preview, alongside the customary `metadata.version`.

## Considered Options

* `Version` maps to `metadata.version` only, and `Mode` defaults to `All`
* `Version` maps to both `metadata.version` and `properties.version`
* No default `Mode` (it must be set)

## Decision Outcome

Chosen option: "`Version` maps to `metadata.version` only, and `Mode` defaults to `All`".

| Key | Emitted as | Required | Validation |
|---|---|---|---|
| `DisplayName` | `properties.displayName` | yes | 1 to 128 characters |
| `Description` | `properties.description` | no | at most 512 characters |
| `Mode` | `properties.mode` | no, defaults to `All` | `All` or `Indexed`, ignoring case, emitted as `All` or `Indexed` |
| `Version` | `metadata.version` | no | SemVer `major.minor.patch`, optionally with a `-preview` suffix |
| `Category` | `metadata.category` | no | string |
| `Preview` | `metadata.preview` | no | boolean |
| `Deprecated` | `metadata.deprecated` | no | boolean |
| `Metadata` | merged into `metadata` | no | hashtable. A key that clashes with a generated key (`version`, `category`, `preview`, `deprecated`) is an error, and so is `deployedBy` (ADR-0011). Each value is at most 1024 characters once serialised. |

* Unknown keys fail the build. The error lists the valid keys and suggests the closest match.
* Resource provider modes (such as `Microsoft.Kubernetes.Data`) are not supported in language version 1.0. They have different rule and effect requirements and would need their own ADR.
* `All` is the default because it is what Azure PowerShell uses. Policies on tags or location usually want `Indexed`, so the compiler warns when `Mode` is `All` and the rule references `tags` or `location`.
* The top-level `properties.version` is not emitted in 1.0, because custom policy versioning is still in preview. Revisit this when it is generally available.

### Consequences

* Good, because the output follows established built-in policy conventions.
* Bad, because authors can't use Azure's preview versioning feature yet.

### Confirmation

Unit tests cover each key, each validation rule and the defaults.

## More Information

* [Definition structure basics](https://learn.microsoft.com/azure/governance/policy/concepts/definition-structure-basics)
