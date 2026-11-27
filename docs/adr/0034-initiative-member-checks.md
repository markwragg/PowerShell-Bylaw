---
status: accepted
date: 2026-11-27
decision-makers: Bylaw maintainers
---

# Initiative members are checked against the emitted definitions after every file has compiled

## Context and Problem Statement

An initiative can include policies from any file in the build, but each file compiles in its own runspace and sees only itself (ADR-0014). Azure only reports a member that doesn't exist, or a parameter value it can't use, when the initiative is created or assigned. Which checks does Bylaw make, and where?

## Decision Drivers

* Every file still compiles in isolation; nothing about one file changes how another compiles (ADR-0014).
* A misspelled member or parameter fails the build, as a misspelled alias does (ADR-0008).
* Checks are made against what is actually emitted, which can differ by format: a literal effect has a generated `effect` parameter in EPAC output, and none in plain JSON (ADR-0023, ADR-0027).

## Considered Options

* A cross-file pass in `Build-Bylaw`, over plain data each file returns
* Compile initiatives last, in a runspace that loads every policy
* No cross-file checks

## Decision Outcome

Chosen option: "A cross-file pass in `Build-Bylaw`, over plain data each file returns".

### How

* Each file compiles as now, initiatives included. An initiative's own checks (ADR-0033) run in its file's runspace, and it is emitted there.
* As well as its text, each compiled policy returns its emitted parameters as plain data: name, type, whether it has a default, the default, and allowed values. It also returns its `Version`. Each initiative returns its members, with their source locations.
* After every file has compiled, `Build-Bylaw` runs the cross-file pass, then the existing all-or-nothing rule applies: if anything fails, nothing is written (ADR-0013).

### What is checked, for a member from the build

* **The policy exists** in the build, ignoring case. Otherwise it's an error that suggests the closest policy names.
* **Every passed name is a parameter of the policy,** matched ignoring case, as ARM does. Otherwise it's an error that lists the policy's parameters.
* **Every parameter without a default is passed.** Otherwise it's an error: Azure would reject the initiative.
* **Values fit the parameter:**
  * A literal must match the parameter's type and be one of its allowed values.
  * A `Param` must be an initiative parameter of the same type. Its default, if it has one, must be one of the member's allowed values, and so must each of its own allowed values. Otherwise it's an error: the assignment could pass a value the member rejects.
  * An `Arm` or `ResourceGroupTag` value isn't checked: its value is only known when the policy is evaluated.
* **`-Version` matches the policy's `Version`,** with a warning that Azure matches it against a top-level `version` Bylaw doesn't emit (BYL3129). Match: `1.*.*` matches `1.4.0` but not `2.0.0`. A pattern that doesn't match is an error, because the assignment would use a version this build doesn't produce. A member without `-Version` is fine: Azure uses the latest major version.

### For a member by `-Id`

* The ID must be a policy definition ID: `/providers/Microsoft.Authorization/policyDefinitions/<name>`, optionally after a management group or subscription scope. A policy set ID is an error, because initiatives can't contain initiatives.
* Its parameters aren't checked: Bylaw has no snapshot of built-in definitions. Like the alias snapshot (ADR-0008), one could be added later, and the checks above would then apply.

### Diagnostics

* Errors: BYL3120 (the policy isn't in the build, with the closest name), BYL3121 (a passed name that isn't a parameter), BYL3122 (a parameter without a default that isn't passed), BYL3123 (a literal of the wrong type or not allowed), BYL3124 (an initiative parameter of another type), BYL3125 (an initiative parameter whose default or allowed values the member doesn't allow), BYL3126 (`-Version` doesn't match the policy's `Version`, or the policy has none).
* Warnings: BYL3127 (the name differs from the policy's only in case: it is emitted as written), BYL3128 (an initiative parameter with no allowed values, passed to a parameter that has them), BYL3129 (`-Version` on a member from the build: Azure matches `definitionVersion` against a top-level `version`, which Bylaw doesn't emit while custom versioning is in preview, ADR-0016).
* The pass runs only when every file compiled without errors, because a policy with errors has nothing reliable to check against.
### Consequences

* Good, because the most common initiative mistakes, a misspelled member or parameter, a missing required parameter or an effect the member doesn't allow, fail the build with a source location.
* Good, because each file still compiles alone.
* Bad, because built-in members, most members in practice, are only checked for the shape of their ID.

### Confirmation

Unit tests cover each check, for members in the same file and in other files, in both formats, including a literal effect that has a generated parameter in EPAC output but not in plain JSON.

## Pros and Cons of the Options

### A cross-file pass over plain data

* Good, because isolation is kept, and the checks see exactly what is emitted.
* Bad, because files return more data than before.

### Compile initiatives in a runspace with every policy loaded

* Good, because initiatives could use the full IR of their members.
* Bad, because that runspace would see every file's state, which ADR-0014 rules out, and policies would be compiled twice.

### No cross-file checks

* Good, because nothing changes in `Build-Bylaw`.
* Bad, because initiative mistakes would only show up when deploying.

## More Information

* Related: [ADR-0013](0013-discovery-by-convention.md), [ADR-0014](0014-runspace-isolation.md), [ADR-0021](0021-parameter-usage-validation.md), [ADR-0023](0023-epac-schema-conformance.md), [ADR-0033](0033-initiatives.md)
