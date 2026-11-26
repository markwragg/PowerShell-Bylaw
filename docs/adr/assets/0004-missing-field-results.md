# Azure Policy missing-field verification

Collected 2026-11-25 16:14 UTC. Cell = whether the condition evaluated true.
`true` = NonCompliant, `false` = Compliant, `missing` = no state yet (re-run Collect), `rejected` = definition refused by Azure.

Fields:
- **tagPresent**: `tags['bylawPresent']`
- **tagEmpty**: `tags['bylawEmpty']`
- **tagMissing**: `tags['bylawMissing']`
- **aliasMissing**: `Microsoft.Storage/storageAccounts/publicNetworkAccess`

| Operator | Value | tagPresent | tagEmpty | tagMissing | aliasMissing |
|---|---|---|---|---|---|
| equals | `"abc"` | true | false | false | missing |
| notEquals | `"abc"` | false | true | true | missing |
| in | `["abc"]` | true | false | false | missing |
| notIn | `["abc"]` | false | true | true | missing |
| like | `"a*"` | true | false | false | missing |
| notLike | `"a*"` | false | true | true | missing |
| match | `"???"` | true | false | false | missing |
| notMatch | `"???"` | false | true | true | missing |
| matchInsensitively | `"???"` | true | false | false | missing |
| notMatchInsensitively | `"???"` | false | true | true | missing |
| contains | `"b"` | true | false | false | missing |
| notContains | `"b"` | false | true | true | missing |
| containsKey | `"k"` | false | false | false | missing |
| notContainsKey | `"k"` | true | true | true | missing |
| greater | `"m"` | false | false | false | missing |
| greaterOrEquals | `"m"` | false | false | true | missing |
| less | `"m"` | true | true | false | missing |
| lessOrEquals | `"m"` | true | true | true | missing |
| greater | `5` | Error | Error | false | missing |
| less | `5` | Error | Error | false | missing |
| exists | `true` | true | true | false | missing |
| exists | `false` | false | false | true | missing |
