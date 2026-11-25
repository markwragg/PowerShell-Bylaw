---
status: proposed
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Which typed ARM expression helpers ship in v1

## Context and Problem Statement

Policy values often use ARM template expressions: `[parameters('x')]`, `[resourceGroup().tags['owner']]`, `[field('location')]`, `[concat(...)]`, `[requestContext().apiVersion]`. Typed helpers allow validation (for example that a parameter exists) and keep authors away from quoting mistakes. Each helper is also surface area to maintain and something the decompiler must recognise. Which helpers ship in v1 beyond `Param`, `Tag`, `ResourceGroupTag` and `Arm`?

## Decision Drivers

* Cover the most common expressions with validation.
* Keep the v1 surface small. `Arm` covers everything else.
* Let real data from the ALZ coverage report (Milestone 3) drive what gets added.

## Considered Options

* Only `Param`, `Tag`, `ResourceGroupTag` and `Arm`. Decide on more from ALZ coverage data.
* Also add `FieldValue`, `ResourceGroupLocation`, `SubscriptionId` and `Concat` now
* A general typed expression builder (`Fn concat (...)`)

## Decision Outcome

Proposed: "Only `Param`, `Tag`, `ResourceGroupTag` and `Arm`, then decide from ALZ coverage data".

* `Param Name` emits `[parameters('<jsonName>')]`. The parameter must exist (ADR-0021).
* `Tag name` emits the field `tags['name']`. If `name` is `Param`, it emits `[concat('tags[', parameters('x'), ']')]`. Milestone 2.
* `ResourceGroupTag name` emits `[resourceGroup().tags['name']]`. Milestone 2.
* `Arm '[...]'` is passed through exactly as written. The compiler checks only that the value starts with `[` and ends with `]`, and that it isn't `[[` (an escaped literal). Any `parameters('x')` names referenced inside are checked against the declared parameters on a best-effort basis, as a warning.
* The Milestone 3 coverage report counts which `Arm` patterns appear most often in ALZ policies. Helpers for the top patterns are proposed in a follow-up ADR.

### Consequences

* Good, because the surface stays minimal and choices are driven by evidence.
* Bad, because common expressions such as `[field('location')]` need `Arm` in v1.

## Pros and Cons of the Options

### Minimal set, data-driven later

* Good, because nothing speculative gets added.
* Bad, because v1 policies will use `Arm` more.

### Larger set now

* Good, because it is more ergonomic immediately.
* Bad, because every helper has to be kept compatible across language versions, even if few people use it.

### General expression builder

* Good, because it covers everything.
* Bad, because it amounts to reimplementing ARM expression syntax in PowerShell, with little benefit over `Arm`.
