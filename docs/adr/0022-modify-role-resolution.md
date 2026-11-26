---
status: accepted
date: 2026-11-26
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

* A bundled built-in role map, with its own refresh command
* A live lookup through Az at compile time
* IDs only, with no name resolution

## Decision Outcome

Chosen option: "A bundled built-in role map, with its own refresh command".

* `src/Data/roles.json` maps built-in role names to role GUIDs. It is written with the canonical writer and sorted by name. The bundled file is a starter set of common roles. The full map is generated with the refresh command, as for aliases (ADR-0008).
* `Update-BylawRoleCache` refreshes it from `Get-AzRoleDefinition`, reading built-in roles only. It is a separate command from `Update-BylawAliasCache`, because the data and the Az command behind it are different, and refreshing one shouldn't require refreshing the other.
* The map used is the first of: `Build-Bylaw -RoleCachePath`, `roleCache` in `bylaw.json`, `~/.bylaw/roles.json`, the bundled file. This is the same order as for aliases.
* `-Role` accepts one or more of:
  * a built-in role name, ignoring case, resolved through the map;
  * a GUID, emitted as `/providers/Microsoft.Authorization/roleDefinitions/<guid>`;
  * a full role definition ID starting with `/providers/Microsoft.Authorization/roleDefinitions/`, emitted unchanged.
* IDs are emitted in the order written. A role given twice, by any form, is a compile error.
* An unknown name is a compile error that suggests the closest names, and says that custom roles must be given by GUID.
* Built-in role GUIDs are the same in every Azure tenant, so the map is portable. Custom roles have to be given by GUID or full ID.
* Bylaw doesn't check that a role grants the permissions the operations need. Learn only says the role must include the operations of Contributor or Tag Contributor for the fields it changes, and the permissions of custom roles can't be known offline.

### Consequences

* Good, because builds are offline and deterministic, and role names are readable.
* Bad, because the map can go stale when Microsoft adds roles. The refresh command addresses this.

### Confirmation

Unit tests cover each form of `-Role`, duplicates, unknown names with suggestions, and the lookup order. Each role in the bundled starter set is checked against Learn's list of built-in roles.

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

## More Information

* [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)
* Related: [ADR-0024](0024-modify-effect.md)
