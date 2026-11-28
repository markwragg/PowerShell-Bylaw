---
status: proposed
date: 2026-11-28
decision-makers: Bylaw maintainers
---

# A pinned copy of the Azure Landing Zones Library is test data, with a coverage report and a regression baseline

## Context and Problem Statement

The Azure Landing Zones Library (ALZ) is the largest public set of custom Azure Policy definitions, and the reference for what Bylaw must be able to express: 149 custom policy definitions and 44 initiatives in its `platform/alz` library (checked 2026-11-28; ADR-0010). Converting all of it is the best test of the decompiler (ADR-0039) and the language, and its results tell users what to expect when they migrate. ALZ is MIT licensed, copyright Microsoft Corporation, which allows copying it with its notice (checked 2026-11-28; recorded in the spec). How is ALZ content brought into the repository, what is measured, and how is it kept from regressing?

## Decision Drivers

* Reproducible: the same commit of Bylaw gives the same results.
* The licence's terms are met: the copyright notice and licence text travel with the content.
* Never shipped: ALZ content isn't part of the published module.
* A change that makes Bylaw convert fewer definitions fails the build.
* Keeping up with ALZ is a deliberate step, not an accident of the network.

## Considered Options

* A pinned copy committed as test data, with a baseline
* Downloaded at test time
* A git submodule

## Decision Outcome

Chosen option: "A pinned copy committed as test data, with a baseline".

### The copy

* `tests/Alz/` holds the policy definitions and policy set definitions from ALZ's `platform/alz` library, as they are in ALZ, at one commit. Other content, such as archetypes and assignments, isn't copied.
* `tests/Alz/THIRD-PARTY-NOTICES.md` has Microsoft's copyright line, the full MIT licence text, the source repository and the commit.
* `build/alz/Update-AlzSnapshot.ps1 -Commit <sha>` replaces the copy with another commit, rewrites the notice, and stops if the repository's licence is no longer MIT, so a change of licence is never picked up unnoticed. It reads the commit through the GitHub API, without cloning.
* `.gitattributes` marks the copy as vendored, so it doesn't count in the repository's language statistics, and it is outside `src/`, so `Package` doesn't publish it.

### The coverage report

* `build/alz/Get-AlzCoverage.ps1` converts every definition in the copy with `ConvertFrom-PolicyJson`, and reports per definition: `Converted`, `EscapeHatch` (with the conditions that needed `Condition`, ADR-0040), or `Failed` (with the diagnostics). It writes `out/alz-coverage.md` and `out/alz-coverage.json`.
* It can also run against the latest ALZ, fetched into an ignored folder, to see what an update would change before pinning it.
* The README gives the totals for the pinned commit, such as "143 of 149 converted, 4 with the escape hatch, 2 failed", updated when the copy or the baseline changes.

### The baseline

* `tests/Alz/baseline.json` records the expected status of each definition.
* A test converts the copy and fails when any definition's status is worse than its baseline: `Converted` to `EscapeHatch` or `Failed`, or `EscapeHatch` to `Failed`. A better status also fails, with a message to update the baseline, so improvements are recorded rather than lost.
* Every `Converted` and `EscapeHatch` result is also proven equivalent to its input (ADR-0041), so the test checks the conversions are right, not only that they ran.
* The test runs with the others, so it costs CI time. If it is slow, it can be tagged and run on demand.

### Consequences

* Good, because the decompiler and the language are measured against the definitions people most often migrate, and can't silently get worse.
* Good, because the licence's terms are met in one visible place.
* Bad, because the repository carries a few hundred ALZ files, which need updating deliberately.
* Bad, because the README's totals go stale if the baseline is updated without them. The baseline update script will print the new totals to copy in.

### Confirmation

The baseline test passes on the pinned copy; the notice matches the pinned commit and the licence; and `Package` output contains no ALZ file.

## Pros and Cons of the Options

### A pinned copy committed as test data

* Good, because results are reproducible offline, and changes to ALZ are reviewed as a diff.
* Bad, because the copy must be updated by hand.

### Downloaded at test time

* Good, because nothing extra is committed.
* Bad, because a test result depends on the network and on ALZ's latest commit, so a change in ALZ can fail an unrelated change to Bylaw.

### A git submodule

* Good, because it pins a commit without copying files.
* Bad, because it brings the whole ALZ repository, needs `git submodule update`, and the notice still has to be added beside it.
