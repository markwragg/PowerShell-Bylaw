# Missing-field verification

This is a developer-only tool behind [ADR-0004](../../docs/adr/0004-strict-missing-field-behaviour.md). It is not part of the Bylaw module and is never shipped. Bylaw itself never deploys anything ([ADR-0007](../../docs/adr/0007-compile-only.md)).

Microsoft Learn doesn't document how most policy operators evaluate against a missing field. This script measures it in a sandbox subscription.

## What it creates

The script creates the following. A route table costs nothing.

* A resource group (`rg-bylaw-verify` by default).
* One route table in that group, tagged `bylawPresent=abc` and `bylawEmpty=` (an empty value).
* One Audit policy definition per field and operator pair. That is 88 definitions with the default fields. They are named `bylaw-verify-001` and up, at subscription scope.
* One initiative, `bylaw-verify-set`, containing those definitions, and an assignment of it to the resource group.

Each rule is: `type == routeTables AND name == rt-bylaw-verify AND <condition under test>`. If the resource is NonCompliant, the condition evaluated to true. If it is Compliant, the condition evaluated to false.

| Field key | Field | Purpose |
|---|---|---|
| `tagPresent` | `tags['bylawPresent']` | Control. The value is `abc`, so every answer is known in advance. |
| `tagEmpty` | `tags['bylawEmpty']` | The tag is present with an empty string. |
| `tagMissing` | `tags['bylawMissing']` | The tag is missing. |
| `aliasMissing` | `Microsoft.Storage/storageAccounts/publicNetworkAccess` | A real alias that doesn't apply to route tables, so it is missing. |

Use `-ExtraField` to add more cases. Pass a route-table alias that you know is absent, or present but `null`, to cover the null-versus-missing question in ADR-0004.

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

# Wait 15-30 minutes for the assignment to take effect.
./Invoke-MissingFieldVerification.ps1 -Action Collect @verify          # re-run if cases are still 'missing'

./Invoke-MissingFieldVerification.ps1 -Action Remove @verify
```

`Collect` writes these files:

* `missing-field-results.md`: a table of operators against fields. Each cell is `true`, `false`, `missing` (no state yet), `rejected` (Azure refused the definition), or another compliance state such as `Error`.
* `missing-field-results.json`: the same data, readable by a machine.
* `missing-field-rejected.json`: written by `Deploy`. It lists any definitions Azure refused, with the error message.

Send the Markdown file back so the "Verified" column in ADR-0004 can be filled in.

## Reading the results

* Check the `tagPresent` column first. If any control answer is unexpected, the run is invalid. The expected values are:
  * `true` for equals, in, like, match, matchInsensitively, contains, less (`m`), lessOrEquals (`m`) and exists true.
  * `false` for their negations and for greater (`m`).
  * A type-mismatch error for the numeric comparisons.
* The `tagMissing` and `aliasMissing` columns answer ADR-0004's "`inv(P)` on missing" question.
* `tagEmpty` shows whether an empty value behaves like a missing one.
