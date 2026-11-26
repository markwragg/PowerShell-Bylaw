---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# The definition name comes only from Policy 'name', and can be any name Azure accepts that is also a safe file name

## Context and Problem Statement

A policy definition's `name` is its identity. EPAC and Azure use it to match a definition with its assignments, so renaming it creates a new definition and orphans the old one's assignments. The name must never be derived from something that changes incidentally, such as a file name, the display name or a hash.

Which names are allowed? Existing definitions should be able to move to Bylaw with their names. Every one of the 149 custom definitions in the Azure Landing Zones Library has capitals, for example `Deny-Storage-minTLS`, and initiatives (Milestone 4) and the decompiler (Milestone 5) will meet the same names. The name is also the output file name, so it must be safe on Windows, Linux and macOS.

## Decision Drivers

* Existing definitions keep their identity when they move to Bylaw.
* Every accepted name is valid in Azure and as a file name on every operating system.

## Considered Options

* Any name Azure accepts that is also a safe file name
* Lowercase kebab-case only, at most 64 characters
* Lowercase kebab-case, with an opt-in setting to relax it
* GUIDs only

## Decision Outcome

Chosen option: "Any name Azure accepts that is also a safe file name".

* The name comes only from the string passed to `Policy 'name'`. File names, display names and paths never affect it.
* A name is 1 to 64 characters. It can't contain `<`, `>`, `*`, `%`, `&`, `:`, `\`, `?`, `.`, `+` or `/`, which Azure Resource Manager rejects, nor `"`, `|` or control characters, which aren't safe in file names. It can't start or end with a space, and it can't be a Windows reserved device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`), ignoring case. A name that breaks the rule is BYL3001.
* Lowercase kebab-case, such as `storage-deny-public-network-access`, is the recommended style in the documentation and examples, but isn't enforced or warned about. A warning would fire on every policy imported from ALZ or the portal, and the author can't change those names without changing the definitions' identity.
* Names must be unique across a build, ignoring case (ADR-0013). That also prevents two output files whose names differ only in case, which would clash on Windows and macOS.
* The name is also the output file name, `<name>.json` (ADR-0011), in the case it is written.
* The same rule will apply to initiative names (Milestone 4).

Azure Resource Manager limits definition names to 64 characters and disallows `<>*%&:\?.+/`. The Microsoft Learn pages for definition structure don't state this.

### Consequences

* Good, because existing definitions keep their names and their assignments.
* Good, because every accepted name is valid in Azure and as a file name on every operating system.
* Bad, because a build can mix naming styles. That is a review concern, not a compiler one.

### Confirmation

Unit tests cover each disallowed character, the length limits, leading and trailing spaces, reserved device names, mixed-case names such as `Deny-Storage-minTLS`, and duplicate names that differ only in case.

## Pros and Cons of the Options

### Any name Azure accepts that is also a safe file name

* Good, because nothing has to be renamed to move to Bylaw.
* Bad, because new names aren't held to one style.

### Lowercase kebab-case only

* Good, because names are uniform and readable.
* Bad, because existing definitions with other names can't move to Bylaw without changing their identity, which creates duplicates in Azure.

### Kebab-case with an opt-in setting

* Good, because new projects stay tidy by default.
* Bad, because every project with existing definitions needs the setting, and a setting that changes which names are valid is easy to misunderstand.

### GUIDs only

* Good, because names never collide.
* Bad, because names are unreadable in output, reviews and file listings.

## More Information

* Milestones 1 and 2 used the kebab-case rule (`^[a-z0-9]+(-[a-z0-9]+)*$`, 3 to 64 characters). Milestone 3 replaced it, before Bylaw was published, so existing definitions such as the Azure Landing Zones Library's can keep their names.
* Related: [ADR-0011](0011-epac-default-output.md), [ADR-0013](0013-discovery-by-convention.md)
