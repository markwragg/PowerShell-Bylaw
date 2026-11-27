# Initiative verification

A developer-only tool for [ADR-0034](../../docs/adr/0034-initiative-member-checks.md) and [ADR-0035](../../docs/adr/0035-initiative-output.md). It is not part of the Bylaw module and is never shipped. Bylaw itself never deploys anything ([ADR-0007](../../docs/adr/0007-compile-only.md)).

The build checks initiatives offline, but two things can only be checked in Azure:

* **Accepted:** whether Azure accepts the plain JSON policies and initiatives Bylaw builds, with members from the build referenced by a full ID at the definition scope, and whether each initiative can be assigned.
* **Version:** what Azure does with `definitionVersion` on a member from the build. Bylaw emits `Version` only as `metadata.version` (ADR-0016), and warns about such a pin (BYL3129). The run records whether the pinned initiative is accepted and assigned, and the version Azure reports for each policy definition.

It doesn't check EPAC. Whether EPAC resolves `policyDefinitionName` needs an EPAC environment.

## What it creates

Everything is at subscription scope or in one resource group, and every name starts with `bylaw-verify`. Definitions and assignments cost nothing.

* Two policy definitions from [sources/verify.bylaw.ps1](sources/verify.bylaw.ps1): one with an effect parameter and a required parameter, and one with a literal effect, which has no effect parameter in plain JSON.
* Two initiatives:
  * `bylaw-verify-set`: both policies, one of them twice with different reference IDs, a built-in policy pinned to `1.*.*`, groups with every property, and parameters passed through.
  * `bylaw-verify-set-pinned`: one member from the build with `-Version '1.*.*'`. It is separate, so if Azure refuses it, the other initiative is still deployed.
* A resource group (`rg-bylaw-verify-initiatives` by default), and an assignment of each initiative to it.

## Requirements

* PowerShell 7.2 or later.
* Az.Accounts and Az.Resources 7 or later.
* `Connect-AzAccount` already run, with rights to create policy definitions and assignments in the sandbox subscription (for example Owner, or Resource Policy Contributor plus Contributor on the resource group).

## Usage

```powershell
$verify = @{ SubscriptionId = '<sandbox subscription id>' }

./Invoke-InitiativeVerification.ps1 -Action Deploy @verify -WhatIf   # preview
./Invoke-InitiativeVerification.ps1 -Action Deploy @verify
./Invoke-InitiativeVerification.ps1 -Action Remove @verify
```

There is no waiting and no Collect step: the results are whether Azure accepted each request, and what it stored. A refused step is recorded and the run carries on.

`Deploy` writes these files to `out/` (or `-OutputPath`), which is not committed:

* `json/`: the plain JSON that was built and deployed.
* `initiative-results.md`: each step with its result, the version Azure reports for each policy, the members as Azure stored them, and the build warnings.
* `initiative-results.json`: the same data, readable by a machine.

## Reading the results

* Every step should be `accepted`. A `rejected` step has Azure's message beside it.
* The members table should show each member from the build as `/subscriptions/<id>/providers/Microsoft.Authorization/policyDefinitions/bylaw-verify-...`.
* For BYL3129: `bylaw-verify-set-pinned` being accepted and assigned, and the version Azure reports for `bylaw-verify-tags`, show what a `definitionVersion` pin on a Bylaw policy means in practice.
