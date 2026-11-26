# Bylaw

[![CI](https://github.com/markwragg/PowerShell-Bylaw/actions/workflows/ci.yml/badge.svg)](https://github.com/markwragg/PowerShell-Bylaw/actions/workflows/ci.yml)

Bylaw is a PowerShell module for writing Azure Policy in a Pester-style language. You describe what a *compliant* resource looks like, and Bylaw compiles that into Azure Policy definition JSON, in the [Enterprise Policy as Code (EPAC)](https://github.com/Azure/enterprise-azure-policy-as-code) format or as plain definitions for other tools.

```powershell
Resource 'Microsoft.Storage/storageAccounts' {
    Require 'TLS 1.2 or later' {
        Field minimumTlsVersion | Must -Be 'TLS1_2'
    }
}
```

What it gives you over writing the JSON by hand:

- **Desired state, not violation logic.** You write what must be true. Bylaw works out the `if` condition that finds resources breaking it, including the negations and the handling of missing properties.
- **Short field names, checked at compile time.** `minimumTlsVersion` becomes `Microsoft.Storage/storageAccounts/minimumTlsVersion`. A misspelled alias fails the build, rather than producing a policy that silently never matches.
- **Simple array conditions.** `Each` replaces hand-written `count` and `where` expressions.
- **Less boilerplate.** Effect parameters and their metadata are generated, and role names become role definition IDs.
- **Remediation checked against the rule.** `Modify` operations sit beside the requirements they fix, and the build warns when an operation changes a field no requirement checks.
- **Deterministic output.** The same input always produces byte-identical files, so diffs show only real changes.

Bylaw only compiles. Deploy the output with EPAC, or any other tool that takes policy definition files.

> [!WARNING]
> **Compiling a policy file runs it.** A `.bylaw.ps1` file is a PowerShell script, and `Build-Bylaw` runs it with your permissions. Each file runs in its own runspace, but that is not a security sandbox. Don't build files you don't trust. In CI, don't run `Build-Bylaw` on pull requests from forks with access to secrets.

## Status

Bylaw is at version 0.1.0 and is not yet on the PowerShell Gallery. It has the compiler core (the language below, alias validation, EPAC output) and the Milestone 2 additions: `Modify`, `AnyOf` and `AllOf`, the tag helpers, value conditions, and plain JSON output. The effects are `Audit`, `Deny`, `Disabled` and `Modify`. Next is a decompiler that turns existing policy JSON into Bylaw files. `AuditIfNotExists` and `DeployIfNotExists` come later.

## Install

Bylaw needs PowerShell 7.2 or later, on Windows, Linux or macOS. Compiling needs no Azure modules and no Azure connection.

Until Bylaw is published, build it from source:

```powershell
git clone https://github.com/markwragg/PowerShell-Bylaw.git
Set-Location PowerShell-Bylaw
./build/build.ps1 -Task Package
Import-Module ./out/Bylaw/Bylaw.psd1
```

## Quick start

Save this as `policies/storage-tls.bylaw.ps1`:

```powershell
Policy 'storage-require-tls12' {

    Properties @{
        DisplayName = 'Storage accounts should require TLS 1.2'
        Category    = 'Storage'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Resource 'Microsoft.Storage/storageAccounts' {
        Require 'TLS 1.2 or later' {
            Field minimumTlsVersion | Must -Be 'TLS1_2'
        }
    }

    Effect Deny
}
```

Compile everything under `policies`:

```powershell
Build-Bylaw ./policies -OutputPath ./Definitions/policyDefinitions
```

This writes `Definitions/policyDefinitions/storage-require-tls12.json`. Its rule denies storage accounts whose `minimumTlsVersion` is anything other than `TLS1_2`, including accounts that don't set it:

```json
"policyRule": {
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Storage/storageAccounts"
      },
      {
        "field": "Microsoft.Storage/storageAccounts/minimumTlsVersion",
        "notEquals": "TLS1_2"
      }
    ]
  },
  "then": {
    "effect": "[parameters('effect')]"
  }
}
```

`Effect Deny` became a parameter: allowed values `Audit`, `Deny` and `Disabled`, with a default of `Deny`. The policy behaves as written unless an assignment overrides the effect.

To see the output without writing files, use `-PassThru`:

```powershell
Build-Bylaw ./policies -PassThru | Select-Object Name, Json
```

If something is wrong, the build fails, writes nothing, and reports every error with its file, line and keyword:

```text
policies/storage-tls.bylaw.ps1:12 [Field] BYL2001: Field 'minimumTlsVersoin' of 'Microsoft.Storage/storageAccounts' is not in the alias snapshot. Did you mean 'minimumTlsVersion'? Use Field <name> -AllowUnknownAlias if the alias is newer than the snapshot, or refresh it with Update-BylawAliasCache.
```

## Before and after

A storage policy with two requirements: public network access must be disabled, and no IP rule may allow every address. It applies only to two kinds of storage account.

**You write:**

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

**Bylaw produces:**

```json
{
  "$schema": "https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json",
  "name": "storage-deny-public-network-access",
  "properties": {
    "displayName": "Storage accounts should disable public network access",
    "policyType": "Custom",
    "mode": "All",
    "description": "Denies storage accounts that allow public network access or allow-all IP rules.",
    "metadata": {
      "version": "1.0.0",
      "category": "Storage"
    },
    "parameters": {
      "effect": {
        "type": "String",
        "metadata": {
          "displayName": "Effect",
          "description": "Enable or disable the execution of the policy"
        },
        "allowedValues": [
          "Audit",
          "Deny",
          "Disabled"
        ],
        "defaultValue": "Deny"
      }
    },
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "type",
            "equals": "Microsoft.Storage/storageAccounts"
          },
          {
            "field": "kind",
            "in": [
              "StorageV2",
              "BlockBlobStorage"
            ]
          },
          {
            "anyOf": [
              {
                "field": "Microsoft.Storage/storageAccounts/publicNetworkAccess",
                "notEquals": "Disabled"
              },
              {
                "count": {
                  "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*]",
                  "where": {
                    "field": "Microsoft.Storage/storageAccounts/networkAcls.ipRules[*].value",
                    "equals": "0.0.0.0/0"
                  }
                },
                "greater": 0
              }
            ]
          }
        ]
      },
      "then": {
        "effect": "[parameters('effect')]"
      }
    }
  }
}
```

What the compiler did:

- `Must -Be 'Disabled'` became its violation, `notEquals`. The two `Require` blocks must both hold, so a resource violates the policy if *either* fails: an `anyOf` of the two violations.
- `Each` became a `count` of the elements that break the condition, and `Must -Not -Be` became `equals`.
- Short field names became full aliases. `kind` and `type` are standard fields, so they stay as written.
- `When` narrows the resources the policy applies to. It is not inverted.

[examples/](examples/README.md) has eleven more policies, each with the JSON it compiles to, including tag inheritance with `Modify` and one that uses a PowerShell loop to generate its requirements.

## Writing policies

A file can hold any number of `Policy` blocks. Bylaw finds every `*.bylaw.ps1` file under the path you give it.

| Keyword | Purpose |
|---|---|
| `Policy 'name' { }` | One policy definition. The name becomes the definition's `name` and its file name. |
| `Properties @{ }` | `DisplayName`, `Description`, `Category`, `Version`, `Mode`, `Preview`, `Deprecated`, `Metadata`. EPAC output needs `Category` and `Version`. `Mode` is `All` (the default) or `Indexed`. Unknown keys fail the build. |
| `Parameter Name` | A policy parameter, with `-Type`, `-AllowedValues`, `-Default`, `-DisplayName`, `-Description`. `AllowedLocations` is emitted as `allowedLocations`. |
| `Resource 'type' { }` | The resource type the rule applies to, and the type short field names resolve against. `Resource *` applies to every type; use standard fields such as `location`, or full aliases. |
| `When { }` | Conditions that decide whether the policy applies. Written and emitted as is. |
| `Require 'description' { }` | A requirement a compliant resource meets. All `Require` blocks must hold, and so must all `Must` statements inside one. |
| `Each path[*] { }` | A condition on every element of an array. Can be nested. |
| `AnyOf { }` | Alternatives: holds when any statement inside it holds. Works in `When`, `Require` and `Each`. |
| `AllOf { }` | Inside `AnyOf`, one alternative made of several statements that must all hold. |
| `Field name` | A field: a short name, a standard field (`name`, `type`, `location`, `tags`, ...), or a full alias. `-AllowUnknownAlias` accepts an alias missing from the snapshot. |
| `Element` | The element itself, inside `Each` over an array of plain values. |
| `Tag name` | A tag field, `tags['name']`. `Tag (Param TagName)` takes the name from a parameter. |
| `ResourceGroupTag name` | The resource group's value for a tag, for example `Tag CostCenter \| Must -Be (ResourceGroupTag CostCenter)`. |
| `Must` | An assertion about the `Field`, `Tag` or `Element` piped into it. See the operators below. |
| `Effect` | `Audit`, `Deny` or `Disabled`, or `(Param Effect)`. |
| `Modify -Role ... { }` | The `modify` effect, in place of `Effect`: what to change on a non-compliant resource. See [Modify](#modify). |
| `... \| AddOrReplace v` | Inside `Modify`: sets the piped field or tag to `v`. |
| `... \| Add v` | Inside `Modify`: sets the piped field or tag to `v` only if it has no value. |
| `... \| Remove` | Inside `Modify`: removes the piped tag. Only tags can be removed. |
| `Param Name` | A parameter's value, for example `Must -BeIn (Param AllowedLocations)`. Write `Param Name` or `(Param Name)`, not `Param(Name)`: at the start of a block, PowerShell reads `param(` as a parameter declaration. |
| `Arm '[...]'` | A raw ARM template expression, for anything else. |

`Each` over objects uses the element's fields. Over plain values, it uses `Element`:

```powershell
Require 'No access policy grants purge' {
    Each accessPolicies[*] {
        Each permissions.keys[*] {
            Element | Must -Not -Be 'purge'
        }
    }
}
```

Statements combine with AND. For alternatives, use `AnyOf`. Here a rule is acceptable if it is outbound, or denies traffic, or doesn't come from the internet:

```powershell
Require 'No rule allows inbound traffic from the internet' {
    Each securityRules[*] {
        AnyOf {
            Field direction | Must -Not -Be 'Inbound'
            Field access | Must -Not -Be 'Allow'
            Field sourceAddressPrefix | Must -Not -BeIn '*', 'Internet'
        }
    }
}
```

Keywords other than `Policy` exist only inside a `Policy` block, so they don't clash with commands of the same name, and calling them elsewhere gives a clear error. `Must` was chosen over `Should` so Bylaw and Pester can be used in the same session.

## Operators

Each `Must` takes one operator. The violation column is what Bylaw emits: the condition that finds a resource breaking the requirement.

| `Must` | Compliant when the value... | Azure operator | Violation emitted |
|---|---|---|---|
| `-Be v` | equals `v` | `equals` | `notEquals` |
| `-BeIn a` | is one of `a` | `in` | `notIn` |
| `-BeLike p` | matches a wildcard pattern, with at most one `*` | `like` | `notLike` |
| `-Match p` | matches an Azure match pattern, ignoring case | `matchInsensitively` | `notMatchInsensitively` |
| `-MatchCase p` | matches an Azure match pattern, case-sensitively | `match` | `notMatch` |
| `-ContainText s` | contains the text `s` | `contains` | `notContains` |
| `-ContainKey k` | has the key `k` (for example a tag) | `containsKey` | `notContainsKey` |
| `-Exist` | is present | `exists: true` | `exists: false` |
| `-BeGreaterThan n` | is greater than `n` | `greater` | `lessOrEquals` |
| `-BeGreaterOrEqual n` | is greater than or equal to `n` | `greaterOrEquals` | `less` |
| `-BeLessThan n` | is less than `n` | `less` | `greaterOrEquals` |
| `-BeLessOrEqual n` | is less than or equal to `n` | `lessOrEquals` | `greater` |

| Switch | Effect |
|---|---|
| `-Not` | Reverses the operator: `Must -Not -Be 'X'` emits `equals 'X'` as the violation. |
| `-IfPresent` | A missing field is compliant. Not valid inside `Each`, with `-Exist`, or in `When`. |
| `-Strict` | A missing element field is a violation. Only valid inside `Each`. |

**Azure match patterns are not regular expressions.** `#` matches a digit, `?` a letter, `.` any character, and every other character, including `*`, matches only itself. Bylaw warns about patterns that look like a regex.

`-Match` is case-insensitive, like PowerShell's. `-ContainText` tests text, unlike Pester's `-Contain`, which tests membership of a collection. Values can be literals, `(Param Name)`, `(ResourceGroupTag name)` or `(Arm '[...]')`.

`Must` can also test an expression instead of a field: pipe `ResourceGroupTag`, `Param` or `Arm` into it. For example, `When { ResourceGroupTag CostCenter | Must -Not -Be '' }` applies a policy only to resource groups that have the tag. An expression is never missing, so `-IfPresent`, `-Strict` and `-Exist` don't apply to it, and it can't be used inside `Each` yet.

## Missing fields

A resource often doesn't set the property a requirement checks. Bylaw fails closed: inside a `Require`, a missing field breaks the requirement unless you say otherwise.

| Where | A missing field is | To change it |
|---|---|---|
| `Require` | a violation | `Must -IfPresent` makes it compliant |
| A field inside `Each` | compliant | `Must -Strict` makes it a violation |
| `When` | not treated specially; operators are emitted as written | |
| The array of an `Each` | compliant: a missing or empty array has no elements to break the condition | add `Field path \| Must -Exist` to require it |

Some operators already give the right answer on a missing field, and others don't. `notEquals` finds a missing value, so `Must -Be 'Disabled'` needs nothing extra. `equals` doesn't, so for `Must -Not -Be 'X'` Bylaw adds an `exists` check:

```json
"anyOf": [
  {
    "field": "Microsoft.Storage/storageAccounts/allowSharedKeyAccess",
    "exists": false
  },
  {
    "field": "Microsoft.Storage/storageAccounts/allowSharedKeyAccess",
    "equals": true
  }
]
```

Bylaw adds these checks only where they change the result. An empty string counts as present. To require a non-empty value, add `Must -Not -Be ''`.

The behaviour of each operator on a missing field isn't documented by Microsoft. Bylaw's rules come from measurements in a real subscription, where missing tags and missing properties behaved the same. [ADR-0004](docs/adr/0004-strict-missing-field-behaviour.md) has the full table and the measurement script.

## Modify

`Modify` changes resources instead of denying them: when they're created or updated, and through remediation tasks for existing ones. It takes the place of `Effect`. The `Require` blocks say what a compliant resource looks like, and the operations say how to make one compliant.

This keeps a tag in step with the resource group, as the built-in "Inherit a tag from the resource group" policy does:

```powershell
Policy 'tags-inherit-from-resource-group' {

    Properties @{
        DisplayName = 'Inherit a tag from the resource group'
        Category    = 'Tags'
        Version     = '1.0.0'
        Mode        = 'Indexed'
    }

    Parameter TagName -Type String

    Resource * {
        When {
            ResourceGroupTag (Param TagName) | Must -Not -Be ''
        }
        Require 'The tag matches the resource group' {
            Tag (Param TagName) | Must -Be (ResourceGroupTag (Param TagName))
        }
    }

    Modify -Role 'Tag Contributor' {
        Tag (Param TagName) | AddOrReplace (ResourceGroupTag (Param TagName))
    }
}
```

Its rule and `details` block:

```json
"policyRule": {
  "if": {
    "allOf": [
      {
        "value": "[resourceGroup().tags[parameters('tagName')]]",
        "notEquals": ""
      },
      {
        "field": "[concat('tags[', parameters('tagName'), ']')]",
        "notEquals": "[resourceGroup().tags[parameters('tagName')]]"
      }
    ]
  },
  "then": {
    "effect": "[parameters('effect')]",
    "details": {
      "roleDefinitionIds": [
        "/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f"
      ],
      "operations": [
        {
          "operation": "addOrReplace",
          "field": "[concat('tags[', parameters('tagName'), ']')]",
          "value": "[resourceGroup().tags[parameters('tagName')]]"
        }
      ]
    }
  }
}
```

To add the tag only where it is missing, and keep any value a resource already has, require `Tag (Param TagName) | Must -Exist` and use `Add` instead of `AddOrReplace`. Both forms are in [examples/tags/](examples/tags/).

- **`-Role`** names the roles the assignment's managed identity needs, as built-in role names, GUIDs or full role definition IDs. See [Roles](#roles).
- **`-ConflictEffect`** is `Audit`, `Deny` (Azure's default) or `Disabled`. When `Modify` changes an alias rather than a tag, Azure recommends `Audit`, so that requests using an API version where the property can't be modified aren't denied. Bylaw warns otherwise.
- **`-Effect (Param Effect)`** makes the effect a parameter you declare, which can allow `Modify`, `Audit` and `Disabled`. `Audit` reports non-compliant resources without changing them. Without `-Effect`, EPAC output gets a generated `effect` parameter allowing `Modify` and `Disabled`, as built-in Modify policies do.
- **`-Condition (Arm '[...]')`** on an operation applies it only when the expression is true, for example `[greaterOrEquals(requestContext().apiVersion, '2019-04-01')]`. `field()`, `resourceGroup()` and `subscription()` aren't supported there.
- **What can be changed:** tags, `identity.type` on virtual machines and scale sets, and aliases marked Modifiable in the alias snapshot. Only tags can be removed, and array elements (`[*]`) can't be changed. Anything else fails the build.
- **Remediation that works:** the build warns when an operation changes a field that no `Require` checks, because a remediated resource would still be non-compliant. It also warns about tag operations in a policy whose `Mode` isn't `Indexed`.

> [!NOTE]
> An assignment of a Modify policy needs a managed identity with the roles in `-Role`, even if the assignment sets the effect to `Audit`. Bylaw only writes the definition: create the identity and its role assignments when you assign it.

## Building

```powershell
Build-Bylaw [[-Path] <string[]>] [[-OutputPath] <string>] [-Format <Epac|PlainJson>] [-PassThru]
            [-Settings <string>] [-AliasCachePath <string>] [-RoleCachePath <string>]
            [-AllowUnknownAlias] [-ThrottleLimit <int>] [-WhatIf]
```

- **Formats:** `Epac`, the default, writes EPAC policy definition files with a `$schema`, and generates what EPAC requires: an `effect` parameter for a literal effect, and parameter display names. EPAC also needs `Category` and `Version` in `Properties`. `PlainJson` writes `{ "name", "properties" }`, the layout Azure publishes built-in definitions in, for `New-AzPolicyDefinition`, the Azure CLI, Bicep or Terraform. It emits the policy as written: a literal effect stays literal, nothing is generated, and `Category` and `Version` are optional. The policy rule is the same in both.
- **Output layout:** one file per policy, named after the policy, in a folder structure that mirrors the sources. Files whose content hasn't changed aren't rewritten.
- **All or nothing:** every file is compiled and every error reported. If anything fails, nothing is written.
- **No deletion:** Bylaw never deletes output. It warns about JSON files in the output folder that the build didn't produce, so you can remove policies you've deleted.
- **Isolation:** each file is compiled in a fresh runspace, so variables and functions can't leak between files. Several files compile at once; `-ThrottleLimit` sets how many, and `-ThrottleLimit 1` compiles one at a time. Files that change environment variables or other process-wide state should be built with `-ThrottleLimit 1`.
- **Unique names:** policy names must be unique across a build, ignoring case.

### Aliases

Bylaw checks field names against an alias snapshot, offline. The bundled snapshot only covers the resource types used by the tests and examples (storage accounts, key vaults, virtual machines and network security groups). For anything else, refresh the snapshot from Azure. This needs `Az.Resources` and a signed-in account, and only reads alias metadata:

```powershell
Connect-AzAccount
Update-BylawAliasCache
```

That writes `~/.bylaw/aliases.json`, which Bylaw then uses by default. To limit it to some providers, use `-Namespace 'Microsoft.Storage', 'Microsoft.KeyVault'`. To keep a snapshot with your policies, write it with `-OutputPath` and point `bylaw.json` at it.

The snapshot used is the first of: `-AliasCachePath`, `aliasCache` in `bylaw.json`, `~/.bylaw/aliases.json`, the bundled snapshot.

### Roles

`Modify -Role` takes built-in role names, which Bylaw turns into role definition IDs using a role map, offline. The bundled map only has a starter set of common roles: Owner, Contributor, Reader, Tag Contributor, and the Storage Account, Network, Virtual Machine and Key Vault Contributor roles. For the full list of built-in roles, refresh it from Azure, which only reads role definitions:

```powershell
Update-BylawRoleCache
```

That writes `~/.bylaw/roles.json`. Built-in role IDs are the same in every tenant, so the map can be shared. Custom roles aren't in it; give them by GUID or full role definition ID.

The map used is the first of: `-RoleCachePath`, `roleCache` in `bylaw.json`, `~/.bylaw/roles.json`, the bundled map.

### `bylaw.json`

An optional settings file. Bylaw looks for it from `-Path` upwards, stopping at the repository root, or uses `-Settings`.

```json
{
  "languageVersion": "1.0",
  "aliasCache": "./aliases.json",
  "roleCache": "./roles.json"
}
```

`languageVersion` pins the language's behaviour, so upgrading Bylaw never changes the output of existing policies by surprise. It defaults to `1.0`. Unknown keys fail the build.

## Development

```powershell
./build/build.ps1 -Task Bootstrap      # install the pinned Pester and PSScriptAnalyzer versions
./build/build.ps1                      # analyze and test
./build/build.ps1 -Task Package        # build out/Bylaw
./build/build.ps1 -Task UpdateGolden   # regenerate the expected JSON after an intended output change
```

The tests include golden files: [examples/](examples/), [tests/Golden/](tests/Golden/) and [tests/GoldenPlainJson/](tests/GoldenPlainJson/) hold each policy source next to the exact JSON it must compile to. [tests/Golden/GoldenRoots.psd1](tests/Golden/GoldenRoots.psd1) lists the folders and the format each is built in.

Design decisions are recorded as ADRs in [docs/adr/](docs/adr/), and the original specification is [docs/SPEC.md](docs/SPEC.md).

## Licence

[MIT](LICENSE)
