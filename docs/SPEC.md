# Build Bylaw: a Pester-style PowerShell DSL that compiles to Azure Policy

## Context

I'm building **Bylaw**, an open-source PowerShell module that gives Azure Policy authors a Pester-style DSL. Authors describe the *compliant* state of a resource, and Bylaw compiles that into standard Azure Policy definition JSON (EPAC-compatible by default). Bylaw does not deploy anything. EPAC, Bicep or Terraform handle deployment.

The value is not just shorter syntax. It is:

- Desired-state authoring (`Require` / `Must`), with the compiler inverting to violation logic
- Short alias names, resolved against the resource type and validated at compile time
- Simple array conditions (`Each`) instead of hand-written `count` / `where`
- Generated boilerplate for effect parameters and metadata
- Pester-friendly testing of policies before deployment

Treat this prompt as the spec. Where it is silent or ambiguous, ask me rather than guess.

## How I want you to work

1. **Plan first.** Read this whole prompt, then reply with an implementation plan for Milestone 1 (below) and any questions. Do not write code until I approve the plan.
2. **ADRs before code.** Create `docs/adr/` using the MADR template and write the ADRs listed under "Locked decisions" with status `Accepted`, and the ones under "Open decisions" with status `Proposed`. Number them sequentially from `0001-record-architecture-decisions.md`.
3. **Work in small, reviewable steps.** One logical change per commit, with clear messages. Stop at the end of each milestone step for me to review.
4. **Tests alongside code.** Every keyword and every compiler rule gets Pester tests. Golden-file tests for compiled output.
5. **Verify Azure Policy semantics against Microsoft Learn docs** (policy definition structure, policy rule conditions, `count` expressions, effects). If anything in this prompt contradicts the docs, flag it rather than following the prompt.

## Technical constraints

- PowerShell 7.2+ only. Pester 6.x for tests. PSScriptAnalyzer clean, except for documented suppressions (DSL keywords will not follow Verb-Noun).
- **No backtick line continuation anywhere** (code, examples, docs). Use splatting, hashtables or natural line breaks after pipes and operators.
- No runtime dependency on Az modules for compiling. Az is only needed for the alias cache refresh command.
- MIT licence.
- Cross-platform (Windows, Linux, macOS). CI on GitHub Actions running Pester and PSScriptAnalyzer on all three.

## Suggested repo layout

```
Bylaw/
  src/
    Bylaw.psd1
    Bylaw.psm1
    Public/          # Build-Bylaw, ConvertFrom-PolicyJson, Update-BylawAliasCache, Policy
    Private/
      Keywords/      # Properties, Parameter, Resource, When, Require, Each, Field, Tag, Must, Element, Effect, Modify, Param, Arm
      IR/            # IR node classes
      Compiler/      # inversion, flattening, alias resolution, validation
      Emitters/      # Epac, PlainJson (Bicep later)
    Data/
      aliases.json   # bundled alias snapshot
  tests/
    Unit/
    Golden/          # *.bylaw.ps1 inputs with expected *.json outputs
  examples/
  docs/
    adr/
  build/             # build and publish scripts
```

Adjust if you have a better structure, but explain why in the plan.

## The DSL

### Example (use this as the first golden test)

```powershell
Policy 'storage-deny-public-network-access' {

    Properties @{
        DisplayName = 'Storage accounts should disable public network access'
        Description = 'Denies storage accounts that allow public network access or allow-all IP rules.'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'All'
    }

    Parameter Effect -AllowedValues Audit, Deny, Disabled -Default Deny

    Resource 'Microsoft.Storage/storageAccounts' {

        When {
            Field kind | Must -BeIn 'StorageV2', 'BlockBlobStorage'
        }

        Require 'Public network access is disabled' {
            Field publicNetworkAccess | Must -Be 'Disabled'
        }

        Require 'No allow-all IP rules' {
            Each networkAcls.ipRules[*] {
                Field value | Must -Not -Be '0.0.0.0/0'
            }
        }
    }

    Effect (Param Effect)
}
```

Expected `policyRule`:

```json
{
  "if": {
    "allOf": [
      { "field": "type", "equals": "Microsoft.Storage/storageAccounts" },
      { "field": "kind", "in": [ "StorageV2", "BlockBlobStorage" ] },
      {
        "anyOf": [
          { "field": "Microsoft.Storage/storageAccounts/publicNetworkAccess", "notEquals": "Disabled" },
          {
            "count": {
              "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]",
              "where": { "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value", "equals": "0.0.0.0/0" }
            },
            "greater": 0
          }
        ]
      }
    ]
  },
  "then": { "effect": "[parameters('effect')]" }
}
```

Note: the parameter is declared as `Effect` in the DSL and emitted as `effect` in JSON. Propose a casing convention for parameter names in the ADRs.

### Keywords

| Keyword | Purpose |
|---|---|
| `Policy 'name' { }` | One policy definition. The only top-level DSL command. |
| `Properties @{ }` | Metadata hashtable. Validated keys: `DisplayName`, `Description`, `Category`, `Version`, `Mode`, `Preview`, `Deprecated`, `Metadata`. Unknown keys fail the build. `Category`, `Version`, `Preview`, `Deprecated` go into `metadata`. |
| `Parameter Name ...` | Policy parameter. One-line form with common options, plus a hashtable form for extras. |
| `Resource 'type' { }` | Scopes to a resource type and sets the alias resolution context. `Resource *` means no type condition. |
| `When { }` | Applicability conditions. Not inverted. |
| `Require 'description' { }` | A named compliance requirement. Inverted. |
| `Each path[*] { }` | Array condition, compiles to `count` / `where`. |
| `Field name` | Field reference, resolved to a full alias. |
| `Element` | The current element of an array of plain values, inside `Each`. |
| `Tag name` | Tag field reference (`tags['name']`), parameter-aware. |
| `ResourceGroupTag name` | The resource group's tag value (`[resourceGroup().tags['name']]`), parameter-aware. |
| `AnyOf { }` / `AllOf { }` | Alternatives in a requirement: `AnyOf` holds if any statement inside holds. `AllOf` is only valid inside `AnyOf` (ADR-0026). |
| `Must` | Assertion, takes a field reference from the pipeline. |
| `Effect value` | The `then` block for simple effects. |
| `Modify -Role ... { }` | Modify effect, in place of `Effect`. Operations take their field from the pipeline: `Tag x \| AddOrReplace 'v'`, `Tag x \| Add 'v'`, `Tag x \| Remove` (ADR-0024). |
| `DenyAction`, `Manual`, `Append { }` | Effects with a `details` block, in place of `Effect` (Milestone 3, ADR-0028, ADR-0029). |
| `AuditIfNotExists -Type ... { }`, `DeployIfNotExists -Type ... { }` | Effects on a related resource, in place of `Effect`. The block describes the related resource's compliant state (Milestone 3, ADR-0030, ADR-0031). |
| `Count path[*]`, `Count -Value ...` | A field or value count, piped to `Must` (Milestone 3, ADR-0032). |
| `Param Name` | Reference a parameter (emits `[parameters('name')]`). |
| `Arm '[...]'` | Raw ARM template expression escape hatch. |

`Element` and `Arm` were originally `Item` and `Expr`. They were renamed because, outside a `Policy`, those names resolved to `Get-Item` and the native `expr` program (ADR-0005).

### Must operators

The operator names follow ADR-0015.

| DSL | Policy operator | Inverted form |
|---|---|---|
| `-Be` | `equals` | `notEquals` |
| `-BeIn` | `in` | `notIn` |
| `-BeLike` | `like` | `notLike` |
| `-Match` | `matchInsensitively` | `notMatchInsensitively` |
| `-MatchCase` | `match` | `notMatch` |
| `-ContainText` | `contains` | `notContains` |
| `-ContainKey` | `containsKey` | `notContainsKey` |
| `-Exist` | `exists: true` | `exists: false` |
| `-BeGreaterThan` | `greater` | `lessOrEquals` |
| `-BeGreaterOrEqual` | `greaterOrEquals` | `less` |
| `-BeLessThan` | `less` | `greaterOrEquals` |
| `-BeLessOrEqual` | `lessOrEquals` | `greater` |
| `-Not` | flips any of the above | |
| `-IfPresent` | a missing field is compliant (not inside `Each`) | |
| `-Strict` | a missing element field is a violation (inside `Each` only) | |

Azure `match` patterns are not regular expressions: `#` matches a digit, `?` a letter and `.` any character.

Use `Must` rather than `Should` to avoid clashing with Pester, which users will run in the same session.

## Locked decisions (write as Accepted ADRs)

1. **Desired-state semantics.** `Require` / `Must` describe the compliant state. Compiled rule: `if` = resource type AND `When` conditions AND NOT (all `Require` blocks). Negation is pushed inward using De Morgan's law and operator inversion, never emitted as a wrapping `not` unless unavoidable.
2. **Multiple `Require` blocks combine with AND.** Multiple `Must` statements inside one `Require` also combine with AND.
3. **Strict missing-field behaviour by default.** A missing field fails the requirement. Provide `-IfPresent` on `Must` for lenient checks. Verify how each inverted operator behaves on a missing field against the docs and document the results in the ADR.
4. **Keyword scoping.** Only `Policy` and the build/utility cmdlets are exported. Inner keywords are made available only while a `Policy` scriptblock runs, and calling them outside one throws a clear error.
5. **Intermediate representation.** DSL front-end produces an IR (PowerShell classes). Compiler passes operate on the IR. Emitters serialise the IR. No keyword writes JSON directly. The IR must be lossless enough to support decompiling JSON back to DSL.
6. **Compile only.** No deployment to Azure.
7. **Bundled alias snapshot.** Compilation works offline using `Data/aliases.json`. `Update-BylawAliasCache` refreshes it via Az. Unknown aliases fail the build unless overridden per field or with `-AllowUnknownAlias`.
8. **Deterministic output.** Stable key ordering, stable formatting, UTF-8 without BOM, LF line endings. Recompiling unchanged input produces byte-identical files.
9. **Name stability.** The definition `name` comes only from `Policy 'name'`. Enforce a naming rule (propose one in the ADR). Milestone 3 relaxed the rule in ADR-0010: any name Azure accepts that is also a safe file name.
10. **Default output is EPAC schema**, one file per policy, with plain definition JSON as a second emitter. Design emitters so Bicep can be added later.
11. **Language versioning.** Support a language version via a project settings file (`bylaw.json`), defaulting to `1.0`.
12. **Discovery by convention.** `Build-Bylaw -Path` finds `*.bylaw.ps1` recursively. Multiple policies per file are allowed. Names must be unique across the build.
13. **Isolation.** Each file is compiled in a fresh runspace so state cannot leak between files.

## Open decisions (write as Proposed ADRs, with options and your recommendation)

- Parameter name casing in emitted JSON
- Whether to stamp provenance metadata (e.g. `metadata.generatedBy`) and how to keep it from adding diff noise
- Representation of ARM expressions: which typed helpers ship in v1 beyond `Param`, `Tag`, `ResourceGroupTag`, `Arm`
- Compile-time validation of parameter usage (e.g. array parameter used with `-Be`)
- Built-in role name to ID resolution for `Modify -Role` (bundled map vs lookup)

## Milestones

### Milestone 1: compiler core

- Module scaffold, manifest, build script, CI
- IR classes
- Keywords: `Policy`, `Properties`, `Parameter`, `Resource`, `When`, `Require`, `Field`, `Element`, `Must` (all operators), `Each`, `Effect`, `Param`, `Arm`
- Compiler passes: alias resolution, inversion, `allOf`/`anyOf` flattening, validation
- EPAC emitter
- `Build-Bylaw` with `-Path`, `-OutputPath`, `-Format`, `-PassThru`
- Alias cache: bundled snapshot loader and `Update-BylawAliasCache`. For the initial bundled file, include just enough aliases for the tests and examples, and I'll generate the full snapshot myself.
- Golden tests: the storage example above plus at least five more covering each operator, `When`, multiple `Require` blocks, `Each`, `-Not`, `-IfPresent`, and `Resource *`
- Helpful errors: file name, line number and the keyword involved for every compile error

### Milestone 2: Modify and helpers

- `Modify` with `AddOrReplace`, `Add`, `Remove`, `-Role`
- `Tag`, `ResourceGroupTag`
- Plain JSON emitter
- Tag inheritance golden test
- Value conditions: `ResourceGroupTag`, `Param` and `Arm` piped into `Must` (ADR-0025)
- From Milestone 1's gaps: `AnyOf` and `AllOf` groups (ADR-0026), and repeated `exists` guards emitted once (ADR-0004)

### Milestone 3: language coverage

Every effect Azure Policy supports, and the conditions Bylaw can't yet express, so the decompiler (Milestone 5) can target the whole language. In the Azure Landing Zones Library, 82 of 149 custom policy definitions use effects that language version 1.0 lacked, and 11 of the remaining 67 use conditions it couldn't express (a field count without `where`, a value count, or a `[*]` field outside a count).

- Policy names: accept existing definition names, such as mixed case (ADR-0010)
- `DenyAction` and `Manual` (ADR-0028)
- `Append` (ADR-0029)
- `AuditIfNotExists`, with the related resource and its existence condition (ADR-0030)
- `DeployIfNotExists`, with roles and the deployment template (ADR-0030, ADR-0031)
- `Count` for field and value counts, with `Current` (ADR-0032)
- Golden tests, examples and README for all of the above

### Milestone 4: initiatives

- An initiative keyword: member policies from the same build or built-in policies by ID, parameters passed to members, policy groups
- Cross-file checks after every file has compiled: references exist, passed parameters match
- EPAC policy set definition output, and plain JSON

### Milestone 5: decompiler and ALZ round-trip

- `ConvertFrom-PolicyJson`: JSON definition (and initiative) to `.bylaw.ps1`
- An escape hatch for raw conditions the language can't express
- Round-trip test harness: decompile, recompile, compare semantically (not textually)
- Script to pull custom policy definitions from the Azure Landing Zones Library and produce a coverage report (supported / escape hatch / failed). Do not commit ALZ content to the repo without checking with me about licensing and attribution first.

### Later (do not build yet, but don't design them out)

- Resource provider modes, such as `Microsoft.Kubernetes.Data`
- Bicep emitter
- `Test-PolicyRule` local evaluator against sample resource JSON
- VS Code syntax support and argument completers for `Field` driven by the enclosing `Resource` type

## Definition of done for Milestone 1

- `Build-Bylaw ./examples` produces EPAC-valid JSON that matches the golden files byte for byte
- All Pester tests pass on Windows, Linux and macOS in CI
- PSScriptAnalyzer clean apart from documented suppressions
- ADRs written
- README with install, a quick start, the storage example before and after, and the operator table

Start with the plan and your questions.