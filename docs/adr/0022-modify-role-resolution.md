---
status: proposed
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Resolving built-in role names for Modify -Role

## Context and Problem Statement

The `modify` effect needs `details.roleDefinitionIds`, a list of full role definition IDs such as `/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c`. Authors would rather write `Modify -Role Contributor`. How does Bylaw turn role names into IDs while still compiling offline (ADR-0007)?

## Decision Drivers

* Compiling works offline, with no Az dependency.
* Typos in role names fail the build.
* Custom roles and IDs written directly must still work.

## Considered Options

* A bundled built-in role map, refreshed alongside the alias cache
* A live lookup through Az at compile time
* IDs only, with no name resolution

## Decision Outcome

Proposed: "A bundled built-in role map, refreshed alongside the alias cache".

* `src/Data/roles.json` maps built-in role names (ignoring case) to role GUIDs. It is written with the canonical writer and sorted.
* `Update-BylawAliasCache -IncludeRoles` (or a sibling `Update-BylawRoleCache`, to be decided when this is implemented) refreshes it from `Get-AzRoleDefinition`, using the same snapshot locations as ADR-0008.
* `-Role` accepts:
  * a built-in role name, resolved through the map,
  * a GUID, wrapped as `/providers/Microsoft.Authorization/roleDefinitions/<guid>`,
  * a full role definition ID, passed through unchanged.
* An unknown name is a compile error that suggests the closest names.
* Built-in role GUIDs are the same in every Azure tenant, so the map is portable. Custom roles have to be given by GUID or full ID.

### Consequences

* Good, because builds are offline and deterministic, and role names are readable.
* Bad, because the map can go stale when Microsoft adds roles. The refresh command addresses this.

## Pros and Cons of the Options

### Bundled map

* Good, because it works offline and is validated.
* Bad, because it has to be refreshed.

### Live lookup

* Good, because it is always current.
* Bad, because it breaks offline compilation and needs credentials in CI.

### IDs only

* Good, because there is no data to maintain.
* Bad, because GUIDs are unreadable and a typo in one goes unnoticed.
