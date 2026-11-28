# Examples

Each `*.bylaw.ps1` file has the EPAC policy and initiative definitions it compiles to beside it. To build them all:

```powershell
Build-Bylaw ./examples -OutputPath ./out
```

The JSON files are also the golden files for the tests: `tests/Golden/Golden.Tests.ps1` checks that the build reproduces them byte for byte, and that they validate against the EPAC schema. To get plain definitions for other tools instead, add `-Format PlainJson`.

| Example | Shows |
|---|---|
| [storage/public-network-access](storage/public-network-access.bylaw.ps1) | The example from the specification: `When`, two `Require` blocks, `Each` over objects, an effect parameter |
| [storage/secure-transfer](storage/secure-transfer.bylaw.ps1) | Several `Must` statements in one `Require`, an array parameter with allowed values, `-Not` with `-IfPresent` |
| [storage/baseline](storage/baseline.bylaw.ps1) | A PowerShell loop that generates one `Require` block per setting |
| [key-vault/recovery](key-vault/recovery.bylaw.ps1) | A comparison with a parameter value, `-IfPresent`, and a literal effect (Bylaw generates the effect parameter) |
| [key-vault/no-purge-permission](key-vault/no-purge-permission.bylaw.ps1) | Nested `Each`, and `Element` for arrays of plain values |
| [network/deny-inbound-from-internet](network/deny-inbound-from-internet.bylaw.ps1) | `AnyOf` and `AllOf` inside `Each`: a rule is acceptable if any alternative holds |
| [compute/linux-vm-standards](compute/linux-vm-standards.bylaw.ps1) | `When` to narrow the resources, `-BeIn` with a parameter, `-BeLike` |
| [general/allowed-locations](general/allowed-locations.bylaw.ps1) | `Resource *` for every resource type, with `location` |
| [general/require-tag](general/require-tag.bylaw.ps1) | `Resource *` with `-ContainKey` and a parameter value |
| [tags/inherit-tag](tags/inherit-tag.bylaw.ps1) | `Modify` with `AddOrReplace`: keep a tag in step with the resource group, as the built-in policy does |
| [tags/inherit-tag-if-missing](tags/inherit-tag-if-missing.bylaw.ps1) | `Modify` with `Add`: add the resource group's tag only where it is missing |
| [storage/minimum-tls-modify](storage/minimum-tls-modify.bylaw.ps1) | `Modify` on an alias, with `-ConflictEffect Audit`, `-Condition` and an effect parameter |
| [storage/append-secure-transfer](storage/append-secure-transfer.bylaw.ps1) | `Append`, with a `Require` that checks the added field |
| [storage/protect-from-deletion](storage/protect-from-deletion.bylaw.ps1) | `DenyAction Delete` with `-CascadeBehavior`, on resources selected by a tag in `When` |
| [general/attest-access-review](general/attest-access-review.bylaw.ps1) | `Manual` with `-DefaultState`, for a control that people attest |
| [compute/audit-antimalware](compute/audit-antimalware.bylaw.ps1) | `AuditIfNotExists` on a VM extension, and the full alias for a field named like a reserved one |
| [key-vault/deploy-diagnostics](key-vault/deploy-diagnostics.bylaw.ps1) | `DeployIfNotExists` with a template file in [key-vault/templates](key-vault/templates/), roles by ID, and an effect parameter that allows `AuditIfNotExists` |
| [general/name-matches-a-pattern](general/name-matches-a-pattern.bylaw.ps1) | A value count over a parameter, with `Current` as the value each name is compared with |
| [network/limit-inbound-allow-rules](network/limit-inbound-allow-rules.bylaw.ps1) | A field count with `-Where`, compared with an `Integer` parameter |
| [initiatives/storage-baseline](initiatives/storage-baseline.bylaw.ps1) | An initiative of storage policies from other files, with one `Effect` passed to all of them, and a member that needs no parameters |
| [initiatives/tagging-baseline](initiatives/tagging-baseline.bylaw.ps1) | An initiative that passes its own parameter to a policy, includes one policy twice with different reference IDs, and includes a built-in policy by its GUID with `-Version`, splatting its arguments |

Template files live in `templates` folders. They are inputs, not golden files.

`tests/Golden/` has more cases, written to cover the compiler rather than as policies to use: every operator in its strict, negated and `-IfPresent` forms, `-Strict` inside `Each`, `AnyOf` and `AllOf` in `When` and `Require`, values from parameters and ARM expressions, tags and value conditions, every `Modify` operation and option, the other effects with their options (`effects/`), the count patterns of the Azure Landing Zones Library (`count/`), raw conditions with `Condition` (`conditions/`), and initiatives (`initiatives/`). `tests/GoldenPlainJson/` has the same kind of cases built with `-Format PlainJson`.

After an intended change to the compiler's output, regenerate the golden files and review the diff:

```powershell
./build/build.ps1 -Task UpdateGolden
```
