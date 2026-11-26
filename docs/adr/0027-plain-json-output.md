---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Plain JSON output is a policy definition with name and properties, emitted as written

## Context and Problem Statement

EPAC is the default output (ADR-0011). Other tools, such as `New-AzPolicyDefinition`, the Azure CLI, Bicep's `loadJsonContent()` and Terraform, take the plain definition JSON instead. What shape should the second format have, and which EPAC rules does it keep?

## Decision Drivers

* Usable as input to the common deployment tools without editing.
* The same determinism as EPAC output (ADR-0009).
* EPAC-specific rules stay in the EPAC emitter (ADR-0023).

## Considered Options

* `{ "name", "properties" }`, the layout of Azure's built-in definitions without `id`
* The `properties` object only
* The full ARM resource, with `type` and `apiVersion`

## Decision Outcome

Chosen option: "`{ "name", "properties" }`", because it is the layout Azure itself publishes built-in definitions in, and it keeps the name with the definition.

```json
{
  "name": "storage-deny-public-network-access",
  "properties": {
    "displayName": "...",
    "policyType": "Custom",
    "mode": "All",
    "description": "...",
    "metadata": { },
    "parameters": { },
    "policyRule": { }
  }
}
```

* Selected with `Build-Bylaw -Format PlainJson`. Files are named `<policy name>.json`, as for EPAC.
* There is no `$schema`, `id` or top-level `version`.
* **Emitted as written:**
  * A literal effect stays literal: `Effect Deny` emits `"effect": "Deny"`, with no generated parameter.
  * `Category` and `Version` are optional.
  * `description`, `metadata` and `parameters` are omitted when they are empty.
  * Parameters without a `DisplayName` get no generated one.
* Everything else is shared with EPAC: key order, formatting, parameter casing, the policy rule, `Modify` details, and all language-level validation. EPAC's own checks (`BYL4xxx`) don't apply, so an `Arm` effect is accepted.

### Consequences

* Good, because the output can be passed straight to Azure tooling.
* Good, because the two formats differ only in the envelope and in EPAC's generated content.
* Bad, because a policy that builds as plain JSON may fail as EPAC, for example without a `Category`. That is intended: EPAC's rules are stricter.

### Confirmation

* Golden tests compile the policies in `tests/GoldenPlainJson/` to plain JSON and compare them byte for byte. `tests/Golden/GoldenRoots.psd1` lists each golden folder with its format, for the tests and for `build.ps1 -Task UpdateGolden`.
* A test checks that the plain JSON `policyRule` is identical to the EPAC one wherever the effect is the same, for `Effect` and for `Modify`.
* Azure doesn't publish a JSON schema for this layout, so a structural test checks the golden files: `name` then `properties`, the required properties, no keys outside the layout, and a `policyRule` with `if` and `then.effect`.
