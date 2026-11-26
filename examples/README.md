# Examples

Each `*.bylaw.ps1` file has the EPAC policy definition it compiles to beside it. To build them all:

```powershell
Build-Bylaw ./examples -OutputPath ./out
```

The JSON files are also the golden files for the tests: `tests/Golden/Golden.Tests.ps1` checks that the build reproduces them byte for byte, and that they validate against the EPAC schema.

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

`tests/Golden/` has more cases, written to cover the compiler rather than as policies to use: every operator in its strict, negated and `-IfPresent` forms, `-Strict` inside `Each`, `AnyOf` and `AllOf` in `When` and `Require`, and values from parameters and ARM expressions.

After an intended change to the compiler's output, regenerate the golden files and review the diff:

```powershell
./build/build.ps1 -Task UpdateGolden
```
