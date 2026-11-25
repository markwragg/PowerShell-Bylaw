# Pinned schemas

| File | Source | Retrieved |
|---|---|---|
| `epac-policy-definition-schema.json` | [Azure/enterprise-azure-policy-as-code `Schemas/policy-definition-schema.json`](https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json) (MIT licence) | 2026-11-25 |

The tests validate emitted EPAC files against this copy (ADR-0011, ADR-0023), so a change upstream can't break the build without warning. To refresh it, download the file again, run the tests, and update the date above. If the schema's rules have changed, update ADR-0023 too.
