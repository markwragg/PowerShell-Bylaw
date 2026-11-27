---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# EPAC policy definition files are the default output, one file per policy

## Context and Problem Statement

Bylaw's output has to be consumed by a deployment tool. Which format is the default, how are files laid out, and how will new formats be added?

## Considered Options

* The EPAC definition file format as the default, with plain definition JSON as a second emitter and an interface designed for Bicep later
* Plain ARM definition JSON only
* Bicep only

## Decision Outcome

Chosen option: "The EPAC definition file format as the default".

### File shape (`-Format Epac`, the default)

```json
{
  "$schema": "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json",
  "name": "storage-deny-public-network-access",
  "properties": {
    "displayName": "...",
    "policyType": "Custom",
    "mode": "All",
    "description": "...",
    "metadata": { "version": "1.0.0", "category": "Storage" },
    "parameters": { "effect": { ... } },
    "policyRule": { "if": { ... }, "then": { ... } }
  }
}
```

(The canonical writer expands the objects shown inline here, per ADR-0009.)

* `$schema` is always included, so editors validate the file against the EPAC schema.
* `policyType: Custom` is included, as in the EPAC template.
* `id` is never emitted, because EPAC ignores it.
* `metadata.deployedBy` is never emitted. EPAC adds it at deploy time, and setting it in the file overrides EPAC's value.
* Where the effect is parameterised, EPAC recommends naming the parameter `effect` (see ADR-0018).

### Layout

* One file per policy, named `<name>.json`. Initiatives (Milestone 4) can be written to a folder of their own, as EPAC needs ([ADR-0035](0035-initiative-output.md)).
* The output mirrors the source folder structure: `<Path>/storage/a.bylaw.ps1` writes its policies to `<OutputPath>/storage/<name>.json`. A file that contains several policies writes them side by side in the mirrored folder.
* Bylaw never deletes files in `-OutputPath`. Cleaning up stale output is left to the user, and Bylaw warns about `*.json` files in the output folder that no source file produced.

### Emitter design

Emitters implement a common contract: `Name`, `FileExtension`, and `Emit(PolicyNode) -> ordered document`. The canonical writer turns the document into bytes. The emitters are `Epac` and `PlainJson` (ADR-0027). Bicep may follow later. A Bicep emitter that writes text can implement the same contract but bypass the JSON writer.

### Consequences

* Good, because the output drops directly into an EPAC `Definitions/policyDefinitions` folder.
* Good, because mirroring the folder structure keeps the author's organisation of their policies.
* Bad, because the `$schema` URL points at EPAC's `main` branch. If EPAC moves it, we change it and regenerate the golden files.

### Confirmation

Golden files are validated against the EPAC JSON schema in CI, using a pinned copy of the schema in `tests/`.

## More Information

* [EPAC: policy definitions](https://azure.github.io/enterprise-azure-policy-as-code/policy-definitions/)
