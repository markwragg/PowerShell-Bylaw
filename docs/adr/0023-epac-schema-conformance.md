---
status: accepted
date: 2026-11-25
decision-makers: Bylaw maintainers
---

# Conforming to the EPAC policy definition schema

## Context and Problem Statement

The Milestone 1 definition of done says `Build-Bylaw` produces EPAC-valid JSON, and ADR-0011 says golden files are validated against the EPAC schema. The [EPAC policy definition schema](https://raw.githubusercontent.com/Azure/enterprise-azure-policy-as-code/main/Schemas/policy-definition-schema.json) (JSON Schema 2020-12, checked 2026-11-25) is stricter than Azure itself:

| EPAC schema rule | Azure |
|---|---|
| `properties` requires `displayName`, `mode`, `metadata`, `parameters`, `policyRule` | only `policyRule` is required |
| `metadata` requires `version` and `category` | optional |
| `then.effect` must be the exact string `[parameters('effect')]` | any effect, literal or expression |
| a parameter named `effect` requires `type` String, `metadata.displayName` exactly `Effect`, `allowedValues` with at least 2 unique effects, and `defaultValue` | `defaultValue` is optional, and so is `allowedValues` |
| every parameter requires `metadata.displayName` | optional |
| parameter `type` is one of String, Array, Object, Boolean, Integer, Float | `DateTime` is also valid |

How should Bylaw's EPAC emitter handle these differences?

## Decision Drivers

* Output from `-Format Epac` passes the EPAC schema, so editors and CI raise no errors.
* Authors don't write boilerplate that the compiler can generate (spec: "Generated boilerplate for effect parameters and metadata").
* No silent guesses about content that only the author knows, such as the category.
* The policy layer of the IR stays format-neutral. EPAC rules live in the EPAC emitter, so the Plain JSON emitter (Milestone 2) isn't bound by them.

## Considered Options

* Generate what can be derived, and fail the EPAC build for what can't
* Emit as written and warn where the output breaks the schema
* Make every EPAC rule part of the language, for every format

## Decision Outcome

Chosen option: "Generate what can be derived, and fail the EPAC build for what can't". The EPAC emitter checks a policy before it emits it, and reports `BYL4xxx` diagnostics with the source location.

**Generated:**

* `metadata` and `parameters` are always emitted, as `{}` when they are empty.
* A literal effect becomes an effect parameter. `Effect Deny` emits `then.effect: "[parameters('effect')]"` and this parameter:

  ```json
  "effect": {
    "type": "String",
    "metadata": {
      "displayName": "Effect",
      "description": "Enable or disable the execution of the policy"
    },
    "allowedValues": [
      "Audit",
      "Deny",
      "Disabled"
    ],
    "defaultValue": "Deny"
  }
  ```

  The allowed values are every effect supported in the language version, and the default is the literal effect, so the policy behaves as written unless an assignment overrides it. The parameter is added after the declared parameters. The description is the text Azure built-in policies use.
* A declared effect parameter (`Effect (Param Effect)`) gets `metadata.displayName` `Effect`, and the same description unless the author sets one.
* Any other parameter without a `DisplayName` gets one from its name, split into words in sentence case: `AllowedLocations` becomes `Allowed locations` and `TLSVersion` becomes `TLS version`.

**Errors:**

* `BYL4001`: `Category` is not set. There is no sensible default.
* `BYL4002`: `Version` is not set. A default of `1.0.0` would be easy, but versioning is the author's call, and silently versioning every policy `1.0.0` hides the omission.
* `BYL4003`: the effect parameter's JSON name isn't `effect`, for example because `JsonName` is set to something else.
* `BYL4004`: the effect parameter has no `Default`.
* `BYL4005`: the effect parameter has fewer than 2 distinct `AllowedValues`.
* `BYL4006`: the effect parameter has a `DisplayName` other than `Effect`.
* `BYL4007`: the effect is a literal, but a parameter with the JSON name `effect` is already declared. The author should use `Effect (Param Effect)`.
* `BYL4008`: the effect is an `Arm` expression, which the schema doesn't allow.

**Warnings:**

* `BYL4009`: a parameter of type `DateTime`. Azure accepts it but the EPAC schema doesn't list it. The policy still compiles, because it deploys.
* `BYL4010`: an `Append` policy. Azure requires its details to be an array, but the EPAC schema says `details` is an object. The policy still compiles, because it deploys (ADR-0030).

### Consequences

* Good, because every definition from `-Format Epac` passes the EPAC schema, which CI checks for the golden files.
* Good, because `Effect Deny` stays the simplest thing to write, and the output still matches EPAC's convention.
* Bad, because a literal effect is no longer fixed: an assignment can change it. Plain JSON output (Milestone 2) will emit literal effects as written.
* Bad, because `Category` and `Version` are now required for EPAC output, which ADR-0016 lists as optional.
* Neutral: the EPAC schema follows EPAC's `main` branch. A copy is pinned in `tests/Schemas/` and refreshed deliberately, as ADR-0011 says.

### Confirmation

Unit tests cover each generated element and each `BYL4xxx` code. Golden files are checked against the pinned schema with `Test-Json`.

## Pros and Cons of the Options

### Generate and fail

* Good, because the output is always schema-valid, with the least boilerplate for authors.
* Bad, because EPAC output needs two Properties keys that other formats won't need.

### Emit and warn

* Good, because it never blocks a build.
* Bad, because the definition of done (EPAC-valid output) isn't guaranteed, and warnings get ignored.

### EPAC rules in the language

* Good, because there is one set of rules.
* Bad, because EPAC's conventions would constrain the Plain JSON and Bicep formats too.

## More Information

* ADR-0011 (EPAC default output), ADR-0016 (Properties), ADR-0017 (effects), ADR-0018 (parameter casing).
* [EPAC policy definitions](https://azure.github.io/enterprise-azure-policy-as-code/policy-definitions/)
