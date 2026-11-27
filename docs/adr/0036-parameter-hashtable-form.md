---
status: proposed
date: 2026-11-27
decision-makers: Bylaw maintainers
---

# Parameter takes its options as a hashtable after the name, as well as on one line

## Context and Problem Statement

`Parameter` has a one-line form, `Parameter Name -Type ... -Default ... -DisplayName ...`, and a hashtable form, `Parameter @{ Name = ...; ... }`, documented only as being for extras such as `Metadata` and `JsonName`. A parameter with a type, allowed values, a default, a display name and a description makes a one-line declaration well over 120 characters, and the spec bans backtick line continuation. The hashtable form fixes the length, but it moves the name into the table, so the name isn't in the same place as in the one-line form, and nothing points authors to it. How should authors write a long parameter declaration?

## Decision Drivers

* Each option on its own line, without backticks (SPEC: no backtick line continuation).
* The parameter's name in the same place in every form, so declarations line up and are easy to scan.
* No new keyword or option names: the hashtable keys are the option names.
* Existing files keep compiling.

## Considered Options

* `Parameter Name @{ ... }`: the name, then a hashtable of options, beside the existing forms
* Document the existing `Parameter @{ Name = ...; ... }` form only
* Rely on PowerShell splatting, `Parameter Name @options`

## Decision Outcome

Chosen option: "`Parameter Name @{ ... }`", because it puts one option per line and keeps the name first, as in the one-line form.

* `Parameter` takes an optional second positional argument, a hashtable with the keys `Type`, `AllowedValues`, `Default`, `DisplayName`, `Description`, `JsonName` and `Metadata`, matched ignoring case. It means the same as the named options.
* `Parameter @{ Name = ...; ... }` stays, for compatibility and for declarations built as data.
* These are BYL1015: a `Name` key in the hashtable after a name, the hashtable together with named options such as `-Type`, two hashtables, a second argument that isn't a hashtable, an unknown key, and an empty name.
* The README documents the hashtable form for any long declaration, and one example uses it.

### Consequences

* Good, because a long parameter reads like `Properties @{ }`, one aligned key per line.
* Good, because every form produces the same IR, so the passes and emitters are unchanged.
* Neutral, because there are now three spellings of one declaration. The README recommends the one-line form for short declarations and `Parameter Name @{ }` for long ones.

### Confirmation

Unit tests in `tests/Unit/Keywords/Metadata.Tests.ps1` check that the three forms give the same parameter, and each BYL1015 case. `examples/storage/secure-transfer.bylaw.ps1` uses the new form.

## Pros and Cons of the Options

### Document the existing form only

* Good, because nothing changes in the language.
* Bad, because the name moves into the table, unlike `Policy 'name' { }`, `Require 'description' { }` and the one-line form.

### Splatting

* Good, because it already works: `Parameter` is a PowerShell function.
* Bad, because the options sit in a variable away from the declaration, and a misspelled key is a PowerShell binding error, not a Bylaw diagnostic with a list of valid keys.
