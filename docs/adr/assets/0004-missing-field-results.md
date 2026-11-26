# Azure Policy missing-field verification

Results from [build/verify-missing-field](../../../build/verify-missing-field/README.md). Each cell says whether the condition evaluated true on the route table:

* `true`: NonCompliant.
* `false`: Compliant.
* `missing`: no compliance state.
* `Error`: Azure reported the compliance state `Error`.

## Third run (2026-11-26)

Collected 2026-11-26 14:32 UTC. Every case has a result.

**Fields:** the same as the second run in every row, for the three tags and for `aliasMissing` (`Microsoft.Network/routeTables/subnets`, a missing property of the route table itself). The cross-type alias was dropped from this run.

**Resource group tags in value conditions** (ADR-0025). The resource group has `bylawPresent = abc` and `bylawEmpty = ''`, and no `bylawMissing`:

| Operator | Value | `[resourceGroup().tags['bylawPresent']]` | `[resourceGroup().tags['bylawEmpty']]` | `[resourceGroup().tags['bylawMissing']]` |
|---|---|---|---|---|
| equals | `"abc"` | true | false | false |
| equals | `""` | false | true | true |
| notEquals | `""` | true | false | false |
| exists | `true` | true | true | true |
| exists | `false` | false | false | false |

A missing resource group tag compares exactly like an empty one, and `exists` is true for both. To require a value, test `notEquals ''` (`Must -Not -Be ''`).

**Modify definition assigned with effect `Audit`** (ADR-0024): `true`. Azure refused the assignment without a managed identity (`ResourceIdentityRequired`). With a system-assigned identity it was accepted, and the route table reported NonCompliant.

## Second run (2026-11-26)

Collected 2026-11-26 10:22 UTC, more than 12 hours after deployment.

Fields:
- **tagPresent**: `tags['bylawPresent']`, the value `abc`. This is the control column.
- **tagEmpty**: `tags['bylawEmpty']`, an empty string.
- **tagMissing**: `tags['bylawMissing']`, not set.
- **aliasMissing**: `Microsoft.Storage/storageAccounts/publicNetworkAccess`. This is an alias of a different resource type.
- **extra1**: `Microsoft.Network/routeTables/subnets`. The route table has no subnets, and `exists: false` confirms the property is missing.
- **extra2**: `Microsoft.Network/routeTables/disableBgpRoutePropagation`. This is present with the boolean value `false`.

| Operator | Value | tagPresent | tagEmpty | tagMissing | aliasMissing | extra1 | extra2 |
|---|---|---|---|---|---|---|---|
| equals | `"abc"` | true | false | false | missing | false | false |
| notEquals | `"abc"` | false | true | true | missing | true | true |
| in | `["abc"]` | true | false | false | missing | false | false |
| notIn | `["abc"]` | false | true | true | missing | true | true |
| like | `"a*"` | true | false | false | missing | false | false |
| notLike | `"a*"` | false | true | true | missing | true | true |
| match | `"???"` | true | false | false | missing | false | false |
| notMatch | `"???"` | false | true | true | missing | true | true |
| matchInsensitively | `"???"` | true | false | false | missing | false | false |
| notMatchInsensitively | `"???"` | false | true | true | missing | true | true |
| contains | `"b"` | true | false | false | missing | false | false |
| notContains | `"b"` | false | true | true | missing | true | true |
| containsKey | `"k"` | false | false | false | missing | false | false |
| notContainsKey | `"k"` | true | true | true | missing | true | true |
| greater | `"m"` | false | false | false | missing | false | Error |
| greaterOrEquals | `"m"` | false | false | true | missing | true | Error |
| less | `"m"` | true | true | false | missing | false | Error |
| lessOrEquals | `"m"` | true | true | true | missing | true | Error |
| greater | `5` | Error | Error | false | missing | false | Error |
| less | `5` | Error | Error | false | missing | false | Error |
| exists | `true` | true | true | false | missing | false | true |
| exists | `false` | false | false | true | missing | true | false |

What it shows:

* **The control column matches expectations**, so the run is valid. The columns it shares with the first run give the same results.
* **A missing alias property behaves like a missing tag.** The `extra1` column is identical to `tagMissing` in every row.
* **An alias of another resource type is never evaluated.** The `aliasMissing` column had no compliance state in either run, even after more than 12 hours. This confirms that Azure treats the resource as not applicable to a condition on another type's alias. It isn't a missing value, so it has no bearing on the guard rules.
* **A type mismatch is an error.** `extra2` is a boolean. Comparing it with a string (`greater "m"`) gives `Error`, as comparing a number with a string did on the present tag.

`extra1` is an array property referenced without `[*]`. No missing scalar alias of the route table type was measured, but no difference is expected, because tags are scalars and behave the same way.

## First run (2026-11-25)

The first run had only the `tagPresent`, `tagEmpty`, `tagMissing` and `aliasMissing` columns. Its results were identical to the same columns above.
