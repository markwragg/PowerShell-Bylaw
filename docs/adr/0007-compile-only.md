---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Bylaw compiles policy definitions and never deploys them

## Context and Problem Statement

Should Bylaw deploy the policies it compiles to Azure?

## Considered Options

* Compile only. EPAC, Bicep or Terraform handle deployment.
* Compile and deploy

## Decision Outcome

Chosen option: "Compile only", because mature deployment tools already exist, and EPAC in particular manages assignments, exemptions and drift. Deploying would mean handling credentials, environments and state, all of which are outside Bylaw's purpose.

* No command in Bylaw changes Azure resources.
* The only command that talks to Azure is `Update-BylawAliasCache`, which only reads alias metadata.
* Compiling has no dependency on Az modules and works offline.

### Consequences

* Good, because the scope stays small, there are no credentials to handle, and Bylaw works in any CI pipeline.
* Bad, because users need a second tool to deploy. The README shows the EPAC workflow.

### Confirmation

Tests run with Az modules unavailable. A test checks that only `Update-BylawAliasCache` references Az commands.

## More Information

Developer verification scripts in `build/` (for example the missing-field verification in ADR-0004) may deploy to a sandbox subscription. They are not part of the module and are never shipped.
