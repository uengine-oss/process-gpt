---
name: e2e-tests
description: Design, implement, and maintain spec-driven Playwright E2E tests from OpenSpec spec.md files. Use when creating or extending E2E coverage matrices, scenario documents, Playwright specs, deterministic API stubs, Dockerized infrastructure, source-run backend/frontend services, screenshots, backend/frontend coverage gates, AI spec coverage HTML reports, and stable execution reports.
argument-hint: "<spec-name>"
arguments: [spec_name]
disable-model-invocation: true
license: MIT
compatibility: Requires Docker Compose and Playwright. E2E suites must boot durable infrastructure dependencies through the root docker-compose.e2e.yml, while repository-owned backend, gateway, and frontend services run directly from source with documented local commands before Playwright tests are written or run. Coverage gates require runtime-appropriate coverage tools such as coverage.py, c8/nyc, JaCoCo, and Monocart; install them when absent and document the command.
metadata:
  author: project
  version: "1.3"
---

# Spec-Driven E2E Tests

Create deterministic, incrementally maintainable E2E coverage from OpenSpec requirements.

**Input**: One or more `spec.md` files, related app/backend files, environment hints, and optional existing tests.

**Direct command input**: When invoked as `/e2e-tests <spec-name>`, use `$spec_name` as the exact OpenSpec folder name. Project feature specs MUST use the service-prefixed OpenSpec ID format: `<microservice>_<domain>-<feature>` for cross-domain services or `<microservice>_<feature>` for single-domain/domain-expressive services (for example `completion_agent-memory-chat` or `billing_invoice-search`). If `$spec_name` is empty, ask for the spec folder name. Find `openspec/specs/<spec-name>/spec.md`, read it and related artifacts, then run this workflow from that evidence. If the folder is missing or ambiguous, ask the user to choose instead of guessing.

**Feature Traceability Rule**: Preserve the OpenSpec spec folder name as the default E2E suite slug. For `openspec/specs/completion_agent-memory-chat/spec.md`, use suite slug `completion_agent-memory-chat`; for `openspec/specs/billing_invoice-search/spec.md`, use suite slug `billing_invoice-search`. Do not rewrite underscores or hyphens because they preserve the service/domain/feature boundary across scenario documents, test paths, results, screenshots, and later DOCX manuals.

**Spec-Local Output Rule**: E2E outputs MUST be colocated with the source spec. For `openspec/specs/<spec-name>/spec.md`, create or update `openspec/specs/<spec-name>/e2e/` and keep scenario documents, coverage matrices, seed/stub files, Playwright test scripts, suite-specific setup/config, execution summaries, result JSON/HTML, screenshots, traces, and helper scripts under that folder. Do not create suite outputs outside that folder. The repository root `docker-compose.e2e.yml` remains the shared infrastructure entrypoint, but suite-specific files and local service startup helpers belong under the spec-local `e2e/` folder.

**Microservice Prefix Consistency Rule**: If E2E evidence or related source paths show that a spec was generated from a specific microservice/service folder, the spec ID must start with that service name followed by `_`. For example, specs covering `services/completion` should use suite slugs such as `completion_agent-memory-chat`, `completion_mcp-server-config`, or `completion_notification-push-delivery`. If the source spec replaces the service prefix with a discovered subdomain or resource name, such as `agent_memory-chat`, `mcp_server-config`, or `notification_push-delivery`, or if it drops the underscore boundary, such as `agent-feedback-feedback-processing` for `services/agent-feedback`, stop and ask for the OpenSpec spec to be regenerated or renamed before creating E2E outputs.

**Backend-Associated Spec Rule**: Only create E2E suites for specs tied to repository-owned backend/product behavior. The service prefix or domain discriminator MUST NOT be an implementation layer such as `frontend`, `ui`, `react`, `page`, or `component`. If a spec is named like `frontend_*`, `frontend-*`, or only describes frontend-local UI behavior, stop before writing E2E outputs and report that the spec should be regenerated around the owning backend/product capability. Frontend UI remains required as the user interaction surface, but it is not the domain under test.

**Core Rule**: Do not let E2E success depend on external APIs, long-running jobs, or large production datasets. Use fixed fixtures and browser/API stubs for nondeterministic behavior.

**Hybrid Runtime Rule**: Use Docker only for stable infrastructure dependencies, not for repository-owned application services. Before writing or changing Playwright specs, check whether the repository root has `docker-compose.e2e.yml`, identify the full runtime graph, and classify each required node as either:
- **Infrastructure**: database, graph store, cache, queue, object storage, mail sink, external-service mock, or other durable dependency whose internal code is not the feature under active development. These MUST be defined in or reused from `docker-compose.e2e.yml`.
- **Application service**: repository-owned frontend, backend, API gateway, reverse proxy, worker, or BFF whose source changes with product work. These MUST run directly from the working tree using the repository's local scripts/entrypoints, with suite-specific startup helpers under `openspec/specs/<spec-name>/e2e/scripts/` when needed.

Do not add Docker images, Dockerfiles, or Compose app services for repository-owned frontend/backend/gateway code solely to satisfy E2E setup. Bring up infrastructure containers first, start source-run app services against that infrastructure, then pass a Sanity Check before continuing to Playwright implementation.

**End-to-End Service Graph Rule**: E2E means exercising the real in-repository request path, not only rendering the frontend. Every new suite in this workflow must run the frontend plus the owning backend services, and must include the API gateway or reverse proxy when the frontend normally reaches APIs through it. Repository-owned app services run from source; infrastructure dependencies run in Docker. Do not replace in-repository backends, gateways, databases, graph stores, or other owned behavior with Playwright route stubs just to simplify setup. Use stubs only for external third-party APIs, LLM responses, slow/nondeterministic jobs, or behavior explicitly outside the repository boundary.

**User-Action Rule**: User-facing E2E scenarios must be driven through browser UI interactions that a real user can perform, such as clicking buttons, typing into fields, selecting options, uploading files, opening panels, submitting forms, cancelling work, or providing feedback. Do not implement a user-facing scenario primarily with Playwright `request` calls or direct API/stream calls. API-level calls are allowed only for setup, teardown, health checks, or non-user-facing protocol tests, and they do not replace the browser scenario.

**Real-Frontend Rule**: The browser UI driven by Playwright MUST be the repository's actual user-facing frontend served from the working tree by the repository's local frontend command. Specs do not always map 1:1 to a dedicated frontend screen — a spec may describe a backend contract that the real frontend exercises indirectly (for example, an LLM gateway route invoked from inside the chat UI, a process-data-query API consumed during workitem execution, a tenant-admin API called from settings dialogs). In those cases you MUST still drive the scenario through the indirect real-user path that triggers the behavior, and capture screenshots of that real flow.
- Do NOT serve synthetic tester HTML, debug consoles, or developer-only pages through `page.route()`, `page.setContent()`, file:// URLs, or any other injection mechanism in order to satisfy the User-Action Rule or Manual Screenshot Rule. The `page.route()` allowance for external boundaries (LLM, third-party APIs, nondeterministic jobs) does NOT extend to fabricating a UI.
- Before writing Playwright code, trace the indirect path: which real frontend route, component, action, or workflow causes the spec's backend behavior to execute? Drive that path. The screenshots must show the real product UI a user would see.
- If no indirect real-user path exists in the current frontend (the capability is genuinely backend-only with no user-visible surface), STOP and trigger Gate Failure Reporting asking for scope re-adjustment — either (a) split out a backend-contract spec with screenshot/manual obligations explicitly waived, or (b) extend the frontend to expose the capability first. Do NOT proceed by injecting a synthetic tester page.

**Manual Screenshot Rule**: Treat screenshots as reusable evidence for the DOCX user manual. Every scenario document must define meaningful UI screenshot checkpoints, and the Playwright test must capture those checkpoints when the UI state exists. Capture screenshots at user-relevant state changes such as initial screen, completed input, submitted/running state, progress, clarification needed, cache/repeated-result state, empty result, error message, cancellation, feedback submitted, and final result. Do not leave documented screenshot checkpoints unimplemented.

**Spec Coverage Gate Rule**: Every completed suite must run an OpenSpec traceability gate and collect spec-relevant backend coverage plus frontend browser coverage before final reporting. For backend-associated specs, backend coverage is a hard gate unless a concrete instrumentation command was attempted and failed for a documented environmental reason. For user-facing frontend specs, source-mapped frontend coverage must be attempted before bundle-level fallback is accepted. Judge coverage by the backend/frontend files and functions that directly implement or expose the OpenSpec capability, not by whole-repository percentages alone. Generate `openspec/specs/<spec-name>/e2e/results/spec-coverage-report.html` and `coverage-summary.json` with an AI judgment explaining whether the coverage is sufficient for this spec.

**Language Rule**: Write E2E documentation in Korean. This includes section headings, scenario titles, coverage notes, checklist text, scenario purpose, steps, expected results, execution summaries, and any prose derived from OpenSpec. Do not copy English Requirement/Scenario prose into E2E docs. Translate human-readable OpenSpec requirement/scenario names into Korean when they are not technical identifiers. Preserve exact technical identifiers only when they are part of the contract, such as file paths, API routes, event names, request/response fields, enum values, SQL keywords, code symbols, and stable requirement IDs.

**Workflow Gate Rule**: Execute the workflow as a dependency graph organized into Phases (see "Phases and Parallelization" below). Do not start a new Phase until the previous Phase's gate checklist passes. Within one Phase, items without dependencies on each other SHOULD be invoked in parallel as long as they do not contend on the same Docker container, local app process, port, or DB state. If a checklist item cannot pass because evidence is missing, infrastructure is unavailable, or the repository shape is ambiguous, stop at that step and tell the user what failed, what evidence was checked, and what decision or input is needed.

## Repository E2E Memory and Reusable Scripts

The repository keeps cross-suite E2E knowledge under `openspec/e2e/`:

- `openspec/e2e/memories/`: project-specific E2E knowledge that the skill itself does not capture — encountered pitfalls, infrastructure quirks, build/coverage workarounds. Each memory file is a small Markdown document with frontmatter (`name`, `description`, `applies-to`, `last-verified`, `metadata.type`). `index.md` lists every memory in one line per entry. Treat this exactly like Claude's personal memory system: short index, semantic file organization, `[[wiki-link]]` between memories, freshness check before applying.
- `openspec/e2e/scripts/`: reusable code artifacts (mock servers, coverage helpers, build wrappers) that more than one suite consumes. Suite-specific scripts stay under `openspec/specs/<spec-name>/e2e/scripts/`. Promote a script to `openspec/e2e/scripts/` only after it has been written twice and the second copy is essentially the first with minor differences — do not preemptively generalize.

Reading these in Phase A and writing back in Phase F is mandatory. The skill stays generic; project-local lessons accumulate here. If `openspec/e2e/memories/` or `openspec/e2e/scripts/` do not yet exist, create them in Phase F when there is something worth saving.

## Phases and Parallelization

The numbered workflow below is a dependency graph, not a strict linear sequence. Across phases, do not start a phase until the previous phase's gate checklist passes. Inside one phase, items without dependencies on each other SHOULD be invoked in a single message using multiple parallel tool calls.

- **Phase A (Plan)**: Steps 1–2. Sequential — Step 2 reads Step 1's output. Step 1 includes reading `openspec/e2e/memories/index.md` and relevant memories.
- **Phase B (Runtime Plan + Infra)**: Steps 3–4. Sequential — Step 4 builds on Step 3's service-graph discovery and infrastructure/application classification.
- **Phase C (Boot + Sanity)**: Step 5. Sequential — infrastructure containers start first, then source-run app services.
- **Phase D (Tests)**: Step 6 plus the Playwright execution part of Step 7. The Playwright run must complete before Phase E starts.
- **Phase E (Validate + Gate)**: The non-Playwright parts of Step 7 and all of Step 8. After Playwright passes, the following are independent and SHOULD run in parallel when they do not contend on shared resources:
  - `scripts/validate_e2e_outputs.py` (pure read on artifacts)
  - `scripts/evaluate_spec_coverage.mjs` (pure read on artifacts)
  - Backend coverage recollection (re-runs or restarts the owning backend source process under coverage.py / c8 / JaCoCo)
  - Frontend coverage recollection (Playwright re-run with V8 coverage, or source-mapped rebuild)
  - The HTML report and `coverage-summary.json` write depend on all four completing.
- **Phase F (Document + Capture Lessons)**: Step 9 — execution summary plus memory write-back and script promotion review.

**Shared-resource rule**: if two parallel candidates touch the same container, local app process, port, DB row, or coverage data directory, serialize them. The classic conflict is "backend coverage recollection restarts the completion backend process while Playwright is still running against it" — that must be sequential. Note in the execution summary which steps were combined and which shared resources were respected.

## Required References

Read these files before creating or changing E2E outputs:

- [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md): canonical directory layout, naming, report locations, and validation rules.
- [TEMPLATES.md](TEMPLATES.md): required Markdown templates for coverage matrices, scenario documents, and execution summaries.
- [COVERAGE_HTML_TEMPLATE.html](COVERAGE_HTML_TEMPLATE.html): HTML template for the AI-written spec coverage report.
- [scripts/validate_e2e_outputs.py](scripts/validate_e2e_outputs.py): consistency checker. Run it after editing scenario docs or reports.
- [scripts/evaluate_spec_coverage.mjs](scripts/evaluate_spec_coverage.mjs): OpenSpec traceability gate. Run it after Playwright results exist to verify Requirement/Scenario/Test/Screenshot coverage and update `coverage-summary.json`.
- [scripts/review_compose_runtime.py](scripts/review_compose_runtime.py): Hybrid Runtime Rule pre-check. MUST be run BEFORE creating, editing, or booting `docker-compose.e2e.yml`. Emits WARNINGS (not errors) when Compose service entries look like repository-owned frontend or backend services. Warnings are informational because there are legitimate exceptions, but every warning must be either resolved (move the service to source-run) or explicitly justified in the execution summary as a user-approved app-container exception. Always invoke with `python -X utf8 ...` (or set `PYTHONIOENCODING=utf-8`) so the Korean warning text renders correctly on Windows consoles whose default code page is not UTF-8.
- [../docx-user-manual/SKILL.md](../docx-user-manual/SKILL.md): screenshot evidence expectations for DOCX user manuals. Read it when E2E screenshots may later feed user manual generation.

## Workflow

1. **Read the contract, specs, and project E2E memory** (Phase A)
   - Read every referenced `spec.md` before designing tests.
   - Read [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md), [TEMPLATES.md](TEMPLATES.md), [COVERAGE_HTML_TEMPLATE.html](COVERAGE_HTML_TEMPLATE.html), and the validator contract before creating outputs.
   - Read `openspec/e2e/memories/index.md` if it exists. For each memory file whose `applies-to` frontmatter matches this spec's stack (backend language/framework, frontend framework, database, special dependencies like mem0/pgvector, build/coverage tool), read the memory file. Before applying a memory, verify the referenced files, commands, image tags are still valid — memories rot. If you can't verify a referenced fact, treat the memory as a hint and check the current state instead.
   - Skim `openspec/e2e/scripts/` (or its `README.md`) for reusable mocks, coverage helpers, or build wrappers that may fit this suite. Prefer reusing or extending these scripts to writing new ones; only write a suite-local script when no shared script fits.
   - Survey already-existing E2E suites under `openspec/specs/*/e2e/` for fixtures, helper functions, login flows, mock services, and seed patterns that can be reused. Record the reusable items in the coverage matrix's `재사용 산출물` section.
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
     - [ ] The coverage HTML report template is understood.
     - [ ] `openspec/e2e/memories/index.md` has been read (or its absence noted). Memories with matching `applies-to` have been read and their freshness checked.
     - [ ] `openspec/e2e/scripts/` has been surveyed for reusable artifacts.
     - [ ] Existing E2E suites have been surveyed for reusable fixtures/helpers/mocks; reusable items are listed for inclusion in the coverage matrix.
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
   - This documentation step must happen before Docker Compose, local service startup helpers, or Playwright files are created.
   - Extract Requirements and Scenarios into `00-coverage-matrix.md`.
   - Group multiple related spec elements into one user-centered E2E case.
   - Ensure every Requirement and important Scenario is assigned to at least one E2E case.
   - Identify the spec-relevant code surface before writing tests: backend route handlers, service functions, clients, persistence adapters, jobs/events, frontend routes, pages, components, stores, and API clients that directly implement or expose the OpenSpec behavior.
   - Record the spec-relevant backend and frontend files/functions in the `스펙 관련 코드 표면` section of `00-coverage-matrix.md`. If a file is shared infrastructure, mark it as supporting evidence instead of applying the same threshold as feature-owned files.
   - Define initial coverage thresholds per relevant surface. Prefer backend route/service/client thresholds such as line/function >= 80%; treat frontend coverage as supporting when the app is served from a prebuilt/minified image or sourcemaps are unavailable.
   - If the spec-local suite already exists, extend it instead of overwriting it. Preserve existing scenario numbers and append new files with the next two-digit prefix.
   - Write each scenario document in Korean, exactly in the format from [TEMPLATES.md](TEMPLATES.md).
   - Write coverage and scenario documents under `openspec/specs/<spec-name>/e2e/scenarios/`.
   - Requirement and scenario names in coverage tables should be Korean unless the source name is a stable technical identifier; keep API paths, fields, event names, and enum values exact.
   - Write scenario steps as real user actions only: navigate, click, type, select, upload, submit, cancel, retry, confirm, or provide feedback. Do not describe direct `request` calls as the main procedure for a user-facing E2E scenario.
   - Identify the real frontend entry point (route, page, component, button, dialog, workflow step) that triggers the spec's behavior, even when the spec describes a backend contract used indirectly. Record that entry point in the scenario document so reviewers can verify the path is a real user surface, not a fabricated tester page.
   - If no real frontend path can be identified for any scenario in the spec, stop with Gate Failure Reporting and request scope re-adjustment before continuing to runtime/Playwright work.
   - Define screenshot checkpoints for every meaningful UI transition needed to understand the user workflow later in a DOCX manual. Each checkpoint must have a stable checkpoint name, the UI state it captures, and a short Korean manual caption.
   - Prefer Korean Playwright test titles and user-facing scenario names for tests.
   - Step checklist:
     - [ ] `00-coverage-matrix.md` exists or is updated under `openspec/specs/<spec-name>/e2e/scenarios/`.
     - [ ] Every Requirement is mapped to at least one E2E scenario.
     - [ ] Every planned scenario document exists with the required Korean headings.
     - [ ] Coverage matrix and scenario documents do not contain copied English prose from source specs except exact identifiers.
     - [ ] Every user-facing scenario procedure is expressed as browser-visible user actions, not direct API calls.
     - [ ] Each scenario records the real frontend entry point that triggers the spec's behavior (including indirect paths), and no scenario relies on a fabricated/injected tester page.
     - [ ] If any scenario has no real frontend entry point, the workflow has stopped at Gate Failure Reporting with a scope re-adjustment request.
     - [ ] Every scenario with visible UI changes lists screenshot checkpoints that can support a later DOCX user manual.
     - [ ] Spec-relevant backend files/functions/routes are listed with coverage thresholds and selection evidence.
     - [ ] Spec-relevant frontend files/components/API calls are listed with coverage thresholds or documented as supporting V8/bundle evidence.
     - [ ] Existing scenario numbers are preserved and new numbers are appended only.
     - [ ] No Docker Compose, local service startup, or Playwright implementation work has started before these documents are complete.

3. **Discover required runtime services**
   - Before writing Playwright scripts, check for root `docker-compose.e2e.yml`.
   - Read existing compose files, package scripts, backend entrypoints, API gateway config, environment examples, and spec-referenced routes to identify the minimal service graph needed for the suite.
   - Trace the frontend API calls from UI code and config to their real in-repository targets. Follow proxy settings, `VITE_*` API base URLs, gateway routes, backend router paths, service clients, and persistence dependencies.
   - Classify each graph node as infrastructure or application service. Prefer Docker Compose only for infrastructure images, ports, health checks, volumes, and environment conventions already present in the repository.
   - Include the full in-repository path needed to reproduce the tested behavior: source-run frontend, source-run API gateway or reverse proxy when present, source-run owning backend services, and Dockerized database, graph store, cache, message broker, object storage, or mocked external dependencies.
   - Frontend-only runtime is invalid for this workflow. If the required owning backend/gateway/data services cannot be identified, stop and report the missing ownership evidence instead of creating a frontend-only suite.
   - If the gateway or backend cannot be identified quickly, stop and inspect more repository evidence instead of defaulting to frontend-only. If ownership remains ambiguous after inspection, ask the user before inventing or omitting services.
   - Step checklist:
     - [ ] Root `docker-compose.e2e.yml` existence has been checked.
     - [ ] Frontend API calls and proxy/API base URL configuration have been traced.
     - [ ] Owning backend services and gateway/reverse proxy requirements have been identified for every API-backed scenario.
     - [ ] Each required service is classified as Dockerized infrastructure or source-run application service.
     - [ ] Required data dependencies, seeds, and external boundaries are listed.
     - [ ] Frontend-only runtime has been rejected.

4. **Create or update deterministic infrastructure and source-run app startup**
   - Treat the root `docker-compose.e2e.yml` as mandatory for infrastructure dependencies only.
   - Create the file if it does not exist. If it exists, extend it without breaking unrelated suites.
   - **Run the Compose runtime pre-check FIRST**, before any other Phase B work and before any `docker compose ... up`:
     `python -X utf8 .claude/skills/e2e-tests/scripts/review_compose_runtime.py --compose docker-compose.e2e.yml`
     This is a heuristic gate that flags Compose service entries that look like repository-owned frontend/backend services (Hybrid Runtime Rule violations). It returns WARNINGS, not errors. Every warning must be either (a) resolved by moving the service to a source-run command and removing it from Compose, or (b) explicitly justified as a user-approved app-container exception and documented in the execution summary. Re-run the script after any edit to `docker-compose.e2e.yml` and again immediately before boot in Step 5. Do not rely on the LLM to remember the rule mid-flow — let the script be the gate.
   - Compose must model stable infrastructure dependencies such as databases, graph stores, caches, queues, object storage, mail sinks, and external-service mocks. It MUST NOT Dockerize repository-owned frontend, backend, gateway, reverse proxy, worker, or BFF code unless the user explicitly approves an exception because no local source-run command exists.
   - Configure frontend API base URLs so browser requests flow through the source-run gateway/backend path, not through Playwright route interception for owned services.
   - Document or create suite-local scripts that start every application service from the working tree with deterministic environment variables pointing at the Dockerized infrastructure.
   - Seed only the minimum database/graph data needed for the tests, and keep suite-specific seed files under `openspec/specs/<spec-name>/e2e/seed_files/`.
   - Keep suite-specific helper scripts, init files, and Docker infrastructure overrides under `openspec/specs/<spec-name>/e2e/scripts/` or `openspec/specs/<spec-name>/e2e/docker/`.
   - Add suite-specific coverage helpers under `openspec/specs/<spec-name>/e2e/scripts/`. Use Docker coverage overrides only for infrastructure or explicit user-approved app-container exceptions. Do not place coverage helpers in ad hoc repository-global scratch folders.
   - For Python/FastAPI backends, start the local source process with `coverage.py`, for example `coverage run --parallel-mode --save-signal=USR2 --source=<service-source> -m uvicorn ...`, write data under `e2e/results/backend-coverage/`, then run `coverage combine`, `coverage xml -o <backend-coverage>/coverage.xml`, and `coverage html -d <backend-coverage>/html`. Backend coverage is incomplete if `backend-coverage/html/index.html` is missing.
   - For Node.js backends, prefer `c8` or `nyc` around the local server entrypoint, with XML/LCOV plus HTML reports written under `e2e/results/backend-coverage/`. Backend coverage is incomplete if only raw data exists and no human-readable HTML report is generated.
   - For Java/JVM backends, prefer JaCoCo agent/report generation around the local service process with XML and HTML copied under `e2e/results/backend-coverage/`. Backend coverage is incomplete if `backend-coverage/html/index.html` or the build-tool equivalent is missing.
   - Source-level frontend coverage is the default target. Before accepting bundle-only frontend coverage, check whether the frontend can be rebuilt with sourcemaps. For Vite frontends, create a coverage build/override that sets `build.sourcemap: true` or the equivalent environment/config and serves that rebuilt artifact through the E2E gateway. For other frontend stacks, enable the framework's production sourcemap option.
   - If the default frontend command serves minified assets without sourcemaps, do not stop at bundle-only coverage immediately. First create a suite-specific source-run frontend coverage command or build wrapper under `e2e/scripts/` that builds from repository source with sourcemaps enabled and points the source-run gateway/backend to that coverage frontend. Use prebuilt bundle/V8-only coverage only when a source-map rebuild command was actually attempted and failed, or repository evidence shows a source-built frontend is impossible. Document the exact command, failure, and reason.
   - If required coverage tools are missing, install or add them using the service's package manager and document the exact command. Examples: `python -m pip install coverage`, `npm install --save-dev c8`, `npm install --save-dev monocart-coverage-reports`, or the repository's Java build plugin for JaCoCo. Keep installed dependencies scoped to the service or suite tooling where possible.
   - Load `.env` through Compose, local service commands, or test config, but never print secrets into docs, logs, screenshots, or fixtures.
   - Keep domain-specific data generic unless the spec itself requires a domain concept.
   - Add explicit health checks or readiness probes for services that Playwright or Sanity Check depends on.
   - Step checklist:
     - [ ] Root `docker-compose.e2e.yml` exists and includes the required infrastructure dependencies for every API-backed scenario.
     - [ ] `python -X utf8 .claude/skills/e2e-tests/scripts/review_compose_runtime.py --compose docker-compose.e2e.yml` has been run; every emitted warning has been either resolved by source-running the flagged service or recorded as a user-approved exception in the execution summary.
     - [ ] Suite-specific seed files are under `openspec/specs/<spec-name>/e2e/seed_files/`.
     - [ ] `docker-compose.e2e.yml` includes required infrastructure dependencies only, unless an app-container exception is explicitly approved.
     - [ ] Repository-owned frontend/backend/gateway services have source-run commands or suite-local startup helpers.
     - [ ] Frontend API base URLs point at source-run gateway/backend routes.
     - [ ] Owned backend, gateway, database, or graph behavior is not replaced by Playwright route stubs.
     - [ ] Required services have health checks or readiness checks.
     - [ ] Backend coverage instrumentation is configured for the owning service and will produce both XML and HTML reports; otherwise stop with Gate Failure Reporting.
     - [ ] Frontend source-map coverage collection is attempted through a source-run coverage build/command when the default frontend lacks sourcemaps; otherwise stop with Gate Failure Reporting.
     - [ ] Frontend browser coverage collection and report generation are configured, with source-map quality documented.

5. **Boot infrastructure, start source-run services, and run Sanity Check**
   - Re-run the Hybrid Runtime Rule pre-check immediately before boot:
     `python -X utf8 .claude/skills/e2e-tests/scripts/review_compose_runtime.py --compose docker-compose.e2e.yml`
     Every warning must already be either resolved or justified per Step 4. Do not boot Compose while unresolved/unjustified warnings remain.
   - Validate the compose file from the repository root with `docker compose -f docker-compose.e2e.yml config`.
   - Start infrastructure with `docker compose -f docker-compose.e2e.yml up -d` before writing Playwright tests. Add `--build` only when infrastructure images or suite-specific infrastructure overrides require it.
   - Start repository-owned app services from source using the documented commands or suite-local startup helpers after infrastructure is ready.
   - Run a Sanity Check against the hybrid runtime first: verify containers are healthy, local app process ports respond, gateway routes reach backend services, core API health routes return success, migrations/seeds are applied, and the frontend can load.
   - For API-backed suites, the Sanity Check must include at least one browser-reachable or HTTP-level request that traverses the same frontend-to-gateway-to-backend or frontend-to-backend route the Playwright test will use, with application services running from source and infrastructure behind Docker.
   - Fix compose, environment, seed, or readiness issues before adding or modifying Playwright specs.
   - Record Sanity Check commands and outcomes in the execution summary.
   - Step checklist:
     - [ ] `python -X utf8 .claude/skills/e2e-tests/scripts/review_compose_runtime.py --compose docker-compose.e2e.yml` has been re-run and every warning is either resolved or recorded as a user-approved exception in the execution summary.
     - [ ] `docker compose -f docker-compose.e2e.yml config` passes.
     - [ ] `docker compose -f docker-compose.e2e.yml up -d` starts the required infrastructure containers.
     - [ ] Required infrastructure containers are healthy or explicitly ready.
     - [ ] Source-run frontend/backend/gateway services have started with documented commands and ready ports.
     - [ ] Migrations and seed loading required by the scenarios have completed.
     - [ ] At least one real frontend-to-gateway-to-backend or frontend-to-backend route works through the hybrid runtime for API-backed suites.

6. **Write Playwright tests**
   - Use `page.route()` or API-level request stubs only for external services, LLM outputs, slow nondeterministic jobs, or explicit failure injection that cannot be produced deterministically through the hybrid runtime.
   - Do not stub the primary API contract between the frontend, gateway, and owned backend service for the scenario under test.
   - Do not use `page.route()`, `page.setContent()`, `file://` URLs, or any other mechanism to serve a synthetic tester HTML, debug console, or developer-only page as the page under test. The page driven by Playwright MUST be the real repository frontend served from source. When a spec is exercised by the frontend only indirectly, drive the indirect real-user workflow that triggers it. If no such workflow exists, stop with Gate Failure Reporting and request scope re-adjustment per the Real-Frontend Rule — do not fabricate a UI.
   - Implement user-facing scenarios with `page` interactions that mimic real user behavior. Prefer `page.goto`, locator-based `click`, `fill`, `press`, `selectOption`, `setInputFiles`, and visible assertions over direct `request` calls.
   - Do not use Playwright `request` as the primary action path for scenarios that claim to verify a user's workflow. If API-level checks are still useful, keep them as supplementary assertions after the browser-driven flow has exercised the UI.
   - Validate request bodies, headers, response media types, stream event order, terminal events, and UI state.
   - Capture screenshots for every scenario checkpoint documented in the scenario file and store them under the stable result directory defined in [OUTPUT_CONTRACT.md](OUTPUT_CONTRACT.md).
   - Write Playwright test scripts and suite-specific Playwright config under `openspec/specs/<spec-name>/e2e/tests/`.
   - When collecting frontend coverage, add a suite-local Playwright fixture or coverage-only config that wraps user-facing `page` tests with `page.coverage.startJSCoverage({ resetOnNavigation: false })` and `page.coverage.startCSSCoverage({ resetOnNavigation: false })`, then writes raw coverage JSON under `e2e/results/frontend-coverage/raw/`.
   - Use Monocart Coverage Reports to merge raw frontend coverage into `e2e/results/frontend-coverage/monocart-report/index.html` when Node tooling is available. If `monocart-coverage-reports` is absent, install it with the relevant package manager or use `npm install --prefix <suite-tool-dir> --no-save monocart-coverage-reports @playwright/test`.
   - Prefer source-mapped frontend coverage. If the existing frontend command serves a prebuilt/minified bundle and Monocart cannot map coverage back to source files, create a suite-local coverage frontend build:
     - For Vite, add or override config so `build.sourcemap` is `true` for the E2E coverage build.
     - Build or serve a coverage frontend from repository source using a suite-local local command.
     - Point the E2E gateway/backend configuration to that source-built coverage frontend service when the app architecture requires it.
     - Re-run Playwright coverage and Monocart so report rows can reference original frontend files/components where possible.
   - Use prebuilt bundle/V8-only frontend coverage only as a fallback. If fallback is used, mark it as `bundle-level supporting evidence`, explain why sourcemaps could not be produced, and avoid presenting guessed source file percentages as exact.
   - Name screenshots so they remain traceable from scenario documents and useful to manuals, for example `<project>-<suite-slug>-NN-<checkpoint-name>.png`.
   - Prefer full-page or stable region screenshots that show enough surrounding UI for a user manual. Hide or avoid secrets, tokens, and irrelevant developer panels.
   - Prefer scoped locators over broad text selectors when labels repeat.
   - Reuse existing fixture helpers within the suite before adding new helpers.
   - Step checklist:
     - [ ] Playwright tests map back to the already-created scenario documents.
     - [ ] Playwright tests and suite-specific config are under `openspec/specs/<spec-name>/e2e/tests/`.
     - [ ] Every user-facing scenario is driven through browser UI actions a real user can perform.
     - [ ] Tests run against the hybrid runtime: Dockerized infrastructure plus source-run app services.
     - [ ] Playwright route stubs do not replace in-repository backend or gateway behavior that the scenario claims to verify.
     - [ ] The page under test is the real repository frontend served from source; no synthetic tester HTML or developer-only page is injected via `page.route()`, `page.setContent()`, or `file://`.
     - [ ] Direct `request` calls are limited to setup, teardown, health checks, or supplementary non-user-facing assertions.
     - [ ] Request bodies, headers, response media types, stream order, terminal events, and UI state are asserted where relevant.
     - [ ] Each documented screenshot checkpoint has a corresponding screenshot capture in the Playwright code.
     - [ ] Reports, artifacts, and screenshots are configured for the canonical result paths.
     - [ ] Frontend coverage raw JSON and Monocart report paths are configured when frontend coverage is attempted.
     - [ ] Source-mapped frontend coverage was attempted before falling back to bundle-level V8 coverage.

7. **Validate**
   - Run Playwright tests against the documented hybrid runtime, not against ad hoc manually started services.
   - Run existing protocol/unit tests if available.
   - Re-run `docker compose -f docker-compose.e2e.yml config` after infrastructure compose changes.
   - Syntax-check helper shell scripts.
   - Run the E2E output validator against the spec-local suite root when available, for example `python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite <suite-slug> --suite-root openspec/specs/<spec-name>/e2e`.
   - The validator checks the Korean headings defined in [TEMPLATES.md](TEMPLATES.md); update the templates and validator together if the section contract changes.
   - Fix failures and rerun until deterministic checks pass.
   - Step checklist:
     - [ ] Playwright run passes or failures are documented with the blocking cause.
     - [ ] Screenshot files exist for every screenshot checkpoint listed in the scenario documents, or the missing checkpoint is reported as a gate failure.
     - [ ] Compose config validation has been re-run after infrastructure changes.
     - [ ] Source-run app startup commands still match the commands used for the Playwright run.
     - [ ] Relevant protocol/unit checks have been run when available.
     - [ ] Helper scripts syntax-check successfully when present.
     - [ ] E2E output validator passes for the suite.

8. **Run coverage gates and generate AI HTML report**
   - Run the OpenSpec traceability gate after Playwright execution. The gate must verify:
     - Every Requirement in `spec.md` is mapped in `00-coverage-matrix.md`.
     - Every important OpenSpec Scenario is mapped to an E2E scenario or explicitly listed as a known gap.
     - Every mapped Playwright test exists in `results.json` and has passed.
     - Every documented screenshot checkpoint has a matching screenshot file.
   - Use the skill-provided traceability script and write its output into `coverage-summary.json`, for example:
     `node .claude/skills/e2e-tests/scripts/evaluate_spec_coverage.mjs --suite <suite-slug> --suite-root openspec/specs/<spec-name>/e2e --spec openspec/specs/<spec-name>/spec.md --write-summary`
   - Run backend coverage for the owning service using the instrumented local source-run service path. For long-running servers, flush coverage before report generation, for example by sending `USR2` to a `coverage run --save-signal=USR2` Python process.
   - Generate backend XML and HTML coverage reports under `openspec/specs/<spec-name>/e2e/results/backend-coverage/`. For `coverage.py`, the expected minimum outputs are `backend-coverage/coverage.xml` and `backend-coverage/html/index.html`; if the HTML report is missing, rerun `coverage html -d <backend-coverage>/html` before judging coverage. Do not mark backend coverage `unavailable` without first attempting the instrumented backend run.
   - Run frontend coverage collection and generate the Monocart report under `openspec/specs/<spec-name>/e2e/results/frontend-coverage/monocart-report/`. Source-mapped frontend coverage is the target. If source maps are unavailable after a source-build/coverage-image attempt, use browser V8/bundle coverage as a supporting artifact and explain that the frontend percentage is bundle/path-level rather than original Vue/TS file-level. Do not mark frontend coverage `unavailable` without first attempting either source-mapped or bundle-level Playwright coverage collection.
   - Parse coverage results and filter them to the spec-relevant code surface recorded in `00-coverage-matrix.md`. Do not use unrelated repository-wide coverage percentages as the primary sufficiency judgment.
   - For each OpenSpec traceability item, backend file/function row, and frontend target row, compute a percentage-based coverage value. Use only rows that are directly related to the spec as the denominator; do not include unrelated files, broad shared utilities, generated code, or whole-repository totals unless the spec explicitly owns that behavior.
   - Compute axis percentages from applicable spec-relevant rows. Include at minimum `traceability.coveragePercent`, `backend.coveragePercent`, `frontend.coveragePercent`, and `overallCoveragePercent`.
   - Treat required backend/frontend coverage that was not collected as `0%` unless the HTML report explains an accepted non-blocking instrumentation blocker. For frontend coverage without source maps, report browser V8/bundle coverage as a supporting percentage and clearly label it as bundle/path-level rather than source-file-level.
   - Write `coverage-summary.json` with machine-readable data:
     - `suite`, `spec`, `generatedAt`
     - `traceability` metrics, `coveragePercent`, and `traceability.items[]` mapping each Requirement/Scenario to E2E scenario documents, Playwright test titles, result status, screenshot evidence, `coveragePercent`, and AI sufficiency notes
     - `backend.coveragePercent` and `backend.files[]` with file, functions/routes, requirement links, line/function/branch coverage, threshold, `coveragePercent`, and uncovered notes
     - `frontend.coveragePercent` and `frontend.files[]` with file/component/API call, requirement links, coverage evidence, source-map quality if available, V8/bundle fallback notes, `coveragePercent`, and limitations
     - `overallCoveragePercent`
     - `gaps[]` with uncovered branch/function, risk, and recommended test additions
     - `aiJudgment` with `sufficient`, `partial`, or `insufficient`
   - Generate `spec-coverage-report.html` from [COVERAGE_HTML_TEMPLATE.html](COVERAGE_HTML_TEMPLATE.html). The report must include a dedicated OpenSpec spec coverage section showing each Requirement/Scenario, mapped E2E scenario, Playwright test, screenshot/result evidence, percentage coverage, and AI sufficiency judgment. It must also explain in Korean which backend/frontend files and functions are related to this spec, how much coverage each has, why the coverage is sufficient or insufficient, and what to add if insufficient.
   - If a coverage tool is missing, install it using the appropriate package manager and record the command. If installation or instrumentation is impossible after an actual attempt, stop with Gate Failure Reporting unless the user explicitly accepts a report with unavailable coverage.
   - If the OpenSpec traceability gate or backend spec-relevant coverage gate fails, strengthen scenario docs/tests and rerun from the relevant earlier step. Frontend coverage may be a warning rather than a hard failure when source-level coverage is technically unavailable.
   - Step checklist:
     - [ ] OpenSpec traceability gate passed or exact missing mappings are documented.
     - [ ] The HTML report includes Requirement/Scenario-level OpenSpec coverage rows with evidence and AI judgment.
     - [ ] Backend coverage was collected for the owning backend service and includes `backend-coverage/coverage.xml` plus a human-readable HTML report.
     - [ ] Backend coverage was filtered to spec-relevant files/functions and judged against thresholds.
     - [ ] Frontend coverage was collected with source maps, or the failed/blocked source-map rebuild attempt is documented before fallback to bundle-level coverage.
     - [ ] Frontend coverage was reported with source-map quality clearly labeled.
     - [ ] Traceability, backend, and frontend sections include row-level percentages and axis-level percentages based only on spec-relevant rows.
     - [ ] `coverage-summary.json` exists under `e2e/results/`.
     - [ ] `spec-coverage-report.html` exists under `e2e/results/` and follows the HTML template.
     - [ ] AI judgment explains sufficiency, weak spots, and concrete additions for insufficient coverage.

9. **Document usage and capture lessons** (Phase F)
   - Write or update the suite execution summary using [TEMPLATES.md](TEMPLATES.md).
   - Include paths for scenarios, tests, Docker files, seed files, Sanity Check output, result JSON/HTML, screenshots, trace files, coverage XML/HTML reports, `coverage-summary.json`, `spec-coverage-report.html`, and validation command output.
   - Include a screenshot map that links each scenario checkpoint to its screenshot file and Korean manual caption.
   - Note in the execution summary which Phase E steps were run in parallel and which shared resources were respected.
   - **Capture project E2E lessons.** Review what cost time in this suite. If a non-obvious pitfall, workaround, or environment quirk cost more than ~30 minutes AND a future agent could not derive it from reading the code, add a memory under `openspec/e2e/memories/`:
     - Create the memory file with frontmatter `name`, `description`, `applies-to`, `last-verified`, and `metadata.type` (`pitfall`, `quirk`, `workaround`, `reference`).
     - Add a one-line pointer to `openspec/e2e/memories/index.md`.
     - Body should explain WHY the issue happens, WHAT works, and HOW TO APPLY (when triggered, when to skip).
     - Link related memories with `[[memory-name]]`.
     - Do NOT log routine choices, well-known commands, or facts derivable from `git log` / source code.
   - **Consider script promotion.** If you wrote a script for this suite (mock server, coverage helper, build wrapper) and a similar one already exists in another suite under `openspec/specs/*/e2e/scripts/`, promotion to `openspec/e2e/scripts/` becomes worthwhile. Rules:
     - Promote only after the second usage (a "rule of two").
     - Generalize only the parts that are truly common; suite-specific data (canned responses, fixture content, selectors) stay under the suite.
     - Update `openspec/e2e/scripts/README.md` with a one-line description and the suites that consume it.
     - When both call sites already work, refactor cautiously — do not break a passing suite to enable a shared script.
   - Step checklist:
     - [ ] Execution summary records the ordered workflow results, including Sanity Check and validation commands.
     - [ ] Execution summary records OpenSpec traceability, backend coverage, frontend coverage, and AI coverage judgment results.
     - [ ] Execution summary lists screenshot files by scenario and checkpoint for DOCX user manual reuse.
     - [ ] Execution summary notes which Phase E steps were parallelized and which shared resources were serialized.
     - [ ] Scenario docs, execution summary, tests, seed/stub files, reports, coverage outputs, and screenshots are written under `openspec/specs/<spec-name>/e2e/`.
     - [ ] Known gaps or user-required follow-ups are explicit.
     - [ ] If a non-obvious pitfall, workaround, or environment quirk cost >30 minutes, a memory has been added under `openspec/e2e/memories/` and `index.md` has been updated. If nothing met the bar, the execution summary states "no new memory captured" and why.
     - [ ] If a script written for this suite duplicates one in another suite, promotion to `openspec/e2e/scripts/` has been considered and either applied or explicitly deferred with a reason.
     - [ ] The execution guide can be followed from a clean checkout.

## Common Pitfalls

- Repeated UI labels: scope selectors, e.g. `.result-content .feedback-btn`, instead of plain `getByText()`.
- Streaming fixtures: include fields the UI store expects, such as `steps: []` for waiting states.
- Floating overlays: use button-specific classes; use `force: true` only when an overlay is intentionally nonessential to the assertion.
- Test data: keep rows small and focused on contract coverage, not realism.
- App Dockerization drift: do not Dockerize repository-owned frontend/backend/gateway services just to make E2E setup uniform. Use Docker for durable infrastructure and run app code from source.
- Ad hoc runtime drift: do not write Playwright specs against undocumented manually started services or host-installed databases. The root `docker-compose.e2e.yml` plus documented source-run commands are the executable environment contract.
- Scattered outputs: keep suite-specific E2E outputs under the source spec folder.
- Frontend-only runtime: do not call a suite E2E if only the UI starts while owned APIs are replaced by Playwright route stubs. Add the source-run gateway/backend and Dockerized data services, or stop and ask for the source spec to be regenerated around the owning backend/product capability.
- Over-stubbing: browser/API stubs are for nondeterministic external boundaries, not for bypassing services this repository owns.
- Request-only scenarios: do not replace a user workflow with Playwright `request` calls. A request-only check may be useful, but it is not enough for a user-facing E2E scenario or manual screenshot evidence.
- Fabricated tester pages: when a spec is a backend contract that the real frontend uses only indirectly (e.g., LLM gateway routes invoked from inside the chat UI), do NOT bridge the gap by serving a custom tester HTML via `page.route()` / `page.setContent()` / `file://` and clicking on that. Screenshots from a fabricated page are not real user evidence and have misled past DOCX manuals. Drive the indirect real-frontend workflow that triggers the backend behavior, or stop and request spec scope re-adjustment.
- Screenshot drift: do not list screenshot checkpoints in scenario documents unless the Playwright code captures them, and do not capture undocumented screenshots that cannot be mapped back to a scenario checkpoint.
- Manual-unfriendly screenshots: avoid tiny cropped states, transient overlays, developer consoles, secrets, and screenshots without enough context for a first-time user.
- Premature Playwright work: if the Dockerized infrastructure and source-run app services have not passed Sanity Check, pause test implementation and fix runtime setup first.
- Result drift: do not invent new report headings, ad hoc screenshot folders, or one-off output names. Update the templates first if the contract must change.
- Language drift: do not switch generated scenario docs, coverage rows, execution summaries, or copied OpenSpec prose back to English unless the user explicitly requests English output. Keep only exact contract identifiers in their original form.
- Coverage dilution: do not judge a focused feature spec by whole-repository coverage alone. Filter coverage to files/functions that implement or expose the spec, and explain shared utility coverage separately.
- Backend coverage flush: long-running API servers often do not write coverage data until stopped or signaled. Configure a deterministic flush path such as `coverage run --save-signal=USR2` for Python services.
- Frontend sourcemap limits: prebuilt/minified frontend bundles may only produce bundle-level V8 coverage. Mark it as supporting evidence unless source-level remapping is verified.
- Tool installation drift: do not assume coverage tools exist in the local service environment. Check first, install with the local package manager if needed, and document the exact command in the execution summary and HTML report.

## Gate Failure Reporting

When any step checklist cannot pass, stop the workflow and report:

- The current step number and name.
- The checklist item that failed.
- The repository evidence already checked.
- The reason it cannot be completed safely.
- The specific user decision, missing input, or repository fix needed before continuing.
