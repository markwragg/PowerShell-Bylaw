# Azure Policy verification

This is a developer-only tool behind [ADR-0004](../../docs/adr/0004-strict-missing-field-behaviour.md), [ADR-0024](../../docs/adr/0024-modify-effect.md), [ADR-0025](../../docs/adr/0025-value-conditions.md) and [ADR-0030](../../docs/adr/0030-if-not-exists-effects.md). It is not part of the Bylaw module and is never shipped. Bylaw itself never deploys anything ([ADR-0007](../../docs/adr/0007-compile-only.md)).

Microsoft Learn doesn't document some policy behaviour that Bylaw relies on. This script measures it in a sandbox subscription:

* **Fields:** how each operator evaluates against present, empty and missing fields (ADR-0004).
* **Resource group tags:** how a missing or empty resource group tag compares in a value condition (ADR-0025).
* **Existence conditions:** how an `AuditIfNotExists` existence condition evaluates on a related resource that lacks the field, with the operator alone and in the guarded forms Bylaw emits (ADR-0030).
* **Modify with Audit:** whether `Audit` is accepted as the effect of a definition with a `modify` details block, and whether it then reports compliance (ADR-0024).

## What it creates

The script creates the following. A route table costs nothing.

* A resource group (`rg-bylaw-verify` by default), tagged `bylawPresent=abc` and `bylawEmpty=` (an empty value).
* One route table in that group, with the same tags, and one route (`bylaw-route`, next hop `VnetLocal`), which has no `nextHopIpAddress`.
* One Audit policy definition per test case, named `bylaw-verify-001` and up, at subscription scope. With the default fields there are 88 field cases, 15 resource group tag cases and 8 existence-condition cases. The existence cases are `auditIfNotExists` policies on the route table, with the route as the related resource.
* One initiative, `bylaw-verify-set`, containing those definitions, and an assignment of it to the resource group.
* One Modify definition, `bylaw-verify-modify-audit`, whose effect parameter allows `Modify`, `Audit` and `Disabled`. It is assigned to the resource group separately, with the effect set to `Audit`. It has no managed identity, so it can't change anything.

Each rule is: `type == routeTables AND name == rt-bylaw-verify AND <condition under test>`. If the resource is NonCompliant, the condition evaluated to true. If it is Compliant, the condition evaluated to false.

| Field key | Field | Purpose |
|---|---|---|
| `tagPresent` | `tags['bylawPresent']` | Control. The value is `abc`, so every answer is known in advance. |
| `tagEmpty` | `tags['bylawEmpty']` | The tag is present with an empty string. |
| `tagMissing` | `tags['bylawMissing']` | The tag is missing. |
| `aliasMissing` | `Microsoft.Network/routeTables/subnets` | A property of the route table's own type that is missing, because the route table has no subnets. |

Use `-ExtraField` to add more cases, for example a route-table alias that is present but `null`.

Don't use an alias of a different resource type as a missing field. Azure never evaluates a condition on another type's alias, so those cases never get a compliance state (ADR-0004).

The resource group tag cases test `[resourceGroup().tags['bylawPresent']]`, `['bylawEmpty']` and `['bylawMissing']` with `equals "abc"`, `equals ""`, `notEquals ""` and `exists`.

## Requirements

* PowerShell 7.2 or later.
* Az.Accounts, Az.Resources 7 or later, and Az.PolicyInsights.
* `Connect-AzAccount` already run, with rights to create policy definitions and assignments in the sandbox subscription (for example Owner or Resource Policy Contributor, plus Contributor on the resource group).

## Usage

```powershell
$verify = @{
    SubscriptionId = '<sandbox subscription id>'
    OutputPath     = './out'
}

./Invoke-MissingFieldVerification.ps1 -Action Deploy @verify -WhatIf   # preview
./Invoke-MissingFieldVerification.ps1 -Action Deploy @verify

# Wait 15-30 minutes for the assignments to take effect.
./Invoke-MissingFieldVerification.ps1 -Action Collect @verify          # re-run if cases are still 'missing'

./Invoke-MissingFieldVerification.ps1 -Action Remove @verify
```

Pass the same `-ExtraField` values to every action. `Remove` deletes the definitions by number, so it needs the same list as `Deploy`.

`Collect` writes these files:

* `missing-field-results.md`: one table for fields, one for resource group tags, and the Modify result. Each cell is `true`, `false`, `missing` (no state yet), `rejected` (Azure refused the definition), or another compliance state such as `Error`.
* `missing-field-results.json`: the same data, readable by a machine.
* `missing-field-rejected.json`: written by `Deploy`. It lists any definitions or assignments Azure refused, with the error message.

Send the Markdown file back so the ADRs can be updated.

## Reading the results

* Check the `tagPresent` and `rgTagPresent` columns first. If any control answer is unexpected, the run is invalid. The expected values for `tagPresent` are:
  * `true` for equals, in, like, match, matchInsensitively, contains, less (`m`), lessOrEquals (`m`) and exists true.
  * `false` for their negations and for greater (`m`).
  * A type-mismatch error for the numeric comparisons.
* For `rgTagPresent`, `equals "abc"` and `notEquals ""` should be `true`, and `equals ""` should be `false`.
* The `tagMissing` and `aliasMissing` columns answer ADR-0004's "`inv(P)` on missing" question.
* `tagEmpty` shows whether an empty value behaves like a missing one.
* `rgTagMissing` with `equals ""` answers ADR-0025's question. `true` means a missing resource group tag compares as an empty string, as the built-in tag inheritance policies assume.
* For the existence cases, a cell says whether the existence condition held for the route (the route table was Compliant). `presentEquals` should be `true` and `presentNotEquals` `false`. The report shows what ADR-0004 needs beside each guarded case.
* For the Modify check:
  * `true` means `Audit` works on a Modify definition.
  * `rejected` means Azure refused the definition or the assignment. The message is in the report.
  * `false` would be unexpected, because the rule matches the route table.
