---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Which typed ARM expression helpers ship in v1

## Context and Problem Statement

Policy values often use ARM template expressions: `[parameters('x')]`, `[resourceGroup().tags['owner']]`, `[field('location')]`, `[concat(...)]`, `[requestContext().apiVersion]`. Typed helpers allow validation (for example that a parameter exists) and keep authors away from quoting mistakes. Each helper is also surface area to maintain and something the decompiler must recognise. Which helpers ship in v1 beyond `Param`, `Tag`, `ResourceGroupTag` and `Arm`?

## Decision Drivers

* Cover the most common expressions with validation.
* Keep the v1 surface small. `Arm` covers everything else.
* Let real data from the ALZ coverage report (Milestone 5) drive what gets added.

## Considered Options

* Only `Param`, `Tag`, `ResourceGroupTag` and `Arm`. Decide on more from ALZ coverage data.
* Also add `FieldValue`, `ResourceGroupLocation`, `SubscriptionId` and `Concat` now
* A general typed expression builder (`Fn concat (...)`)

## Decision Outcome

Chosen option: "Only `Param`, `Tag`, `ResourceGroupTag` and `Arm`, then decide from ALZ coverage data".

* `Param Name` emits `[parameters('<jsonName>')]`. The parameter must exist (ADR-0021).
* `Tag name` is a field reference to the tag, `tags['name']`. It can be piped into `Must` and into `Modify` operations (ADR-0024).
  * `Tag (Param TagName)` emits the field `[concat('tags[', parameters('tagName'), ']')]`, as Azure's built-in tag policies do.
  * A tag name containing `'`, `[` or `]` is a compile error (`BYL1023`), because it can't be written safely inside `tags['...']`.
  * A parameter that holds a tag name must be declared, and must be of type `String` (`BYL3034`).
  * `Tag` is a compile error inside `Each`, because fields there refer to the array element.
  * `Tag` is shorthand for `Field "tags['name']"`, so the two compile to the same output.
* `ResourceGroupTag name` is a value: `[resourceGroup().tags['name']]`.
  * `ResourceGroupTag (Param TagName)` emits `[resourceGroup().tags[parameters('tagName')]]`.
  * It can be used wherever a value is expected (`Must -Be (ResourceGroupTag CostCenter)`, a `Modify` operation's value), and piped into `Must` as a value condition (ADR-0025).
  * The same name rule as `Tag` applies.
* `Arm '[...]'` is passed through exactly as written. The compiler checks only that the value starts with `[` and ends with `]`, and that it isn't `[[` (an escaped literal). Any `parameters('x')` names referenced inside are checked against the declared parameters on a best-effort basis, as a warning.
* The Milestone 5 coverage report counts which `Arm` patterns appear most often in ALZ policies. Helpers for the top patterns are proposed in a follow-up ADR.

### Consequences

* Good, because the surface stays minimal and choices are driven by evidence.
* Bad, because common expressions such as `[field('location')]` need `Arm` in v1.

### Confirmation

Unit tests cover each helper with a literal name and with `Param`, the name rule, and the equivalence of `Tag x` and `Field "tags['x']"`. The tag inheritance golden test uses both `Tag` and `ResourceGroupTag` with a parameter.

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
