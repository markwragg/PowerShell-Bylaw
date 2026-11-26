---
status: accepted
date: 2026-11-26
decision-makers: Bylaw maintainers
---

# DeployIfNotExists takes its template from a JSON file or a hashtable, with checked parameters

## Context and Problem Statement

`deployIfNotExists` needs `details.deployment`: "the full template deployment as it would be passed to the `Microsoft.Resources/deployments` PUT API". That is an ARM template, the values passed to its parameters, and for subscription-level deployments a `location`. Templates are often hundreds of lines. In the Azure Landing Zones Library every deployment uses `incremental` mode. Template parameters take their values from `[parameters(...)]` 245 times, from `[field(...)]` 138 times, and are literal only twice. How does an author supply the template and its parameters?

## Decision Drivers

* Templates are long and are often written and tested on their own, so they should be able to live in their own files.
* The values passed to template parameters are where policy and template meet, and mistakes there only show at remediation time.
* Deterministic output (ADR-0009).

## Considered Options

* A `Deployment` keyword inside the `DeployIfNotExists` block, taking a JSON file or a hashtable
* Template options on `DeployIfNotExists` itself
* Compiling Bicep with the Bicep CLI

## Decision Outcome

Chosen option: "A `Deployment` keyword inside the `DeployIfNotExists` block, taking a JSON file or a hashtable".

```powershell
DeployIfNotExists -Type 'Microsoft.Sql/servers/databases/transparentDataEncryption' -Name current -Role 'SQL DB Contributor' {

    Require 'Transparent data encryption is enabled' {
        Field status | Must -Be 'Enabled'
    }

    Deployment -TemplateFile ./templates/sql-tde.json -Parameters @{
        fullDbName = Arm "[field('fullName')]"
    }
}
```

* `Deployment` is required in `DeployIfNotExists`, at most once, and not allowed anywhere else.
* `-TemplateFile` is a JSON file, relative to the `.bylaw.ps1` file's folder. `-Template` is a hashtable (ordered, to keep its key order). Exactly one of the two is required. The template is emitted through the canonical writer (ADR-0009): key order as in the file or hashtable, Bylaw's formatting.
* `-Parameters` maps template parameter names to values. Each value is emitted as `{ "value": ... }`. A value can be a literal, `Param`, `Arm` or `ResourceGroupTag`. Policy parameters used here count as used (ADR-0021).
* The deployment mode is always `incremental`, the only mode Learn's examples and ALZ use. It isn't configurable.
* `-Scope ResourceGroup` or `Subscription` emits `details.deploymentScope`, omitted when not set (Azure's default is `ResourceGroup`). `-Location` emits `deployment.location`. Learn: "A *location* property must be specified in the *Deployment* when using subscription level deployments", so `-Scope Subscription` without `-Location` is a compile error.
* A `.bicep` file is a compile error saying Bicep isn't supported yet. Compiling Bicep needs the Bicep CLI, and the CLI's output changes between versions, which would break deterministic output.

### Checks

* The template file exists and is valid JSON, and the template is an object with a `resources` array.
* Every name in `-Parameters` is a parameter of the template.
* Every template parameter without a `defaultValue` is given in `-Parameters`.
* Expressions inside the template aren't checked. Learn: "All functions inside the `deployment` property are evaluated as components of the template, not the policy", except the parameter values.
* Template parameter names are matched ignoring case, as ARM does.

### Details

* `-Parameters` keeps the order of an `[ordered]` hashtable. A plain hashtable is sorted, as the JSON writer sorts one (ADR-0009), because its own order changes from one process to the next.
* `-Template` can't contain `Param` or `Arm`: it is an ARM template, evaluated by the deployment. Policy values go in through `-Parameters`.
* The emitted `details` follow the AuditIfNotExists details (ADR-0030) with `roleDefinitionIds`, `deploymentScope` and `deployment` after them: `deployment` is `{ location?, properties: { mode, template, parameters? } }`.
* A template file is an input of the build. `Build-Bylaw` never reports it as stale output (BYL5030), even when it is inside `-OutputPath`.

### Diagnostics

* Front end: BYL1032 (no `-Role`), BYL1043 (no block, or no `Deployment` in it), BYL1044 (neither or both of `-TemplateFile` and `-Template`), BYL1045 (a template file that is missing, isn't JSON or is Bicep; a template without a `resources` array; `Param` or `Arm` in `-Template`), BYL1040 (an invalid `-Scope`), BYL1039 (an invalid `-Location`), BYL1046 (`-Scope Subscription` without `-Location`). `Deployment` outside `DeployIfNotExists` is BYL1002, and a second one BYL1004.
* Validation: BYL3093 (a value passed to a parameter the template doesn't have), BYL3094 (a required template parameter that isn't passed), BYL3060 and BYL3061 for roles (ADR-0022), BYL3020 for an undeclared policy parameter.

### Consequences

* Good, because templates can be authored and linted as ordinary ARM templates, and the policy only says what it passes to them.
* Good, because a misspelled or missing template parameter fails the build instead of the remediation task.
* Bad, because a template file is a second input to a policy. Editing it changes the policy's output, which is what an author would expect.

### Confirmation

Unit tests cover the file and hashtable forms, each check, `-Scope` with and without `-Location`, and parameter values of each kind. A golden test uses a template file.

## Pros and Cons of the Options

### A `Deployment` keyword

* Good, because the deployment is visually separate from the existence condition, and its options are grouped.
* Bad, because there is one more keyword.

### Options on `DeployIfNotExists`

* Good, because there is no extra keyword.
* Bad, because the keyword would have a dozen parameters mixing the related resource, the roles and the deployment.

### Bicep

* Good, because many authors write Bicep rather than JSON.
* Bad, because it needs the Bicep CLI at build time, and its output isn't stable across versions. It can be added later as another `-TemplateFile` type.

## More Information

* [DeployIfNotExists effect](https://learn.microsoft.com/azure/governance/policy/concepts/effect-deploy-if-not-exists)
* Related: [ADR-0009](0009-deterministic-output.md), [ADR-0021](0021-parameter-usage-validation.md), [ADR-0030](0030-if-not-exists-effects.md)
