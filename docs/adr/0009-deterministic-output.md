---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Byte-identical output from a canonical JSON writer

## Context and Problem Statement

Compiled policies are committed and reviewed as diffs, and EPAC redeploys any definition whose content changes. Output must not change unless the input changes, on any operating system or PowerShell version.

`ConvertTo-Json` doesn't guarantee this. It truncates at depth 2 by default, writes line endings that depend on the platform, and its escaping and number formatting can differ between PowerShell releases.

## Considered Options

* A Bylaw-owned canonical JSON writer
* `ConvertTo-Json` with post-processing
* `System.Text.Json` with custom options

## Decision Outcome

Chosen option: "A Bylaw-owned canonical JSON writer", because it is the only option whose output Bylaw fully controls.

### Format

* UTF-8 without BOM. LF line endings. A single trailing newline.
* 2-space indentation, one key or array item per line, `"key": value` with one space after the colon.
* Empty objects are written as `{}` and empty arrays as `[]`.
* Strings: escape `"` and `\`. Control characters use `\b \f \n \r \t`, otherwise `\u00XX`. All other characters, including non-ASCII ones, are written as literal UTF-8. `/` and `'` are not escaped.
* Numbers use the invariant culture. Integers are written without a decimal point. Doubles use the shortest representation that round-trips. `NaN` and infinity are compile errors.
* Booleans and null are written as `true`, `false` and `null`.

### Key order

The order is fixed by the schema, not alphabetical, so the output reads like hand-written policy:

| Object | Order |
|---|---|
| EPAC file | `$schema`, `name`, `properties` |
| `properties` | `displayName`, `policyType`, `mode`, `description`, `metadata`, `parameters`, `policyRule` |
| `metadata` | `version`, `category`, `preview`, `deprecated`, then user keys sorted by ordinal comparison |
| `parameters` | declaration order |
| parameter | `type`, `metadata` (`displayName`, `description`, then others), `allowedValues`, `defaultValue` |
| `policyRule` | `if`, `then` |
| condition | `field` / `value` / `count`, then the operator |
| `count` | `field` / `value`, `name`, `where` |
| `then` | `effect`, `details` |

Hashtable input, such as `Properties.Metadata`, is ordered by ordinal key comparison. Ordered input keeps declaration order.

### Consequences

* Good, because builds can be reproduced byte for byte across Windows, Linux and macOS.
* Bad, because there is a small serialiser to maintain, which needs its own tests.
* The repository's `.gitattributes` must pin LF for golden files. Otherwise Windows checkouts with `core.autocrlf=true` break byte comparisons.

### Confirmation

* Golden tests compare bytes.
* A CI step compiles the examples twice and compares the hashes.
* The CI matrix covers all three operating systems.
