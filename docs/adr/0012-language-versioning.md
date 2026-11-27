---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# The language version is set in a bylaw.json project settings file, defaulting to 1.0

## Context and Problem Statement

DSL semantics will change over time: new keywords, corrected missing-field rules, different defaults. Existing policies must keep compiling to the same output after a module upgrade, unless the author opts into new behaviour.

## Considered Options

* `languageVersion` in a `bylaw.json` project settings file
* A version declared per file (for example `#requires`-style)
* The module version is the language version

## Decision Outcome

Chosen option: "`languageVersion` in `bylaw.json`", defaulting to `1.0` when there is no file or no setting.

### `bylaw.json`

```json
{
  "languageVersion": "1.0",
  "aliasCache": "./aliases.json"
}
```

* Keys: `languageVersion`, `aliasCache` (ADR-0008) and `roleCache` (ADR-0022). Unknown keys are a build error, so typos aren't silently ignored.
* **Discovery:** `-Settings <path>` if given. Otherwise the file is searched for upward from `-Path`, stopping at the first folder that contains `.git`, or at the filesystem root.
* An unsupported `languageVersion` is a build error that lists the supported versions.

### Versioning rules

* `major.minor`. A minor version only adds things: new keywords and operators, with no change to the output of existing input. A major version may change semantics or output.
* The compiler looks up behaviour through the language version, not the module version.
* Every module release documents the language versions it supports.

### Before the first public release

These rules protect published users, and there are none yet. Until Bylaw is first released publicly, language version `1.0` stays open: new keywords and changes to output are added to `1.0` directly, and golden files are regenerated. From the first public release, `1.0` is frozen and the rules above apply. Everything added so far, such as `Modify`, the other effects, `Count` and initiatives, is part of `1.0` on this basis.

### Consequences

* Good, because upgrading the module never changes output by surprise.
* Bad, because the compiler has to keep old behaviour behind version checks. Old major versions can be deprecated through an ADR.

### Confirmation

Tests cover discovery, the default, unknown keys and unsupported versions.
