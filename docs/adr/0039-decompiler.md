---
status: accepted
date: 2026-11-28
decision-makers: Bylaw maintainers
---

# ConvertTo-Bylaw turns policy JSON into Bylaw files that compile back to the same rule

## Context and Problem Statement

Teams adopting Bylaw already have policy definitions as JSON: their own, EPAC's, the Azure Landing Zones Library's, or exported from Azure. Rewriting them by hand is slow, and easy to get subtly wrong, which is the problem Bylaw exists to solve. A decompiler, `ConvertTo-Bylaw`, was planned from the start (ADR-0005, ADR-0006), and the IR already keeps `Not` and generic groups for it.

Decompiling isn't the reverse of a single step. An `if` condition finds violations, while Bylaw describes compliance, split into `When` and `Require`. Compiling also adds missing-field guards (ADR-0004), generates effect parameters (ADR-0017) and resolves short alias names (ADR-0008). Hand-written JSON follows none of Bylaw's patterns. How does `ConvertTo-Bylaw` produce a readable `.bylaw.ps1` file, and how does it know the file is right?

## Decision Drivers

* **Correct first:** a converted file compiles to a rule with the same meaning as the input. A readable file that means something else is worse than none.
* **Readable second:** the output looks like what a person would write: short field names, `Require` blocks that say what they require, and an effect parameter only when the input had a real one.
* **Honest:** what can't be converted is reported, per definition, never silently dropped or approximated.
* Works on any policy JSON, not only Bylaw's own output.

## Considered Options

* Convert, then prove the result by compiling it and comparing
* Convert with fixed patterns, without checking
* Convert everything to raw conditions

## Decision Outcome

Chosen option: "Convert, then prove the result by compiling it and comparing".

### The command

The command is `ConvertTo-Bylaw`: it reads as "convert this JSON to Bylaw", and carries Bylaw's name like the other commands, so it is unlikely to clash with another module's. The spec's earlier name was `ConvertFrom-PolicyJson`.

```powershell
ConvertTo-Bylaw -Path ./Definitions -OutputPath ./policies
Get-AzPolicyDefinition -Custom | ConvertTo-Bylaw -OutputPath ./policies
```

* **Input:** `-Path` takes files and folders of policy and policy set definitions in the EPAC format, plain `{ name, properties }` JSON, or a bare `properties` object, and objects from `Get-AzPolicyDefinition` and `Get-AzPolicySetDefinition` on the pipeline. Built-in definitions can be converted too.
* **Output:** one `.bylaw.ps1` file per definition, named after it, mirroring the input folders. A DeployIfNotExists template is written beside it, in `templates/<name>.json`, and referenced with `-TemplateFile` (ADR-0031). `-PassThru` returns, per definition: name, source, the script text, a status, and diagnostics. Without `-OutputPath`, nothing is written.
* **Status:** `Converted` (the file uses only the language), `EscapeHatch` (it uses raw conditions for some parts, ADR-0040), or `Failed` (nothing was written, and the diagnostics say why). Diagnostics are a new range, BYL6xxx, in the catalogue (ADR-0037).
* Existing files are never overwritten unless `-Force` is given.

### How it converts

1. **Read** the JSON into the IR, which can hold any supported condition, including `not` and generic groups.
2. **Recognise** each part, and choose the Bylaw form for it:
   * **Resource:** a top-level `type equals` becomes `Resource '<type>'`; with no type condition, `Resource *`. Field names are shortened to the form `Field` resolves back to the same alias, and kept in full when the short form would be ambiguous (ADR-0008).
   * **When and Require:** the top-level conjuncts other than the type are applicability conditions, written in `When` as they are, except one, which is the violation: an `anyOf`, if there is one, or otherwise the last conjunct. Each alternative of the violation becomes a `Require`, inverted back into its compliant form. Any split compiles to the same rule, so this is a readability choice, and the proof in step 4 checks it.
   * **Statements:** each condition is matched against the forms the compiler emits. A violation `notEquals` with no guard is `Must -Be`; an `equals` with no guard is `Must -Not -Be -IfPresent`; an `equals` inside `anyOf` with `exists: false` is the strict `Must -Not -Be`; and so on through ADR-0004's table. To stay exact, candidate statements are compiled with Bylaw's own inversion, and the one that reproduces the condition is chosen.
   * **Arrays:** `count` with `where` becomes `Each` when it's the form `Each` emits, and `Count -Where` otherwise (ADR-0032).
   * **Values:** `[parameters('x')]` becomes `Param X`, recognised tag and resource group expressions become `Tag` and `ResourceGroupTag`, and other expressions `Arm`.
   * **Effect:** `[parameters('effect')]` with a declared parameter becomes `Parameter Effect ...` and `Effect (Param Effect)`. A parameter identical to the one Bylaw generates for a literal effect becomes the literal, e.g. `Effect Deny`. Effects with details become their keywords: Modify with its operations, and roles by name from the role map (ADR-0022); Append; DenyAction; Manual; AuditIfNotExists and DeployIfNotExists with their existence condition as `Require` (ADR-0030).
   * **Parameters and properties:** parameter names become PascalCase DSL names, with `JsonName` where the original wouldn't round-trip (ADR-0018). Unknown metadata goes to `Properties.Metadata`.
   * **Initiatives:** a member whose ID matches a definition converted in the same run becomes `PolicyDefinition '<name>'`; a built-in becomes `-Id <guid>`; any other ID is kept in full. Groups become `DefinitionGroup`.
3. **Write** the file in Bylaw's style: the README's layout, the hashtable form for parameters with several options (ADR-0021), and `Require` descriptions made from the condition, such as `'publicNetworkAccess is Disabled'`, because the JSON has none. A comment at the top says which file it was converted from.
4. **Prove** it: the converted file is compiled in memory and compared with the input by meaning (ADR-0041). A file that doesn't prove `Equivalent` isn't written, and is reported as `Failed` with the first difference.

Anything step 2 can't express in the language is written with the escape hatch (ADR-0040), for that condition only, so the rest of the policy stays readable. A definition fails outright only when even that can't express it, for example a resource provider mode such as `Microsoft.Kubernetes.Data`, which language version 1.0 doesn't support.

### Consequences

* Good, because every converted file is known to compile to the same rule as its input.
* Good, because the readable choices, such as the `When` and `Require` split and the descriptions, are safe to improve later: the proof catches a mistake.
* Good, because migrating a set of definitions is one command, with a status per definition.
* Bad, because the generated `Require` descriptions describe the condition, not the intent, and need a person to improve them.
* Bad, because the proof is only as strong as the comparison (ADR-0041): a pair it can't prove equivalent is reported as failed, even if it is.

### Confirmation

The round-trip tests (ADR-0041) convert every golden file and every example back to Bylaw, prove each one, and compare the converted source with the original where the original is in the style the converter writes. The ALZ coverage report (ADR-0042) runs it over the Azure Landing Zones Library.

## Pros and Cons of the Options

### Convert, then prove the result by compiling it and comparing

* Good, because correctness doesn't depend on every pattern being right.
* Bad, because it needs a comparison that understands meaning.

### Convert with fixed patterns, without checking

* Good, because it is simpler.
* Bad, because a wrong pattern, such as a missed guard, silently changes the policy, which is the worst outcome for a migration.

### Convert everything to raw conditions

* Good, because it is always exact.
* Bad, because the output isn't Bylaw in any useful sense: no checked aliases, no inversion, nothing to read.
