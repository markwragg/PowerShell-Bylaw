---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# The definition name comes only from Policy 'name' and follows a strict naming rule

## Context and Problem Statement

A policy definition's `name` is its identity. Renaming it creates a new definition and orphans existing assignments. The name must never be derived from something that changes incidentally, such as a file name, the display name or a hash. Which characters and lengths are allowed?

## Considered Options

* Lowercase kebab-case, at most 64 characters
* Anything Azure accepts
* GUIDs only

## Decision Outcome

Chosen option: "Lowercase kebab-case, at most 64 characters".

* The name comes only from the string passed to `Policy 'name'`. File names, display names and paths never affect it.
* Rule: `^[a-z0-9]+(-[a-z0-9]+)*$`, 3 to 64 characters. For example `storage-deny-public-network-access`.
* Names must be unique across a build, ignoring case (ADR-0013).
* The name is also the output file name, `<name>.json` (ADR-0011).

Azure Resource Manager limits definition names to 64 characters and disallows characters such as `<>*%&:\?.+/`. The Microsoft Learn pages for definition structure don't state this. The Bylaw rule is a strict subset of what Azure accepts, so any valid Bylaw name is also valid in Azure.

### Consequences

* Good, because names are readable, safe as file names on every operating system, and stable.
* Bad, because existing definitions with other names (for example mixed case, underscores or uppercase GUIDs) can't be migrated to Bylaw unchanged. A future `-AllowLegacyName` switch could relax the rule, and would be a separate ADR.

### Confirmation

Unit tests cover valid and invalid names, the length limit and duplicate names.

## More Information

* [ADR-0028](0028-policy-names.md) (proposed) replaces the naming rule with any name Azure accepts that is also a safe file name, so existing definitions such as the Azure Landing Zones Library's can keep their names. The rest of this ADR stands.
