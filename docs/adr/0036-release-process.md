---
status: accepted
date: 2026-11-27
decision-makers: Bylaw maintainers
---

# Releases are published from main when CHANGELOG.md has a "## !Deploy" heading

## Context and Problem Statement

Bylaw is to be published to the PowerShell Gallery. The maintainer's other modules release the same way: changes go under a `## !Deploy` heading in `CHANGELOG.md`, and when that reaches the default branch the build publishes, replaces the heading with the version and date, commits that back, and creates a GitHub release with the section as its notes. Those modules do this with psake, BuildHelpers, PSDeploy and a task that joins every `.ps1` file into one `.psm1`. Bylaw has its own `build/build.ps1`, and its `Package` task already builds the module it would ship, with its class load order, its data files and a smoke test (ADR-0006). How does Bylaw release, and how is the README's coverage badge kept current?

## Decision Drivers

* Releasing works the same way as the maintainer's other modules.
* What is published is what `Package` builds and smoke-tests.
* Preview releases are possible: Bylaw starts as `0.1.0-alpha`, and the Gallery orders a prerelease before its stable version.
* No new build dependencies.

## Considered Options

* The changelog convention, as tasks in `build/build.ps1`
* The other modules' build, copied as is
* Tagging a commit to release

## Decision Outcome

Chosen option: "The changelog convention, as tasks in `build/build.ps1`".

### The Deploy heading

* `## !Deploy` on a line of its own requests a release of the changes under it. `## !Deploy 0.2.0` or `## !Deploy 0.2.0-beta` pins the version. A version is `major.minor.patch`, optionally with a label of letters and digits, which is what the Gallery accepts for a prerelease.
* A pinned version must be newer than the newest version on the Gallery, prereleases included, so a typo can't ship an old version. Without a pin, the release is the next patch after the newest published version, with the manifest's `Prerelease` label. The first release uses the manifest's version.
* More than one Deploy heading is an error. Without one, nothing is published.

### The Publish task

`./build/build.ps1 -Task Publish` reads the heading and:

1. Fails if `NUGET_API_KEY` isn't set, so a requested release is never skipped silently.
2. Sets `ModuleVersion` and `Prerelease` in `src/Bylaw.psd1`. A stable version comments out the `Prerelease` line.
3. Runs `Package`, including its smoke test, and publishes `out/Bylaw` with `Publish-PSResource`.
4. Replaces the heading with `## [version] - yyyy-MM-dd`, and writes that section to `out/release-notes.md`.

The text changes are functions in `build/Release.ps1`, tested by `tests/Build/Release.Tests.ps1`.

### The pipeline

A `release` job runs after the test matrix, on pushes to `main` only:

1. Runs the tests with code coverage (`Test -CI -Coverage`, written to `out/coverage.xml`). Coverage roughly doubles the test time, so pull requests don't measure it.
2. `UpdateCoverageBadge` sets the shields.io badge in the README to the share of commands covered, rounded down.
3. `Publish`, as above.
4. Commits the README, changelog and manifest to `main` with `[skip ci]`, if any changed. `main` isn't protected, so the job's token can push.
5. After a publish, creates the release `v<version>` on that commit with `gh`, marked as a prerelease when the version has a label, with the notes and the zipped module attached.

### Consequences

* Good, because releasing is the same as in the maintainer's other modules: edit the changelog.
* Good, because the published module is the one `Package` built and smoke-tested.
* Good, because the version check makes a stale or mistyped version fail before anything is published.
* Bad, because the job pushes to `main`. If `main` becomes protected, the job needs a token that may bypass the protection.
* Bad, because if the push fails after a publish, the changelog still has its Deploy heading, and the next build fails the version check until the heading is dated by hand.

### Confirmation

`tests/Build/Release.Tests.ps1` covers the Deploy heading, the version rules, the manifest and changelog edits and the badge, including against the real manifest and README. The first release, `0.1.0-alpha`, confirms the pipeline end to end.

## Pros and Cons of the Options

### The changelog convention, as tasks in `build/build.ps1`

* Good, because it reuses Bylaw's build and `Package`.
* Neutral, because the convention's code is rewritten, not shared with the other modules.

### The other modules' build, copied as is

* Good, because it is already proven.
* Bad, because its join step would lose Bylaw's class load order and data files, and it adds four build dependencies.

### Tagging a commit to release

* Good, because it is common in other projects.
* Bad, because it differs from the maintainer's other modules, and the changelog still needs updating by hand.
