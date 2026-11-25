---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Record architecture decisions as MADR files

## Context and Problem Statement

Bylaw makes a number of design choices that are hard to reverse once policies are written against them: DSL semantics, output format, alias handling and so on. Contributors need to see what was decided, why, and which alternatives were rejected.

## Considered Options

* Markdown Architectural Decision Records (MADR 4.0.0) in `docs/adr/`
* Decisions recorded only in the spec and in pull request descriptions
* A wiki

## Decision Outcome

Chosen option: "MADR 4.0.0 in `docs/adr/`", because the records are versioned with the code, reviewed in the same pull requests and readable without extra tooling.

### Consequences

* Good, because every significant decision has a durable, reviewable record.
* Bad, because ADRs must be kept up to date. A changed decision needs a new ADR that supersedes the old one, not an in-place rewrite.

### Confirmation

Pull requests that change a recorded decision must add or update an ADR. Reviewers check this.

## More Information

* Files are named `NNNN-short-title.md`, numbered sequentially from `0001`.
* `adr-template.md` is the unmodified MADR 4.0.0 full template.
* Status values: `proposed`, `accepted`, `rejected`, `deprecated`, `superseded by ADR-NNNN`.
* The index is in [README.md](README.md).
