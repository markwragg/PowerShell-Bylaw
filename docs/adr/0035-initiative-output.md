---
status: accepted
date: 2026-11-27
decision-makers: Bylaw maintainers
---

# Initiatives are emitted as EPAC policy set definitions or plain JSON, to their own output folder

## Context and Problem Statement

EPAC reads policy definitions from `Definitions/policyDefinitions` and initiatives from `Definitions/policySetDefinitions`, and validates set files against its [policy set definition schema](https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-set-definition-schema.json). That schema references a custom member by `policyDefinitionName` and a built-in one by `policyDefinitionId`, and allows only `name` and `additionalMetadataId` on a group. Plain JSON, for `New-AzPolicySetDefinition`, the Azure CLI, Bicep or Terraform, needs a full `policyDefinitionId` for every member, including the scope a custom definition is deployed at, which Bylaw can't know. Today `Build-Bylaw -OutputPath` gets every policy, in folders mirroring the source (ADR-0011). What do the formats look like, and where are initiatives written?

## Decision Drivers

* Output from `-Format Epac` passes the EPAC schema, as for policies (ADR-0023).
* Plain JSON is deployable as written (ADR-0027).
* EPAC users can point Bylaw at the two folders EPAC reads, and the golden tests can keep building a folder into itself.

## Considered Options

* `-InitiativeOutputPath`, defaulting to `-OutputPath`
* Fixed `policyDefinitions` and `policySetDefinitions` subfolders of `-OutputPath`
* The same folder, with no option

## Decision Outcome

Chosen option: "`-InitiativeOutputPath`, defaulting to `-OutputPath`".

### Where

* `Build-Bylaw -InitiativeOutputPath`, or `initiativeOutputPath` in `bylaw.json`, is where initiatives are written. It defaults to `-OutputPath`. Initiatives mirror the source folders, one file per initiative named `<name>.json`, as policies do (ADR-0011). Because names are unique across policies and initiatives (ADR-0033), the two never clash in one folder.
* For EPAC: `Build-Bylaw ./policies -OutputPath ./Definitions/policyDefinitions -InitiativeOutputPath ./Definitions/policySetDefinitions`.
* The stale-output warning (BYL5030) covers both folders. A file in either that the build didn't produce is reported, whatever kind of definition it holds.

### EPAC format

```json
{
  "$schema": "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-set-definition-schema.json",
  "name": "tagging-baseline",
  "properties": {
    "displayName": "Tagging baseline",
    "policyType": "Custom",
    "metadata": { "version": "1.0.0", "category": "Tags" },
    "parameters": { },
    "policyDefinitions": [
      { "policyDefinitionReferenceId": "tags-require-mandatory-tags", "policyDefinitionName": "tags-require-mandatory-tags", "parameters": { } },
      { "policyDefinitionReferenceId": "InheritCostCenter", "policyDefinitionId": "/providers/...", "definitionVersion": "1.*.*", "parameters": { } }
    ]
  }
}
```

* Key order follows the schema and Learn: `policyDefinitionReferenceId`, then `policyDefinitionName` or `policyDefinitionId`, `definitionVersion`, `parameters`, `groupNames`. Empty `parameters` and `groupNames` are left out.
* A member from the build is emitted with `policyDefinitionName`, and EPAC resolves it. A member by `-Id` is emitted with `policyDefinitionId`.
* `Category` and `Version` are required, as for policies (BYL4001, BYL4002). Parameters get generated display names, as for policies (ADR-0023). No effect parameter is generated: an initiative has no effect.
* A `DefinitionGroup` with `-DisplayName`, `-Category` or `-Description` is an EPAC error, because the schema doesn't allow them on a group. Only `name` and `additionalMetadataId` are emitted.

### Plain JSON format

* `{ "name", "properties" }`, as for policies (ADR-0027), with `metadata`, `parameters` and groups emitted as written.
* Every member needs a full `policyDefinitionId`. For a member from the build, it is `<definitionScope>/providers/Microsoft.Authorization/policyDefinitions/<name>`, where `definitionScope` is the scope the build's policies are deployed at, such as `/providers/Microsoft.Management/managementGroups/contoso`. It is set with `Build-Bylaw -DefinitionScope` or `definitionScope` in `bylaw.json`. A plain JSON build with an initiative that has a member from the build, and no definition scope, is an error.
* Groups keep `displayName`, `category` and `description`.

### Consequences

* Good, because EPAC users write to the folders EPAC reads, and nothing changes for builds without initiatives.
* Good, because plain JSON initiatives are deployable, with the scope stated once.
* Bad, because EPAC users have to pass a second path. The README says so where it describes EPAC output.

### Confirmation

Unit tests cover both folders, the default, stale-output warnings in each, both formats, the definition scope and its error, and groups in each format. Golden tests validate EPAC initiatives against the pinned set schema, which is added to `tests/Schemas`.

## Pros and Cons of the Options

### `-InitiativeOutputPath`, defaulting to `-OutputPath`

* Good, because EPAC's layout is one option away, and every existing layout and golden test still works.
* Bad, because there is one more parameter.

### Fixed subfolders

* Good, because EPAC users need no extra option.
* Bad, because it changes where every policy is written, for every format, and plain JSON users don't want EPAC's folder names.

### The same folder

* Good, because there's nothing to configure.
* Bad, because EPAC can't read initiatives from its policy definitions folder.

## More Information

* [EPAC policy set definitions](https://azure.github.io/enterprise-azure-policy-as-code/policy-set-definitions/), [initiative definition structure](https://learn.microsoft.com/azure/governance/policy/concepts/initiative-definition-structure)
* Related: [ADR-0011](0011-epac-default-output.md), [ADR-0012](0012-language-versioning.md), [ADR-0023](0023-epac-schema-conformance.md), [ADR-0027](0027-plain-json-output.md), [ADR-0033](0033-initiatives.md)
