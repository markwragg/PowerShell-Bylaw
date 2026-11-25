# Architecture decision records

Bylaw records significant design decisions as [MADR 4.0.0](https://adr.github.io/madr/) files. See [ADR-0001](0001-record-architecture-decisions.md). New ADRs start from [adr-template.md](adr-template.md).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions as MADR files | Accepted |
| [0002](0002-desired-state-semantics.md) | Authors describe the compliant state; the compiler inverts it | Accepted |
| [0003](0003-requirements-combine-with-and.md) | Multiple Require blocks and multiple Must statements combine with AND | Accepted |
| [0004](0004-strict-missing-field-behaviour.md) | Missing fields fail requirements by default (strict), with explicit leniency | Accepted (verification pending) |
| [0005](0005-keyword-scoping.md) | Only Policy and the utility cmdlets are exported; inner keywords exist only inside Policy | Accepted |
| [0006](0006-intermediate-representation.md) | Keywords build an IR of PowerShell classes; passes transform it; emitters serialise it | Accepted |
| [0007](0007-compile-only.md) | Bylaw compiles policy definitions and never deploys them | Accepted |
| [0008](0008-bundled-alias-snapshot.md) | Resolve and validate aliases offline against a bundled snapshot | Accepted |
| [0009](0009-deterministic-output.md) | Byte-identical output from a canonical JSON writer | Accepted |
| [0010](0010-definition-name-stability.md) | The definition name comes only from Policy 'name' and follows a strict naming rule | Accepted |
| [0011](0011-epac-default-output.md) | EPAC policy definition files are the default output, one file per policy | Accepted |
| [0012](0012-language-versioning.md) | The language version is set in a bylaw.json project settings file, defaulting to 1.0 | Accepted |
| [0013](0013-discovery-by-convention.md) | Build-Bylaw discovers *.bylaw.ps1 files recursively; names are unique across a build | Accepted |
| [0014](0014-runspace-isolation.md) | Each source file is compiled in a fresh runspace | Accepted |
| [0015](0015-must-operator-vocabulary.md) | Must operator names follow PowerShell expectations, not raw Azure operator names | Accepted |
| [0016](0016-properties-mapping-and-defaults.md) | How Properties keys map into the definition, and their defaults | Accepted |
| [0017](0017-effects-in-language-version-1-0.md) | Effects supported in Milestone 1, and how they are validated | Accepted |
| [0018](0018-parameter-name-casing.md) | Parameter name casing in emitted JSON | Proposed |
| [0019](0019-provenance-metadata.md) | Provenance metadata in emitted definitions | Proposed |
| [0020](0020-arm-expression-helpers.md) | Which typed ARM expression helpers ship in v1 | Proposed |
| [0021](0021-parameter-usage-validation.md) | Compile-time validation of parameter declarations and usage | Proposed |
| [0022](0022-modify-role-resolution.md) | Resolving built-in role names for Modify -Role | Proposed |
