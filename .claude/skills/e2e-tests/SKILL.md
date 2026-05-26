---
name: e2e-tests
description: Design, implement, and maintain spec-driven Playwright E2E tests from OpenSpec spec.md files. Use when creating or extending E2E coverage matrices, scenario documents, Playwright specs, deterministic API stubs, Docker test environments, screenshots, and stable execution reports.
argument-hint: "<spec-name>"
arguments: [spec_name]
disable-model-invocation: true
license: MIT
compatibility: Requires Docker Compose and Playwright. E2E suites must boot their required services through the root docker-compose.e2e.yml before Playwright tests are written or run.
metadata:
  author: project
  version: "1.1"
---

# Spec-Driven E2E Tests

Create deterministic, incrementally maintainable E2E coverage from OpenSpec requirements.

**Input**: One or more `spec.md` files, related app/backend files, environment hints, and optional existing tests.

**Direct command input**: When invoked as `/e2e-tests <spec-name>`, use `$spec_name` as the exact OpenSpec folder name. Project feature specs MUST use the service-prefixed OpenSpec ID format: `<microservice>_<domain>-<feature>` for cross-domain services or `<microservice>_<feature>` for single-domain/domain-expressive services (for example `completion_agent-memory-chat` or `billing_invoice-search`). If `$spec_name` is empty, ask for the spec folder name. Find `openspec/specs/<spec-name>/spec.md`, read it and related artifacts, then run this workflow from that evidence. If the folder is missing or ambiguous, ask the user to choose instead of guessing.

**Feature Traceability Rule**: Preserve the OpenSpec spec folder name as the default E2E suite slug. For `openspec/specs/completion_agent-memory-chat/spec.md`, use suite slug `completion_agent-memory-chat`; for `openspec/specs/billing_invoice-search/spec.md`, use suite slug `billing_invoice-search`. Do not rewrite underscores or hyphens because they preserve the service/domain/feature boundary across scenario documents, test paths, results, screenshots, and later DOCX manuals.

**Spec-Local Output Rule**: E2E outputs MUST be colocated with the source spec. For `openspec/specs/<spec-name>/spec.md`, create or update `openspec/specs/<spec-name>/e2e/` and keep scenario documents, coverage matrices, seed/stub files, Playwright test scripts, suite-specific setup/config, execution summaries, result JSON/HTML, screenshots, traces, and helper scripts under that folder. Do not create suite outputs outside that folder. The repository root `docker-compose.e2e.yml` may remain the shared Docker entrypoint, but suite-specific files belong under the spec-local `e2e/` folder.

**Microservice Prefix Consistency Rule**: If E2E evidence or related source paths show that a spec was generated from a specific microservice/service folder, the spec ID must start with that service name followed by `_`. For example, specs covering `services/completion` should use suite slugs such as `completion_agent-memory-chat`, `completion_mcp-server-config`, or `completion_notification-push-delivery`. If the source spec replaces the service prefix with a discovered subdomain or resource name, such as `agent_memory-chat`, `mcp_server-config`, or `notification_push-delivery`, or if it drops the underscore boundary, such as `agent-feedback-feedback-processing` for `services/agent-feedback`, stop and ask for the OpenSpec spec to be regenerated or renamed before creating E2E outputs.

**Backend-Associated Spec Rule**: Only create E2E suites for specs tied to repository-owned backend/product behavior. The service prefix or domain discriminator MUST NOT be an implementation layer such as `frontend`, `ui`, `react`, `page`, or `component`. If a spec is named like `frontend_*`, `frontend-*`, or only describes frontend-local UI behavior, stop before writing E2E outputs and report that the spec should be regenerated around the owning backend/product capability. Frontend UI remains required as the user interaction surface, but it is not the domain under test.

**Core Rule**: Do not let E2E success depend on external APIs, long-running jobs, or large production datasets. Use fixed fixtures and browser/API stubs for nondeterministic behavior.

**Docker-First Rule**: Assume Docker is mandatory. Before writing or changing Playwright specs, check whether the repository root has `docker-compose.e2e.yml`, identify the frontend, backend, gateway, database, graph, cache, queue, and other services required by the target specs, then create or update `docker-compose.e2e.yml` so those services can boot reproducibly. Bring the stack up with that file and pass a Sanity Check before continuing to Playwright implementation.

**End-to-End Service Graph Rule**: E2E means exercising the real in-repository request path, not only rendering the frontend. Every new suite in this workflow must run the frontend plus the owning backend services, and must include the API gateway or reverse proxy when the frontend normally reaches APIs through it. Do not replace in-repository backends, gateways, databases, or graph stores with Playwright route stubs just to simplify setup. Use stubs only for external third-party APIs, LLM responses, slow/nondeterministic jobs, or behavior explicitly outside the repository boundary.

**User-Action Rule**: User-facing E2E scenarios must be driven through browser UI interactions that a real user can perform, such as clicking buttons, typing into fields, selecting options, uploading files, opening panels, submitting forms, cancelling work, or providing feedback. Do not implement a user-facing scenario primarily with Playwright `request` calls or direct API/stream calls. API-level calls are allowed only for setup, teardown, health checks, or non-user-facing protocol tests, and they do not replace the browser scenario.

**Manual Screenshot Rule**: Treat screenshots as reusable evidence for the DOCX user manual. Every scenario document must define meaningful UI screenshot checkpoints, and the Playwright test must capture those checkpoints when the UI state exists. Capture screenshots at user-relevant state changes such as initial screen, completed input, submitted/running state, progress, clarification needed, cache/repeated-result state, empty result, error message, cancellation, feedback submitted, and final result. Do not leave documented screenshot checkpoints unimplemented.

**Language Rule**: Write E2E documentation in Korean. This includes section headings, scenario titles, coverage notes, checklist text, scenario purpose, steps, expected results, execution summaries, and any prose derived from OpenSpec. Do not copy English Requirement/Scenario prose into E2E docs. Translate human-readable OpenSpec requirement/scenario names into Korean when they are not technical identifiers. Preserve exact technical identifiers only when they are part of the contract, such as file paths, API routes, event names, request/response fields, enum values, SQL keywords, code symbols, and stable requirement IDs.

**Workflow Gate Rule**: Execute the workflow strictly in order. Do not create or edit outputs from a later step until the current step checklist passes. If a checklist item cannot pass because evidence is missing, infrastructure is unavailable, or the repository shape is ambiguous, stop at that step and tell the user what failed, what evidence was checked, and what decision or input is needed.

## Required References

Read these files before creating or changing E2E outputs:

- [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md): canonical directory layout, naming, report locations, and validation rules.
- [TEMPLATES.md](TEMPLATES.md): required Markdown templates for coverage matrices, scenario documents, and execution summaries.
- [scripts/validate_e2e_outputs.py](scripts/validate_e2e_outputs.py): consistency checker. Run it after editing scenario docs or reports.
- [../docx-user-manual/SKILL.md](../docx-user-manual/SKILL.md): screenshot evidence expectations for DOCX user manuals. Read it when E2E screenshots may later feed user manual generation.

## Workflow

1. **Read the contract and specs**
   - Read every referenced `spec.md` before designing tests.
   - Read [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md), [TEMPLATES.md](TEMPLATES.md), and the validator contract before creating outputs.
   - If referenced OpenSpec content contains English prose, translate the human-readable requirement/scenario meaning into Korean in E2E outputs while preserving exact contract identifiers.
   - Keep public API paths, request/response fields, streaming events, and user-visible labels exact.
   - Determine the suite slug from the spec set, preserving the exact service-prefixed spec ID when the source spec uses `<microservice>_<domain>-<feature>` or `<microservice>_<feature>`.
   - Determine the canonical suite root as `openspec/specs/<spec-name>/e2e/`.
   - If the spec is traceable to a microservice/service folder, confirm the spec ID starts with the normalized service folder name followed by `_`.
   - If the service spans multiple domains, confirm the spec ID includes a domain discriminator after the service prefix. If the service is single-domain or domain-expressive, confirm the spec ID keeps the `<microservice>_` prefix and does not redundantly repeat the same domain.
   - Confirm the target spec is feature-sized and backend-associated. If it appears to summarize an entire microservice, route inventory, multiple unrelated workflows, or frontend-only behavior, stop and ask to split or regenerate the spec before creating E2E outputs.
   - Reject spec IDs whose service prefix or domain discriminator is `frontend`, `ui`, `react`, `page`, or `component`; ask for a backend/product capability spec instead.
   - Step checklist:
     - [ ] Every referenced `spec.md` and related change artifact has been read.
     - [ ] Required output contract, templates, and validator behavior are understood.
     - [ ] Human-readable OpenSpec prose has been represented in Korean in E2E outputs.
     - [ ] Suite slug decision is documented.
     - [ ] The suite slug preserves the source spec ID, including service/domain/feature separators.
     - [ ] The canonical suite root is `openspec/specs/<spec-name>/e2e/`.
     - [ ] For microservice/service-backed specs, the suite slug starts with the service folder name followed by `_`.
     - [ ] Cross-domain specs include a domain discriminator, while single-domain/domain-expressive specs avoid redundant domain repetition and keep the `<microservice>_` prefix.
     - [ ] The target spec is scoped to one backend-associated feature or cohesive workflow, not a whole microservice or frontend-only behavior.
     - [ ] The spec service prefix and domain discriminator are not implementation layers such as frontend/ui/react/page/component.
     - [ ] Blocking ambiguity has been resolved with repository evidence or by asking the user.

2. **Create coverage matrix and scenario documents**
   - This documentation step must happen before Docker Compose or Playwright files are created.
   - Extract Requirements and Scenarios into `00-coverage-matrix.md`.
   - Group multiple related spec elements into one user-centered E2E case.
   - Ensure every Requirement and important Scenario is assigned to at least one E2E case.
   - If the spec-local suite already exists, extend it instead of overwriting it. Preserve existing scenario numbers and append new files with the next two-digit prefix.
   - Write each scenario document in Korean, exactly in the format from [TEMPLATES.md](TEMPLATES.md).
   - Write coverage and scenario documents under `openspec/specs/<spec-name>/e2e/scenarios/`.
   - Requirement and scenario names in coverage tables should be Korean unless the source name is a stable technical identifier; keep API paths, fields, event names, and enum values exact.
   - Write scenario steps as real user actions only: navigate, click, type, select, upload, submit, cancel, retry, confirm, or provide feedback. Do not describe direct `request` calls as the main procedure for a user-facing E2E scenario.
   - Define screenshot checkpoints for every meaningful UI transition needed to understand the user workflow later in a DOCX manual. Each checkpoint must have a stable checkpoint name, the UI state it captures, and a short Korean manual caption.
   - Prefer Korean Playwright test titles and user-facing scenario names for tests.
   - Step checklist:
     - [ ] `00-coverage-matrix.md` exists or is updated under `openspec/specs/<spec-name>/e2e/scenarios/`.
     - [ ] Every Requirement is mapped to at least one E2E scenario.
     - [ ] Every planned scenario document exists with the required Korean headings.
     - [ ] Coverage matrix and scenario documents do not contain copied English prose from source specs except exact identifiers.
     - [ ] Every user-facing scenario procedure is expressed as browser-visible user actions, not direct API calls.
     - [ ] Every scenario with visible UI changes lists screenshot checkpoints that can support a later DOCX user manual.
     - [ ] Existing scenario numbers are preserved and new numbers are appended only.
     - [ ] No Docker Compose or Playwright implementation work has started before these documents are complete.

3. **Discover required Docker services**
   - Before writing Playwright scripts, check for root `docker-compose.e2e.yml`.
   - Read existing compose files, Dockerfiles, package scripts, backend entrypoints, API gateway config, environment examples, and spec-referenced routes to identify the minimal service graph needed for the suite.
   - Trace the frontend API calls from UI code and config to their real in-repository targets. Follow proxy settings, `VITE_*` API base URLs, gateway routes, backend router paths, service clients, and persistence dependencies.
   - Prefer existing service images, build contexts, ports, health checks, volumes, and environment conventions from the repository.
   - Include the full in-repository path needed to reproduce the tested behavior: frontend, API gateway or reverse proxy, owning backend services, and required database, graph store, cache, message broker, object storage, or mocked external dependencies.
   - Frontend-only Compose is invalid for this workflow. If the required owning backend/gateway/data services cannot be identified, stop and report the missing ownership evidence instead of creating a frontend-only suite.
   - If the gateway or backend cannot be identified quickly, stop and inspect more repository evidence instead of defaulting to frontend-only. If ownership remains ambiguous after inspection, ask the user before inventing or omitting services.
   - Step checklist:
     - [ ] Root `docker-compose.e2e.yml` existence has been checked.
     - [ ] Frontend API calls and proxy/API base URL configuration have been traced.
     - [ ] Owning backend services and gateway/reverse proxy requirements have been identified for every API-backed scenario.
     - [ ] Required data dependencies, seeds, and external boundaries are listed.
     - [ ] Frontend-only Compose has been rejected.

4. **Create or update deterministic infrastructure**
   - Treat the root `docker-compose.e2e.yml` as mandatory and as the orchestration entrypoint for every suite.
   - Create the file if it does not exist. If it exists, extend it without breaking unrelated suites.
   - Compose must model the application boundary used in production-like local execution: frontend depends on gateway when present, gateway depends on backend services, and backend services depend on their data stores or brokers.
   - Configure frontend API base URLs so browser requests flow through the Docker-hosted gateway/backend path, not through Playwright route interception for owned services.
   - Seed only the minimum database/graph data needed for the tests, and keep suite-specific seed files under `openspec/specs/<spec-name>/e2e/seed_files/`.
   - Keep suite-specific helper scripts, init files, and Docker override files under `openspec/specs/<spec-name>/e2e/scripts/` or `openspec/specs/<spec-name>/e2e/docker/`.
   - Load `.env` through Compose or test config, but never print secrets into docs, logs, screenshots, or fixtures.
   - Keep domain-specific data generic unless the spec itself requires a domain concept.
   - Add explicit health checks or readiness probes for services that Playwright or Sanity Check depends on.
   - Step checklist:
     - [ ] Root `docker-compose.e2e.yml` exists and includes the frontend, owning backend services, gateway/reverse proxy when used by the app, and required data dependencies for every API-backed scenario.
     - [ ] Suite-specific seed files are under `openspec/specs/<spec-name>/e2e/seed_files/`.
     - [ ] Frontend API base URLs point at Docker-hosted gateway/backend routes.
     - [ ] Owned backend, gateway, database, or graph behavior is not replaced by Playwright route stubs.
     - [ ] Required services have health checks or readiness checks.

5. **Boot Docker stack and run Sanity Check**
   - Validate the compose file from the repository root with `docker compose -f docker-compose.e2e.yml config`.
   - Start the stack with `docker compose -f docker-compose.e2e.yml up -d --build` before writing Playwright tests.
   - Run a Sanity Check against the Docker-hosted endpoints first: verify containers are healthy, required ports respond, gateway routes reach backend services, core API health routes return success, migrations/seeds are applied, and the frontend can load.
   - For API-backed suites, the Sanity Check must include at least one browser-reachable or HTTP-level request that traverses the same frontend-to-gateway-to-backend route the Playwright test will use.
   - Fix compose, environment, seed, or readiness issues before adding or modifying Playwright specs.
   - Record Sanity Check commands and outcomes in the execution summary.
   - Step checklist:
     - [ ] `docker compose -f docker-compose.e2e.yml config` passes.
     - [ ] `docker compose -f docker-compose.e2e.yml up -d --build` starts the stack.
     - [ ] Required containers are healthy or explicitly ready.
     - [ ] Migrations and seed loading required by the scenarios have completed.
     - [ ] At least one real frontend-to-gateway-to-backend or frontend-to-backend route works through Docker for API-backed suites.

6. **Write Playwright tests**
   - Use `page.route()` or API-level request stubs only for external services, LLM outputs, slow nondeterministic jobs, or explicit failure injection that cannot be produced deterministically through the Docker stack.
   - Do not stub the primary API contract between the frontend, gateway, and owned backend service for the scenario under test.
   - Implement user-facing scenarios with `page` interactions that mimic real user behavior. Prefer `page.goto`, locator-based `click`, `fill`, `press`, `selectOption`, `setInputFiles`, and visible assertions over direct `request` calls.
   - Do not use Playwright `request` as the primary action path for scenarios that claim to verify a user's workflow. If API-level checks are still useful, keep them as supplementary assertions after the browser-driven flow has exercised the UI.
   - Validate request bodies, headers, response media types, stream event order, terminal events, and UI state.
   - Capture screenshots for every scenario checkpoint documented in the scenario file and store them under the stable result directory defined in [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md).
   - Write Playwright test scripts and suite-specific Playwright config under `openspec/specs/<spec-name>/e2e/tests/`.
   - Name screenshots so they remain traceable from scenario documents and useful to manuals, for example `<project>-<suite-slug>-NN-<checkpoint-name>.png`.
   - Prefer full-page or stable region screenshots that show enough surrounding UI for a user manual. Hide or avoid secrets, tokens, and irrelevant developer panels.
   - Prefer scoped locators over broad text selectors when labels repeat.
   - Reuse existing fixture helpers within the suite before adding new helpers.
   - Step checklist:
     - [ ] Playwright tests map back to the already-created scenario documents.
     - [ ] Playwright tests and suite-specific config are under `openspec/specs/<spec-name>/e2e/tests/`.
     - [ ] Every user-facing scenario is driven through browser UI actions a real user can perform.
     - [ ] Tests run against the Docker Compose stack.
     - [ ] Playwright route stubs do not replace in-repository backend or gateway behavior that the scenario claims to verify.
     - [ ] Direct `request` calls are limited to setup, teardown, health checks, or supplementary non-user-facing assertions.
     - [ ] Request bodies, headers, response media types, stream order, terminal events, and UI state are asserted where relevant.
     - [ ] Each documented screenshot checkpoint has a corresponding screenshot capture in the Playwright code.
     - [ ] Reports, artifacts, and screenshots are configured for the canonical result paths.

7. **Validate**
   - Run Playwright tests against the Docker Compose stack, not a separately started local process.
   - Run existing protocol/unit tests if available.
   - Re-run `docker compose -f docker-compose.e2e.yml config` after compose changes.
   - Syntax-check helper shell scripts.
   - Run the E2E output validator against the spec-local suite root when available, for example `python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite <suite-slug> --suite-root openspec/specs/<spec-name>/e2e`.
   - The validator checks the Korean headings defined in [TEMPLATES.md](TEMPLATES.md); update the templates and validator together if the section contract changes.
   - Fix failures and rerun until deterministic checks pass.
   - Step checklist:
     - [ ] Playwright run passes or failures are documented with the blocking cause.
     - [ ] Screenshot files exist for every screenshot checkpoint listed in the scenario documents, or the missing checkpoint is reported as a gate failure.
     - [ ] Compose config validation has been re-run after infrastructure changes.
     - [ ] Relevant protocol/unit checks have been run when available.
     - [ ] Helper scripts syntax-check successfully when present.
     - [ ] E2E output validator passes for the suite.

8. **Document usage**
   - Write or update the suite execution summary using [TEMPLATES.md](TEMPLATES.md).
   - Include paths for scenarios, tests, Docker files, seed files, Sanity Check output, result JSON/HTML, screenshots, trace files, and validation command output.
   - Include a screenshot map that links each scenario checkpoint to its screenshot file and Korean manual caption.
   - Step checklist:
     - [ ] Execution summary records the ordered workflow results, including Sanity Check and validation commands.
     - [ ] Execution summary lists screenshot files by scenario and checkpoint for DOCX user manual reuse.
     - [ ] Scenario docs, execution summary, tests, seed/stub files, reports, and screenshots are written under `openspec/specs/<spec-name>/e2e/`.
     - [ ] Known gaps or user-required follow-ups are explicit.
     - [ ] The execution guide can be followed from a clean checkout.

## Common Pitfalls

- Repeated UI labels: scope selectors, e.g. `.result-content .feedback-btn`, instead of plain `getByText()`.
- Streaming fixtures: include fields the UI store expects, such as `steps: []` for waiting states.
- Floating overlays: use button-specific classes; use `force: true` only when an overlay is intentionally nonessential to the assertion.
- Test data: keep rows small and focused on contract coverage, not realism.
- Docker bypass: do not write Playwright specs against manually started services or host-installed databases. The root `docker-compose.e2e.yml` must be the first executable environment contract.
- Scattered outputs: keep suite-specific E2E outputs under the source spec folder.
- Frontend-only Compose: do not call a suite E2E if Compose only boots the UI while owned APIs are replaced by Playwright route stubs. Add the gateway/backend/data services, or stop and ask for the source spec to be regenerated around the owning backend/product capability.
- Over-stubbing: browser/API stubs are for nondeterministic external boundaries, not for bypassing services this repository owns.
- Request-only scenarios: do not replace a user workflow with Playwright `request` calls. A request-only check may be useful, but it is not enough for a user-facing E2E scenario or manual screenshot evidence.
- Screenshot drift: do not list screenshot checkpoints in scenario documents unless the Playwright code captures them, and do not capture undocumented screenshots that cannot be mapped back to a scenario checkpoint.
- Manual-unfriendly screenshots: avoid tiny cropped states, transient overlays, developer consoles, secrets, and screenshots without enough context for a first-time user.
- Premature Playwright work: if the Docker stack has not passed Sanity Check, pause test implementation and fix infrastructure first.
- Result drift: do not invent new report headings, ad hoc screenshot folders, or one-off output names. Update the templates first if the contract must change.
- Language drift: do not switch generated scenario docs, coverage rows, execution summaries, or copied OpenSpec prose back to English unless the user explicitly requests English output. Keep only exact contract identifiers in their original form.

## Gate Failure Reporting

When any step checklist cannot pass, stop the workflow and report:

- The current step number and name.
- The checklist item that failed.
- The repository evidence already checked.
- The reason it cannot be completed safely.
- The specific user decision, missing input, or repository fix needed before continuing.
