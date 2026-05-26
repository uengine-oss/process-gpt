---
name: code-to-spec
description: Reverse-engineer OpenSpec main specs from existing source folders by deriving observable behavior, planning capability boundaries, and writing implementation-independent specs under openspec/specs. Use when the user invokes /code-to-spec or asks to generate specs from code.
argument-hint: "<source-folder...>"
arguments: [source_folders]
disable-model-invocation: true
license: MIT
compatibility: Requires OpenSpec project structure and access to the source folders being analyzed.
metadata:
  author: project
  version: "1.0"
---

# Code To Spec

Reverse-engineer existing source code into OpenSpec main specs. The output is not a code summary; it is a set of behavior contracts the system already appears to guarantee from the perspective of users, clients, operators, public APIs, events, persisted state, and errors.

**Direct command input**: When invoked as `/code-to-spec <source-folder...>`, use `$source_folders` as the exact list of folders to analyze. If `$source_folders` is empty, ask for one or more source folders. If any folder is missing or ambiguous, ask the user to choose instead of guessing.

**Language Rule**: Write planning documents and specs in Korean. This includes document titles, section prose, table text, checklists, Requirement names, Requirement bodies, Scenario names, and Scenario steps. Keep only contract identifiers in their original form: API paths and methods, request/response fields, event names, enum values, configuration keys, environment variables, SQL keywords, test IDs, and requirement IDs. Keep the OpenSpec structural prefixes `### Requirement:` and `#### Scenario:`, but write the names after those prefixes in Korean. Do not write general prose such as "The system SHALL..." or "When the client..." in English.

**Core Rule**: Specs MUST describe observable behavior, not implementation internals. Do not put internal function names, class names, private helper names, module paths, file paths, or line numbers in `openspec/specs/*/spec.md`.

**Feature-Sized Spec Rule**: Main specs MUST be split by feature, not by microservice or source folder. When the input is a microservice or service folder, every spec folder name MUST start with the normalized microservice/service folder name followed by `_`. If the service spans multiple business domains, use `openspec/specs/<microservice>_<domain>-<feature>/spec.md`. If the service focuses on one domain, or the service name already expresses the domain, use `openspec/specs/<microservice>_<feature>/spec.md`. All segments are lowercase kebab-case.

**Microservice Prefix And Domain Split Rule**: For code-to-spec, the microservice name plus `_` is a required spec ID prefix. Do not replace that prefix with business-domain, external-system, protocol, resource, or sub-capability names discovered inside the service. When a service spans multiple domains, add a domain discriminator after the service prefix, for example `completion_agent-memory-chat`, `completion_mcp-server-config`, and `completion_notification-push-delivery`; do not generate `agent_memory-chat`, `mcp_server-config`, or `notification_push-delivery`. When a service already names the domain or focuses on only one domain, omit the extra domain discriminator but keep the `_` separator, for example `billing_invoice-search`.

**Backend-Associated Naming Rule**: Do NOT use implementation layers such as `frontend`, `ui`, `react`, `page`, or `component` as the service prefix or domain discriminator. Main specs must represent backend-associated product/service behavior: public APIs, streaming contracts, persistence, auth, jobs, data processing, or workflows backed by repository-owned services. Frontend code is evidence for user actions and visible outcomes, not the naming boundary itself. If the input is a frontend folder, trace its API calls, routes, events, config, and service clients to the owning backend/product capability and name specs from that capability. If no backend-associated behavior can be identified, skip spec generation and record an open question instead of creating a frontend-only spec.

**Workflow Gate Rule**: Execute the workflow strictly in order. Do not write `openspec/specs` before the planning document exists and its checklist passes. If a step cannot pass, stop and report the failed gate, checked evidence, and required user decision.

## Required References

Read these before creating or changing outputs:

- `openspec/config.yaml`: repository-specific OpenSpec context and rules. Its constraints override generic advice in this skill.
- `TEMPLATES.md`: required planning and spec templates.
- Existing `openspec/specs/*/spec.md`, if any: preserve and merge existing requirements instead of overwriting them.
- Relevant OpenSpec skills when needed:
  - `../openspec-explore/SKILL.md` for investigative stance and ambiguity handling.
  - `../openspec-propose/SKILL.md` for OpenSpec artifact discipline.
  - `../openspec-sync-specs/SKILL.md` for main-spec merge behavior.

## Workflow

1. **Read rules and resolve input**
   - Read `openspec/config.yaml` and apply its `context` and `rules.specs`.
   - Read `TEMPLATES.md`.
   - Resolve each `$source_folders` entry to an existing folder.
   - Identify whether existing specs already cover any target behavior.
   - Derive a lowercase kebab-case service prefix for each source folder or microservice being analyzed.
   - If a source folder is a microservice/service folder, lock the prefix to that folder/service name and do not substitute discovered subdomain, protocol, resource, or external-system names.
   - Decide whether each service is single-domain or cross-domain before naming specs. Use `<microservice>_<domain>-<feature>` when the extra domain segment prevents unrelated capabilities from being grouped together; otherwise use `<microservice>_<feature>`.
   - If a source folder is frontend/UI code, trace it to the owning backend API, service, product workflow, or data contract before choosing the service-prefixed spec ID.
   - Step checklist:
     - [ ] `openspec/config.yaml` has been read.
     - [ ] `TEMPLATES.md` has been read.
     - [ ] Every source folder exists and is in scope.
     - [ ] Existing main specs have been checked.
     - [ ] Service prefixes have been derived from backend/product service boundaries, not implementation layers such as frontend/ui/react.
     - [ ] Microservice/service inputs use the normalized service folder name as the locked prefix.
     - [ ] Each service has been classified as single-domain or cross-domain for spec folder naming.
     - [ ] Blocking ambiguity has been resolved by evidence or user input.

2. **Explore observable behavior**
   - Inspect code broadly enough to understand user-visible and client-visible behavior.
   - Prefer public boundaries over internal call graphs: routes, commands, UI workflows, message/event contracts, jobs, persistence effects, configuration behavior, auth/permission checks, validation, error handling, and integration boundaries.
   - For frontend inputs, follow UI actions to owned backend routes, gateway paths, request/response contracts, streaming events, persistence effects, auth behavior, and service dependencies. Treat UI labels and interactions as evidence for the feature, not as the service prefix or domain discriminator.
   - Collect evidence as internal notes while analyzing, but do not copy implementation references into final specs.
   - Treat tests, examples, docs, route declarations, schemas, migrations, and UI labels as contract evidence.
   - Step checklist:
     - [ ] Public/API/UI/CLI/job boundaries have been identified where present.
     - [ ] Frontend-visible behavior has been tied to an owning backend/product contract where applicable.
     - [ ] Inputs, outputs, state changes, errors, and permissions have been noted.
     - [ ] Tests/docs/examples were checked when present.
     - [ ] Internal-only helpers were filtered out unless they expose observable behavior.
     - [ ] No domain-specific assumption was introduced unless the code exposes it as a contract.

3. **Plan feature-sized spec partitioning first**
   - Before writing specs, create `openspec/plannings/code-to-spec-<scope-slug>.md`.
   - Use the planning template in `TEMPLATES.md`.
   - Partition by capability and use case, not by package, class, component, or file.
   - Choose spec folder names in `<microservice>_<domain>-<feature>` or `<microservice>_<feature>` format. Every segment MUST be lowercase kebab-case.
   - For microservice/service inputs, keep the `<microservice>_` prefix identical to the normalized service folder name plus underscore across all planned specs from that input. A folder such as `agent-feedback-feedback-processing` is invalid for `services/agent-feedback`; use `agent-feedback_feedback-processing`.
   - If the input folder is a microservice or broad module, do NOT create one spec for the whole folder. Use the folder/service as the required prefix and create separate feature specs for each observable public workflow, API resource behavior, CLI command group, job contract, event contract, or externally visible lifecycle.
   - If a service crosses several business areas, protocols, or owned resources, keep the service name as `<microservice>` and express the business area as `<domain>`. Example: `services/completion` yields `completion_agent-memory-chat`, `completion_mcp-server-config`, and `completion_notification-push-delivery`.
   - If a service focuses on one business domain, or the service name already clearly represents that domain, do not repeat the domain after the underscore, but keep the underscore between service and feature. Example: `services/billing` yields `billing_invoice-search`.
   - If the input folder is frontend/UI, do NOT create `frontend_*`, `frontend-*`, `ui_*`, `ui-*`, `react_*`, or `react-*` specs. Map each UI workflow to the backend-associated service and feature it exercises, such as `text2sql-streaming` or `understanding-graph-visualization`.
   - Do not create specs for purely frontend-only display, component, theme, or local UI preferences unless they are explicitly tied to a backend-owned product contract; record them as skipped or open questions instead.
   - For each proposed spec folder, document:
     - service prefix, optional domain discriminator, and feature,
     - feature purpose,
     - included use cases,
     - observable contracts to capture,
     - why this is an appropriate one-E2E-suite boundary,
     - excluded implementation details,
     - behaviors intentionally split into other feature specs,
     - source evidence categories,
     - open questions or risks.
   - Step checklist:
     - [ ] Planning file exists under `openspec/plannings/`.
     - [ ] Spec folders use `<microservice>_<domain>-<feature>` for cross-domain services or `<microservice>_<feature>` for single-domain/domain-expressive services.
     - [ ] For microservice/service inputs, every planned spec from that input starts with the same locked service-name prefix.
     - [ ] Spec service prefixes and domain discriminators are backend/product capability names, not frontend/ui/react/page/component names.
     - [ ] No planned spec summarizes an entire microservice, package, controller layer, route inventory, or source folder.
     - [ ] No planned spec is frontend-only; each planned spec has an owning backend/product contract or a documented skip reason.
     - [ ] Every planned spec is feature-sized and can naturally map to one E2E suite.
     - [ ] Every source folder has at least one planned capability or an explicit exclusion reason.
     - [ ] Cross-cutting behavior is assigned to the smallest appropriate capability.
     - [ ] Planning avoids internal function/class/module summaries.

4. **Derive main specs incrementally**
   - For each planned spec folder, create or update `openspec/specs/<spec-id>/spec.md`, where `<spec-id>` follows the service-prefixed naming rule.
   - Use the main spec template in `TEMPLATES.md`.
   - Main specs use `## Purpose` and `## Requirements`; do not use delta sections such as `ADDED Requirements`.
   - Each Requirement title must describe a user/client/operator capability.
   - Each Requirement title and body MUST be written in Korean. Use SHALL/MUST only inside Korean sentences when needed.
   - Each Scenario title and step MUST be written in Korean. Prefer Korean `GIVEN`/`WHEN`/`THEN` style or Korean prose with exact public API fields/events only when they are part of the contract.
   - When UI behavior is involved, write it as the user-facing surface of a backend-associated feature. Do not make the spec about React state, components, pages, local-only preferences, or frontend implementation details.
   - Merge with existing specs intelligently:
     - preserve unrelated requirements,
     - update overlapping requirements instead of duplicating them,
     - add scenarios when behavior is already covered by a requirement,
     - keep the operation idempotent.
   - Step checklist:
     - [ ] Each planned spec folder has a corresponding `spec.md` or a documented skip reason.
     - [ ] Requirements are implementation-independent behavior contracts.
     - [ ] Requirement titles, Requirement bodies, Scenario titles, and Scenario steps are written in Korean except exact contract identifiers.
     - [ ] Scenarios are externally verifiable.
     - [ ] Existing specs were preserved and merged, not blindly overwritten.
     - [ ] Public identifiers are exact where needed.
     - [ ] Each created or updated spec remains scoped to a single feature-sized E2E boundary.
     - [ ] Each created or updated spec is backed by a repository-owned backend/product contract, not frontend-only behavior.

5. **Quality review and validation**
   - Re-read each created or updated spec as if it were used to implement the system from scratch.
   - Remove code-inventory language such as "function", "class", "module", "file", "line", "helper", "calls", "uses", unless it is a public contract term.
   - Check that every planned capability has useful requirements and scenarios rather than low-level implementation summaries.
   - Check that no `spec.md` has drifted into a service-wide inventory. If a spec mixes unrelated workflows, split it into additional service-prefixed feature specs before validation.
   - Check that specs generated from one microservice/service folder all retain the locked service-name prefix followed by `_`. If any spec replaces that prefix with a discovered subdomain, protocol, resource, or external-system name, or uses `<microservice>-<feature>` without the required underscore, rename/replan it before validation.
   - Check that cross-domain services use `<microservice>_<domain>-<feature>` and single-domain/domain-expressive services use `<microservice>_<feature>` without redundant domain repetition.
   - Check that no spec folder starts with `frontend_`, `frontend-`, `ui_`, `ui-`, `react_`, `react-`, `page_`, `page-`, `component_`, or `component-`. Rename/replan those specs around the owning backend/product capability before writing final specs.
   - Run OpenSpec validation if the CLI is available, preferably:
     ```bash
     openspec validate --strict
     ```
     If that command is not supported, run the closest repository-supported OpenSpec validation command and report it.
   - Step checklist:
     - [ ] Specs contain no internal function/class/module/file/line references.
     - [ ] Specs do not contain English prose in Requirement/Scenario content except exact identifiers such as API paths, fields, event names, enum values, and SQL keywords.
     - [ ] Requirements can be tested from outside the implementation boundary.
     - [ ] Scenario outcomes are observable.
     - [ ] Planning and specs agree on folder names and capability scope.
     - [ ] Spec folder names follow the service-prefixed naming rule and each spec is one-feature/one-E2E sized.
     - [ ] Specs generated from microservice/service folders use the service-name prefix, not discovered subdomain or resource names.
     - [ ] Redundant names such as `<microservice>_<same-domain>-<feature>` are avoided when the service name already expresses the domain, while preserving the required `<microservice>_` prefix.
     - [ ] Spec service prefixes and domain discriminators are backend-associated product/service terms, not UI implementation layers.
     - [ ] OpenSpec validation passed or the blocking validation issue is reported.

6. **Report completion**
   - Summarize created or updated planning and spec paths.
   - List the capability folders and the main behavior areas captured.
   - Report validation commands and outcomes.
   - Explicitly call out skipped folders, open questions, or residual risks.

## Partitioning Guidance

Prefer capability boundaries such as:

- A user workflow or screen-level outcome.
- A public API resource or cohesive group of endpoints.
- A CLI command group or external protocol.
- An ingestion, transformation, or export contract.
- A security, permission, validation, caching, or lifecycle behavior that is externally visible.

Avoid partitions based on:

- One spec per source folder, package, class, component, or helper.
- One spec per microservice when that microservice exposes multiple independent features.
- Specs whose service prefix or domain discriminator is only an implementation layer such as frontend, ui, react, page, component, screen, or view.
- Frontend-only behavior that cannot be tied to a backend-owned product contract.
- Framework layers such as controllers/services/repositories unless that layer is itself the public contract.
- Domain keyword matching that would not generalize to another service or feature boundary.
- Internal algorithm steps that users or clients cannot observe.

## Spec Folder Naming

Use one of these exact formats for new main specs:

```text
openspec/specs/<microservice>_<domain>-<feature>/spec.md
openspec/specs/<microservice>_<feature>/spec.md
```

Rules:

- `<microservice>` is the stable backend service or microservice folder name in lowercase kebab-case.
- `<domain>` is the business domain discriminator used only when the microservice spans multiple domains.
- `<feature>` is one observable feature or cohesive workflow in lowercase kebab-case.
- Use `<microservice>_<domain>-<feature>` for cross-domain services so the service boundary and domain discriminator are both visible.
- Use `<microservice>_<feature>` for single-domain services or when the microservice name already reveals the domain.
- Preserve the same spec ID as the default E2E suite slug for traceability.
- Examples: `billing_invoice-search`, `billing_payment-retry`, `auth_password-reset`.
- Example for a cross-domain service: `services/completion` should produce `completion_agent-memory-chat`, `completion_mcp-server-config`, and `completion_notification-push-delivery`, not `agent_memory-chat`, `mcp_server-config`, or `notification_push-delivery`.
- Avoid redundant domain duplication. If `services/billing` already represents the billing domain, prefer `billing_invoice-search` over `billing_billing-invoice-search`.
- Do not use implementation-layer service prefixes or domain discriminators such as `frontend`, `ui`, `react`, `page`, or `component`. For example, prefer `text2sql-streaming` over `frontend_text2sql-react`, and `understanding-graph-visualization` over `frontend_understanding-graph`.

## Spec Writing Guardrails

- Write from the perspective of "the system", "user", "client", "operator", or named public actor.
- Use implementation-neutral verbs: accepts, validates, returns, persists, emits, rejects, displays, records, resumes, cancels, retries.
- Write those perspectives and verbs in Korean in the final spec. For example, use "시스템은 ... SHALL ..." or "클라이언트가 ... 요청하면 ..." rather than English prose.
- Keep public identifiers exact when needed, but do not surround each requirement with source-code traceability notes.
- If a behavior is inferred but not certain, capture it as an open question in the planning file instead of pretending it is a requirement.
- If the code contains dead, unreachable, or test-only behavior, do not create product specs for it unless tests/docs show it is a supported contract.

## Gate Failure Reporting

When any step checklist cannot pass, stop and report:

- The current step number and name.
- The checklist item that failed.
- The repository evidence already checked.
- Why continuing would risk creating misleading specs.
- The specific user decision, missing input, or repository fix needed before continuing.
