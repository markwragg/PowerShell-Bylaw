---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Compile-time validation of parameter declarations and usage

## Context and Problem Statement

Azure accepts definitions whose parameter usage is wrong, for example an `Array` parameter used with `equals`, or a `String` parameter used with `in`. The mistake only shows up at evaluation time, as an error or a policy that never matches. Bylaw knows each parameter's type and every place it is used, so it can catch many of these mistakes. How strict should it be?

## Decision Drivers

* Catch definite mistakes at compile time.
* Avoid false positives that push authors towards `Arm`.

## Considered Options

* Errors for definite mismatches, warnings for likely mistakes
* Warnings only
* No validation beyond checking that the parameter exists

## Decision Outcome

Chosen option: "Errors for definite mismatches, warnings for likely mistakes".

**Errors:**

* `Param X` where `X` is not declared.
* An `Array` parameter used with an operator that takes a single value: `-Be`, `-BeLike`, `-Match`, `-MatchCase`, `-ContainText`, `-ContainKey`, or the comparison operators.
* A non-`Array` parameter used with `-BeIn`.
* A `Boolean` or `Object` parameter used with `-BeLike`, `-Match`, `-MatchCase` or `-ContainText`.
* A comparison operator used with a parameter that isn't `Integer`, `Float`, `String` or `DateTime`.
* A `Default` that doesn't match the declared `Type`, or isn't in `AllowedValues`.
* `AllowedValues` whose items don't match the declared `Type`.
* Effect parameter rules (ADR-0017).

**Warnings:**

* A parameter that is declared but never used.
* A `String` parameter with no `AllowedValues` that is used as an effect. This is already an error under ADR-0017, so it is listed here only for completeness.

Parameter types follow Azure: `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float`, `DateTime`. When `Type` isn't given, every `Parameter` form infers it from `Default` and `AllowedValues`. If inference is ambiguous, the build fails and asks for an explicit `-Type`.

### Declaration forms

A parameter can be declared in three forms, which all give the same parameter:

```powershell
Parameter Sku -Type String -AllowedValues a, b -Default a

Parameter Sku @{
    Type          = 'String'
    AllowedValues = 'a', 'b'
    Default       = 'a'
}

Parameter @{ Name = 'Sku'; Type = 'String'; AllowedValues = 'a', 'b'; Default = 'a' }
```

* The one-line form suits a short declaration. A long one would need backtick line continuation, which Bylaw files don't use, so it goes in a hashtable after the name, one option per line. That keeps the name first, as in the one-line form and in `Policy 'name' { }`.
* The hashtable keys are the option names `Type`, `AllowedValues`, `Default`, `DisplayName`, `Description`, `JsonName` and `Metadata`, matched ignoring case. The form with `Name` inside the hashtable also suits declarations built as data.
* These are BYL1015: an unknown key, a hashtable together with named options such as `-Type`, a `Name` key in a hashtable after a name, two hashtables, a second argument that isn't a hashtable, and a missing or empty name.
* Splatting (`Parameter Sku @options`) also works, because `Parameter` is a PowerShell function. It isn't the documented form, because the options sit away from the declaration, and a misspelled key is a PowerShell binding error, not a Bylaw diagnostic that lists the valid keys.

### Consequences

* Good, because the most common parameter bugs become build errors.
* Bad, because `Arm` usage can't be checked. Parameters referenced only inside `Arm` count as used, and are not validated.

## Pros and Cons of the Options

### Errors and warnings

* Good, because it gives the best defect detection.
* Bad, because the rule set has to be maintained.

### Warnings only

* Good, because it never blocks a build.
* Bad, because warnings get ignored in CI.

### Existence only

* Good, because it is trivial.
* Bad, because it misses the bugs that matter.
