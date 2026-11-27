# Change Log

A `## !Deploy` heading publishes the changes under it to the PowerShell Gallery when they reach `main`, and the build replaces it with the version and date. `## !Deploy 0.2.0` or `## !Deploy 0.2.0-beta` sets the version; without one, the build takes the next patch after the newest published version. See [ADR-0036](docs/adr/0036-release-process.md).

## !Deploy 0.1.0-alpha

* First preview release, to make Bylaw available while the language settles. Expect changes before 1.0.
* `Policy` compiles to Azure Policy definitions: `Properties`, `Parameter`, `Resource`, `When`, `Require`, `Each`, `Field`, `Tag`, `Must` with every Azure Policy operator, `-Not`, `-IfPresent` and `-Strict`, `AnyOf` and `AllOf`, value conditions, `Count` and `Current`.
* Every effect: `Audit`, `Deny`, `Disabled`, `Modify`, `Append`, `DenyAction`, `Manual`, `AuditIfNotExists` and `DeployIfNotExists`.
* `Initiative` compiles to policy set definitions, with `PolicyDefinition` and `DefinitionGroup`, and the build checks each member against the policy it includes.
* `Build-Bylaw` writes EPAC definitions by default, or plain JSON with `-Format PlainJson`, and checks aliases against a bundled snapshot that `Update-BylawAliasCache` refreshes.
