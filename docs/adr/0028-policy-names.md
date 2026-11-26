---
status: proposed
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Policy names accept any name Azure accepts that is also a safe file name

## Context and Problem Statement

ADR-0010 limits names to lowercase kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`). That keeps new names tidy, but existing definitions can't be brought into Bylaw with their names. Every one of the 149 custom definitions in the Azure Landing Zones Library has capitals, for example `Deny-Storage-minTLS`. EPAC and Azure use the name as the definition's identity, so renaming a definition creates a new one and orphans its assignments. Initiatives (Milestone 4) and the decompiler (Milestone 5) will meet the same names. Which names should Bylaw accept?

## Decision Drivers

* Existing definitions keep their identity when they move to Bylaw.
* The name is also the output file name, so it must be safe on Windows, Linux and macOS.
* The name still comes only from `Policy 'name'` (ADR-0010).

## Considered Options

* Accept any name Azure accepts that is also a safe file name
* Keep the strict rule, with an opt-in setting to relax it
* Keep the strict rule; tools that import definitions lowercase the name

## Decision Outcome

Proposed: "Accept any name Azure accepts that is also a safe file name".

* A name is 1 to 64 characters. It can't contain `<`, `>`, `*`, `%`, `&`, `:`, `\`, `?`, `.`, `+` or `/`, which Azure Resource Manager rejects, nor `"`, `|` or control characters, which aren't safe in file names. It can't start or end with a space, and it can't be a Windows reserved device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`), ignoring case.
* Lowercase kebab-case stays the recommended style in the documentation and examples, but isn't enforced or warned about. A warning would fire on every policy imported from ALZ or the portal, and the author can't change those names without changing the definitions' identity.
* Names stay unique across a build, ignoring case (ADR-0013). That also prevents two output files whose names differ only in case, which would clash on Windows and macOS.
* This replaces the naming rule in ADR-0010. The rest of ADR-0010 stands: the name comes only from `Policy 'name'`.
* The same rule will apply to initiative names (Milestone 4).

### Consequences

* Good, because existing definitions keep their names and their assignments.
* Good, because every accepted name is valid in Azure and as a file name on every operating system.
* Bad, because a build can mix naming styles. That is a review concern, not a compiler one.

### Confirmation

Unit tests cover each disallowed character, the length limits, leading and trailing spaces, reserved device names, mixed-case names such as `Deny-Storage-minTLS`, and duplicate names that differ only in case.

## Pros and Cons of the Options

### Accept Azure-valid, file-safe names

* Good, because nothing has to be renamed to move to Bylaw.
* Bad, because new names aren't held to one style.

### Strict rule with an opt-in setting

* Good, because new projects stay tidy by default.
* Bad, because every project with existing definitions needs the setting, and a setting that changes which names are valid is easy to misunderstand.

### Lowercase on import

* Good, because the rule stays simple.
* Bad, because it changes the identity of every imported definition, which creates duplicates in Azure.

## More Information

* Supersedes the naming rule in [ADR-0010](0010-definition-name-stability.md).
* Related: [ADR-0013](0013-discovery-by-convention.md)
