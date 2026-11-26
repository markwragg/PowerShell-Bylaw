---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Build-Bylaw discovers *.bylaw.ps1 files recursively; names are unique across a build

## Context and Problem Statement

How does `Build-Bylaw` find the policies to compile, and what happens with several policies per file or duplicate names?

## Considered Options

* Recursive discovery of `*.bylaw.ps1`
* An explicit manifest listing the files
* Any `*.ps1` that contains `Policy`

## Decision Outcome

Chosen option: "Recursive discovery of `*.bylaw.ps1`".

* `-Path` accepts files and folders, and several of each. Folders are searched recursively for `*.bylaw.ps1`. Other `.ps1` files are ignored, so helper scripts can live alongside policies.
* Files are processed in ordinal order of their path relative to `-Path`, so diagnostics and `-PassThru` results come out in a stable order.
* One file can contain several `Policy` blocks. A file with none is a warning.
* Names must be unique across the whole build, ignoring case. A duplicate is an error that gives both locations (file and line). In Milestone 4 (proposed), this covers policies and initiatives together ([ADR-0033](0033-initiatives.md)).
* `Build-Bylaw` compiles every file and reports **all** errors before failing, not just the first. It writes no output at all if any file fails, so a broken build never leaves partial output.

### `Build-Bylaw` parameters

| Parameter | Purpose |
|---|---|
| `-Path` | Source files or folders. Defaults to the current folder. |
| `-OutputPath` | Output folder. Required unless `-PassThru` is used alone. |
| `-Format` | `Epac` (the default, ADR-0011) or `PlainJson` (ADR-0027). |
| `-PassThru` | Returns one result object per policy: `Name`, `SourceFile`, `SourceLine`, `OutputFile`, `Json`, `Warnings`. |
| `-Settings` | An explicit path to `bylaw.json` (ADR-0012). |
| `-AliasCachePath` | Alias snapshot override (ADR-0008). |
| `-RoleCachePath` | Role map override for `-Role` (ADR-0022). |
| `-AllowUnknownAlias` | Allows unknown aliases for the whole build (ADR-0008). |
| `-ThrottleLimit` | How many files to compile at once, each in its own runspace (ADR-0014). Output is the same either way. |

`-PassThru` without `-OutputPath` compiles in memory and writes nothing, which is useful in Pester tests.

### Consequences

* Good, because adding a policy needs no configuration.
* Bad, because a mistyped extension (for example `.bylaw.ps`) means the file is silently skipped. Mitigation: `-Verbose` lists the files that were found.

### Confirmation

Tests cover discovery, ordering, several policies per file, duplicate names across files, aggregated errors and the no-partial-output rule.
