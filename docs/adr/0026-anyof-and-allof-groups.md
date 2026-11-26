---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# AnyOf and AllOf groups let a requirement have alternatives

## Context and Problem Statement

Every `Must` in a `Require` or `Each` has to hold (ADR-0003). Some requirements have alternatives. For example, a network security group rule is acceptable if it is outbound, *or* it denies traffic, *or* its source isn't the internet. Without a way to write "any of these", the policy "no inbound rule allows traffic from the internet" can't be written. How should alternatives be expressed?

## Decision Drivers

* Authors still describe the compliant state. The compiler still does the inversion (ADR-0002).
* The missing-field rules (ADR-0004) keep working inside the new groups.
* Keep the keyword count small.

## Considered Options

* `AnyOf { }` and `AllOf { }` group keywords
* An `-Or` switch on `Must` that joins it to the previous statement
* Multiple `Require` blocks with an `-Any` switch

## Decision Outcome

Chosen option: "`AnyOf { }` and `AllOf { }` group keywords", because nesting groups covers any combination and the names match Azure's own.

```powershell
Require 'No inbound rule allows traffic from the internet' {
    Each securityRules[*] {
        AnyOf {
            Field direction | Must -Not -Be 'Inbound'
            Field access | Must -Not -Be 'Allow'
            Field sourceAddressPrefix | Must -Not -BeIn '*', 'Internet'
        }
    }
}
```

A rule is compliant if any of the three holds. The compiler inverts the group with De Morgan's law: an element violates the requirement when all three are false. That gives `count` of `securityRules[*]` `where` `allOf[direction equals Inbound, access equals Allow, sourceAddressPrefix in ['*', 'Internet']]`, `greater` 0.

* `AnyOf` holds when at least one statement or group inside it holds.
* `AllOf` holds when all of them do. It is only needed inside `AnyOf`, because statements combine with AND everywhere else. `AllOf` anywhere else is a compile error, so it isn't used out of habit.
* Groups can contain `Must` statements, `Each`, and other groups.
* Groups are allowed in `Require`, inside `Each`, and in `When`. In `When`, they are emitted as written.
* An empty group is a compile error. A group with one child is allowed, and flattening removes it.
* Each `Must` keeps its own missing-field handling. A strict `Must` inside `AnyOf` holds only if its field is present and the condition holds.

### Consequences

* Good, because any combination of conditions can be written.
* Good, because the compiler already inverts and flattens nested groups. Only the front-end keywords are new.
* Bad, because deep nesting is hard to read. Authors are encouraged to split requirements into separate `Require` blocks where they can.

### Confirmation

* Unit tests cover the keywords, the errors, and inversion with strict and lenient fields.
* A golden test covers the network security group example, and `AnyOf` in `When` and at the top level of `Require`.

## Pros and Cons of the Options

### Group keywords

* Good, because they nest and cover every case.
* Bad, because they add two keywords.

### An `-Or` switch

* Good, because it is short for two alternatives.
* Bad, because the precedence of AND and OR becomes implicit and easy to get wrong.

### `Require -Any`

* Good, because it adds no keyword.
* Bad, because it only works at the top level, not inside `Each`, where the network security group case needs it.
