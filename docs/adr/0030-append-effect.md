---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# Append is a block of Add operations, like Modify

## Context and Problem Statement

`append` adds fields to a resource during a create or update request. Its `details` is an array of `{ field, value }`. With a `[*]` alias the value is added to the array; with any other alias it sets the field, and the request is denied if it already has a different value. Learn recommends `modify` for tags, and Azure recommends `modify` over `append` in general, but `append` is still used: the Azure Landing Zones Library has five Append policies. How is it written?

## Decision Drivers

* The same shape as `Modify`: operations take their field from the pipeline.
* Existing Append policies can be written in Bylaw without changing their behaviour.

## Considered Options

* An `Append` block of `Add` operations
* `Append -Field ... -Value ...` pairs as parameters
* Not supporting `append`, and pointing authors to `Modify`

## Decision Outcome

Chosen option: "An `Append` block of `Add` operations".

```powershell
Append {
    Field supportsHttpsTrafficOnly | Add $true
    Field 'networkAcls.ipRules[*]' | Add @{ value = '40.40.40.40'; action = 'Allow' }
}
```

* `Add` is the same keyword as in `Modify`, and means "add this value". Each `Add` emits one `{ "field": ..., "value": ... }`, in the order written. `AddOrReplace` and `Remove` are compile errors inside `Append`.
* The field is a `Field` or a `Tag`. A `[*]` alias is allowed, unlike in `Modify`: Learn documents it as adding the value to the array, creating the array if it doesn't exist.
* The value can be a literal, including a hashtable for an object and an array, or a `Param`, `Arm` or `ResourceGroupTag`.
* The same field in more than one `Add` is a compile error.
* Warning: a `Tag` field. Learn: "it's recommended to use the modify effect for tags instead."
* Warning: a field that no `Require` checks, as for `Modify` (ADR-0024). Append marks existing resources that match the rule as non-compliant, so the rule should check what Append adds.
* The effect is emitted as `Append`. `-Effect (Param Effect)` may allow `Append` and `Disabled`, the values the ALZ Append policies use. A literal effect gets a generated EPAC parameter with those values. Learn doesn't say whether `Audit` or `Deny` are valid on a definition with append details, so they are compile errors until measured.
* `Append` has no roles: it changes the request, not the resource.
* A hashtable value can't contain `Param` or `Arm` (BYL1020), because Learn doesn't say whether expressions nested in an object value are evaluated. A parameter of type `Object` can hold the whole value.
* The details are emitted as an array, as Azure requires. The EPAC schema says `details` is an object, so EPAC output gets the warning BYL4010 (ADR-0023). EPAC deploys it. The golden test checks the rest of the file against the schema.

### Diagnostics

* Front end: BYL1036 (`AddOrReplace` or `Remove` in `Append`), BYL1037 (`Add -Condition` in `Append`), BYL1020 (`Param` or `Arm` inside a hashtable value). As for `Modify`, BYL1013 is an empty block, BYL1027 an `Add` without a value, BYL1030 a literal `-Effect`, and BYL1031 an `Add` with no field.
* Validation: BYL3080 (`[*]` before the end of the path), BYL3081 (the same field twice), BYL3072 (an effect parameter that allows anything but `Append` and `Disabled`), and the warnings BYL3082 (a tag field) and BYL3083 (a field no `Require` checks, where a `[*]` field counts as checked by an `Each` over it).

### Consequences

* Good, because existing Append policies can move to Bylaw unchanged.
* Bad, because `Add` means slightly different things in `Modify` (set the field only if it has no value) and in `Append` (add the value, and deny on conflict). The README describes each in its own section.

### Confirmation

Unit tests cover each operation form, the errors and warnings, and the effect parameter. Golden tests cover a scalar field and a `[*]` field with an object value.

## Pros and Cons of the Options

### An `Append` block of `Add` operations

* Good, because it reads like `Modify`.
* Bad, because `Add` is shared between two effects with slightly different behaviour.

### Field and value parameters

* Good, because nothing is shared with `Modify`.
* Bad, because several fields need several pairs, which reads poorly.

### Not supporting `append`

* Good, because there is less to build.
* Bad, because existing Append policies couldn't be written in Bylaw.

## More Information

* [Append effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-append)
* Related: [ADR-0024](0024-modify-effect.md)
