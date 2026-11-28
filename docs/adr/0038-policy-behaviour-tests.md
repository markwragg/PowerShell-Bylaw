---
status: proposed
date: 2026-11-28
decision-makers: Bylaw maintainers
---

# Policies are tested against example resources with a local evaluator

## Context and Problem Statement

`Build-Bylaw` checks that a policy is valid: aliases exist, operators and parameters fit, and Azure's limits hold. It can't check that a policy means what its author intended. A policy that compiles to exactly what was written passes every check, even when what was written is wrong. For example, an NSG policy whose `AnyOf` held an `AllOf` of "no management port" and "no internet source" denied every internet rule on any port, and every management-port rule from any source, when the intent was rules that are both.

Today the only ways to test behaviour are snapshot tests, which catch changes but not mistakes, and deploying to a sandbox subscription, which is slow and needs Azure access (README, Testing policies). Pester users expect to write `It 'denies SSH from the internet'` with an example resource and run it locally. How can a policy be tested against example resources without Azure?

## Decision Drivers

* Tests read like the rest of Bylaw: Pester, with example resources and plain assertions.
* No Azure connection, no deployment and no cost, so tests run on every change.
* The evaluator gives the answer Azure would, or says it can't: a wrong "compliant" is worse than no answer.
* Its agreement with Azure is checked against Azure, as the missing-field behaviour was (ADR-0004).

## Considered Options

* A local evaluator in Bylaw, with Pester assertions
* Sandbox tests only, with helper commands to deploy, scan and clean up
* An external policy engine

## Decision Outcome

Chosen option: "A local evaluator in Bylaw, with Pester assertions", because it is the only option that runs on every change and reads like a Pester test. Sandbox tests stay the final proof, and verify the evaluator itself.

### Writing a test

```powershell
Describe 'nsg-inbound-ports-deny' {
    BeforeAll {
        $policy = Build-Bylaw ./policies/nsg-inbound-ports-deny.bylaw.ps1 -PassThru
    }

    It 'denies SSH from the internet' {
        $nsg = @{
            type       = 'Microsoft.Network/networkSecurityGroups'
            name       = 'nsg-test'
            properties = @{
                securityRules = @(
                    @{ properties = @{ direction = 'Inbound'; access = 'Allow'; sourceAddressPrefix = 'Internet'; destinationPortRange = '22' } }
                )
            }
        }
        $nsg | Should -ViolatePolicy $policy
    }

    It 'allows SSH from the corporate network' {
        $nsg.properties.securityRules[0].properties.sourceAddressPrefix = '10.0.0.0/8'
        $nsg | Should -BeCompliantWith $policy
    }
}
```

* An example resource is a hashtable or JSON in the shape Azure Resource Manager returns: `type`, `name`, `location`, `tags`, `kind` and `properties`. That's what `Get-AzResource -ExpandProperties` and the portal's JSON view show, so a real resource can be copied into a test.
* **`Test-BylawPolicy -Policy <result or JSON> -Resource <resource> [-Parameters @{...}]`** evaluates one resource and returns whether the policy applies to it, whether it is compliant, and a trace: each condition with the value it read and its result, so a failing test shows why. `-Parameters` gives assignment values; otherwise each parameter's default is used.
* **`Should -BeCompliantWith`** and **`Should -ViolatePolicy`** are registered with `Add-ShouldOperator` when Pester is loaded, and show the trace on failure. **`Should -NotApplyTo`** checks the type condition and `When`.

### What the evaluator covers first

* The `if` condition of policies built by Bylaw, or of any policy JSON: `allOf`, `anyOf`, `not`, every field operator, value conditions, `count` over fields and values with `where` and `current()`, and `[*]` fields, with Azure's documented and verified behaviour for missing fields, case and types.
* Reserved fields: `name`, `fullName`, `type`, `location`, `kind`, `id`, `tags`, `identity.*` and `extendedLocation.*`.
* ARM expressions: `parameters()`, `field()`, `current()`, `concat()`, `length()`, `empty()`, `equals()`, `not()`, `and()`, `or()`, `if()`, `toLower()` and `toUpper()`, and `resourceGroup()` and `subscription()` from optional `-ResourceGroup` and `-Subscription` hashtables. Anything else makes the result **inconclusive**, with the expression in the trace, never a guess.
* The result for the effect: Audit and Deny report compliant or not; Disabled reports that the policy doesn't apply. For Modify and Append, the result is whether remediation would be triggered; the operations aren't applied. AuditIfNotExists and DeployIfNotExists need the related resources too, so `-Related` takes them, and the existence condition is evaluated against each.

### Alias paths

Reading a field from a resource needs each alias's path in the resource JSON, such as `properties.minimumTlsVersion` for `Microsoft.Storage/storageAccounts/minimumTlsVersion`. The alias snapshot stores alias names and flags, not paths. `Update-BylawAliasCache` will also store each alias's default path from `Get-AzPolicyAlias`, in snapshot schema version 2, and the bundled snapshot will be regenerated. A path that differs by API version uses the default path, as Azure does for resources without an explicit version. An alias with no path in the snapshot makes the result inconclusive.

### Keeping it honest

* A conformance suite of example resources and expected results, one case per operator, missing-field case, count form and expression, runs with the unit tests.
* A sandbox script, like `build/verify-missing-field`, deploys the same cases to Azure, assigns the policies with Audit, and records Azure's compliance results. The suite's expected results come from that run, not from reading the documentation, and are re-run when the evaluator changes.

### Consequences

* Good, because policy authors can test behaviour on every change, in the Pester style Bylaw already uses.
* Good, because a failing test shows which condition gave which result.
* Good, because the evaluator works on any policy JSON, so it can also test policies not written in Bylaw, such as built-ins and the Azure Landing Zones Library.
* Bad, because the evaluator is a second implementation of Azure's semantics, which can drift from Azure. The sandbox conformance runs and "inconclusive" for anything unsupported limit the risk, but don't remove it.
* Bad, because the alias snapshot grows with the paths, and needs a schema change.

### Confirmation

The conformance suite passes, and its expected results match a recorded sandbox run. The README's Testing policies section is updated with behaviour tests.

## Pros and Cons of the Options

### A local evaluator in Bylaw, with Pester assertions

* Good, because tests are fast, free and run anywhere.
* Bad, because its correctness depends on matching Azure, which needs its own verification.

### Sandbox tests only, with helper commands to deploy, scan and clean up

* Good, because Azure is the real evaluator, so there's nothing to drift.
* Bad, because a compliance scan takes minutes, needs a subscription and credentials, and can't run on every change or in a fork's pull request.

### An external policy engine

* Good, because someone else maintains the semantics.
* Bad, because the nearest candidate, PSRule for Azure, converts policy assignments into its own rules in a preview feature, so it would need assignments rather than definitions, cover what its converter supports, and add a dependency whose results Bylaw can't explain in a trace. This should be checked again before work starts.

## Later

* Applying Modify and Append operations, to test the remediated resource against the rule.
* Generating example resources from a policy's conditions, to cover each branch.
