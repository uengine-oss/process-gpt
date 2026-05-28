# E2E Output Contract

Use this contract for every OpenSpec-driven Playwright E2E suite. Do not create alternate folder names or report shapes unless the user explicitly changes this contract. Write scenario documentation with the Korean section contract from `TEMPLATES.md`. Every suite must use the repository root `docker-compose.e2e.yml` as the shared executable infrastructure contract for stable dependencies such as databases, graph stores, caches, queues, object storage, and external-service mocks. Repository-owned frontend, backend, gateway, reverse proxy, worker, or BFF services must run directly from the working tree with documented local commands. API-backed suites must run the real in-repository frontend-to-gateway-to-backend or frontend-to-backend path. User-facing E2E scenarios must be browser-driven and must produce screenshot evidence that can be reused by the DOCX user manual workflow.

Every suite must be tied to repository-owned backend/product behavior. Do not create new suites for frontend-only specs or spec IDs whose service prefix or domain discriminator is an implementation layer such as `frontend`, `ui`, `react`, `page`, or `component`. The frontend is the user interaction surface; the tested capability must still have an owning backend/API/service/data contract.

## Suite Slug

Derive `<suite-slug>` from the covered OpenSpec feature spec. For project main specs named `<microservice>_<domain>-<feature>` or `<microservice>_<feature>`, preserve the exact lowercase spec folder name as the suite slug, for example `completion_agent-memory-chat`, `completion_mcp-server-config`, or `billing_invoice-search`.

- Reuse an existing suite slug when extending the same user-facing capability.
- Keep one suite focused on one coherent feature area.
- Preserve underscores and hyphens exactly as they appear in the source OpenSpec spec ID.
- Use lowercase kebab-case inside each segment. Do not convert `completion_agent-memory-chat` to `completion-agent-memory-chat`, because the underscore separates the service prefix from the domain discriminator.
- For specs generated from a microservice/service folder, the spec ID must start with the normalized service folder name followed by `_`. For example, `services/completion` maps to `completion_agent-memory-chat`, `completion_mcp-server-config`, or `completion_notification-push-delivery`, not `agent_memory-chat`, `mcp_server-config`, `notification_push-delivery`, or `completion-agent-memory-chat`.
- For single-domain services or services whose name already expresses the domain, avoid redundant domain repetition but keep the service-prefix underscore. For example, use `billing_invoice-search`, not `billing_billing-invoice-search`.
- Do not use suite slugs whose service prefix or domain discriminator is an implementation layer, such as `frontend_app-settings` or `frontend-text2sql-react`; regenerate the source spec around the owning backend/product capability first.
- Append new scenarios instead of renumbering or replacing existing ones.

## Canonical Directory Layout

From the repository root:

```text
openspec/
  specs/
    <spec-name>/
      spec.md
      e2e/
        seed_files/
          <fixture-or-seed-files>
        scenarios/
          00-coverage-matrix.md
          01-<scenario-slug>.md
          02-<scenario-slug>.md
          execution-summary.md
        tests/
          <suite-slug>.spec.mjs
          playwright.config.mjs
          global-setup.mjs
        results/
          results.json
          html-report/
            index.html
          spec-coverage-report.html
          coverage-summary.json
          backend-coverage/
            coverage.xml
            html/
              index.html
          frontend-coverage/
            playwright-results.json
            raw/
              <test-title-or-scenario>.json
            monocart-report/
              index.html
          screenshots/
            <project>-<suite-slug>-NN-<checkpoint-name>.png
          artifacts/
        scripts/
          <suite-specific-helper-scripts>
        docker/
          <suite-specific-compose-overrides-or-init-files>

docker-compose.e2e.yml
```

## File Naming Rules

- Coverage matrix: always `00-coverage-matrix.md`.
- Scenario documents: `NN-<scenario-slug>.md`, where `NN` starts at `01` and is never reused.
- Execution summary: always `execution-summary.md`.
- Playwright spec: `openspec/specs/<spec-name>/e2e/tests/<suite-slug>.spec.mjs`.
- Playwright config and suite-specific setup files: keep under `openspec/specs/<spec-name>/e2e/tests/` unless the repository already has a shared config that should be imported.
- Docker entrypoint: root `docker-compose.e2e.yml` is the shared infrastructure orchestration entrypoint; keep suite-specific seed data, init files, infrastructure compose overrides, local service startup helpers, and helper scripts under `openspec/specs/<spec-name>/e2e/`.
- Runtime graph: suites must include the source-run frontend, source-run owning backend services, source-run gateway or reverse proxy when used by the app, and Dockerized required data dependencies. Frontend-only runtime is not valid for new suites in this workflow.
- App service boundary: do not add Docker images, Dockerfiles, or Compose app services for repository-owned frontend/backend/gateway code solely for E2E. Use local source commands unless the user explicitly approves an app-container exception because no local source-run command exists.

## Result Directory Rules

Configure Playwright so all generated files land under `openspec/specs/<spec-name>/e2e/results/`.

Required result paths:

- JSON reporter: `results.json`.
- HTML reporter: `html-report/index.html`.
- Playwright output artifacts: `artifacts/`.
- Intentional screenshots: `screenshots/`.

Coverage result paths:

- AI-written spec coverage report: `spec-coverage-report.html`.
- Machine-readable AI/spec coverage summary: `coverage-summary.json`.
- Backend coverage report: `backend-coverage/coverage.xml` plus `backend-coverage/html/index.html` when backend coverage can be collected. Producing only `coverage.xml` is not complete enough for this workflow because reviewers need a browsable report.
- Frontend coverage report: `frontend-coverage/monocart-report/index.html` plus raw Playwright coverage JSON under `frontend-coverage/raw/` when browser coverage can be collected.
- Frontend coverage Playwright result JSON: `frontend-coverage/playwright-results.json` when a coverage-instrumented Playwright pass is run separately from the canonical `results.json`.
- Suite-specific coverage compose overrides, coverage fixtures, and report-generation scripts belong under `openspec/specs/<spec-name>/e2e/docker/` or `openspec/specs/<spec-name>/e2e/scripts/`, not in repository-global scratch folders.

All suites must use the spec-local `e2e/results/` directory.

## Spec-Relevant Coverage Rules

Coverage gates must be scoped to the code surface that implements or directly exposes the OpenSpec capability. Do not judge a feature E2E suite by whole-repository coverage alone.

- The coverage matrix must identify spec-relevant backend files/functions and frontend files/functions/components before coverage is judged.
- Backend coverage is required for API-backed suites. It may be marked unavailable only after an instrumented backend run was actually attempted and failed for a documented environmental reason. Otherwise stop with Gate Failure Reporting instead of producing a final coverage report.
- Frontend coverage is required for user-facing browser suites. Source-mapped frontend coverage must be attempted first when repository source is available. Bundle-level V8 coverage may be used as a supporting fallback only after source-map rebuild/instrumentation was attempted or proven impossible.
- Prefer function/file-level thresholds for spec-relevant files, for example backend route/service/client files, over broad service-wide thresholds that are diluted by unrelated shared modules.
- Treat shared infrastructure files, generated files, database adapters, and broad utility modules as supporting evidence unless the spec specifically owns their behavior.
- The AI coverage judgment must explain whether coverage is sufficient for the spec, cite uncovered relevant branches/functions, and recommend concrete scenario/test additions when coverage is insufficient.
- Source-mapped frontend coverage is the target. If the running frontend command serves a minified bundle without sourcemaps, first attempt a suite-specific source-built coverage frontend command or build wrapper with sourcemaps enabled. If source-map generation is impossible after an actual attempt, use browser V8/bundle coverage as a supporting artifact and judge frontend coverage by whether relevant user-facing flows produced raw coverage data and exercised the expected UI/API call path.
- Every coverage row in `coverage-summary.json` and `spec-coverage-report.html` must include a percentage-based coverage result. Compute spec, backend, and frontend percentages only from the Requirement/Scenario rows or code rows that are directly related to the spec. Do not include unrelated files, broad shared utilities, generated code, or whole-repository totals in the denominator unless the spec explicitly owns that behavior.
- Compute each axis percentage from applicable rows. For traceability, use covered Requirement/Scenario/Test/Screenshot rows. For backend, use only spec-relevant backend files/functions/routes. For frontend, use only spec-relevant frontend files/components/API-call paths or, when source maps are unavailable, the relevant browser V8/bundle coverage artifact. Exclude explicitly non-applicable rows from the denominator, but treat required coverage that was not collected as `0%` unless the report explains and accepts the blocker as non-blocking.

## Screenshot Evidence Rules

Screenshots are first-class E2E outputs because they feed later user manual generation.

- Every user-facing scenario document must list screenshot checkpoints in its `산출물` section.
- Each listed checkpoint must have a matching screenshot file under `openspec/specs/<spec-name>/e2e/results/screenshots/`.
- Use stable names that map back to scenario IDs and checkpoints, preferably `<project>-<suite-slug>-NN-<checkpoint-name>.png`.
- Capture user-relevant UI states, such as first screen, completed input, submitted/running state, progress, clarification needed, cache/repeated-result state, empty result, error message, cancellation, feedback submitted, and final result.
- Screenshots should show enough surrounding UI to be understandable in a user manual and must not expose secrets, tokens, developer consoles, or irrelevant internal tooling.
- Request-only or protocol-only checks do not satisfy screenshot evidence for a user-facing scenario.

## Incremental Update Rules

When adding coverage from another spec:

1. Read the existing `00-coverage-matrix.md`.
2. Add rows for new Requirements and Scenarios.
3. Reuse existing scenarios when they already verify the same user-visible behavior.
4. Add new scenario files only for behavior not already covered.
5. Do not renumber existing scenario files.
6. Update `execution-summary.md` with the latest run and known gaps.

## Validation Rules

Before completion, the suite must satisfy:

- Every scenario file listed in `00-coverage-matrix.md` exists.
- Every scenario file has the required Korean headings from `TEMPLATES.md`.
- For microservice/service-backed specs, the suite slug starts with the service folder name followed by `_`.
- Cross-domain specs include a domain discriminator, while single-domain/domain-expressive specs avoid redundant domain repetition and keep the `<microservice>_` prefix.
- Scenario documents, seed/stub files, Playwright tests, execution summaries, results, artifacts, and screenshots are under `openspec/specs/<spec-name>/e2e/`.
- Every user-facing scenario procedure is driven through browser UI interactions rather than direct Playwright `request` calls.
- Every screenshot checkpoint listed in scenario documents has a matching screenshot file, or the missing screenshot is documented as a blocking gap.
- Root `docker-compose.e2e.yml` exists and includes the minimal infrastructure dependencies needed by the suite.
- Repository-owned frontend, owning backend services, gateway or reverse proxy when used by the app, and workers/BFFs run from source using documented commands or suite-local startup helpers.
- Compose includes required data dependencies and stable infrastructure only, unless a user-approved app-container exception is documented. It must not replace owned services with Playwright route stubs.
- `docker compose -f docker-compose.e2e.yml config` passes from the repository root.
- The infrastructure containers have been started with `docker compose -f docker-compose.e2e.yml up -d` before Playwright tests are written or run. Add `--build` only when infrastructure images or suite-specific infrastructure overrides require it.
- A Sanity Check verifies container health, source-run app process readiness, required migrations/seeds, frontend load, and at least one real frontend-to-gateway-to-backend or frontend-to-backend route through the hybrid runtime for API-backed suites.
- The Playwright spec path exists.
- If results were generated, `results.json` and `html-report/index.html` are under `openspec/specs/<spec-name>/e2e/results/`.
- OpenSpec traceability coverage can be evaluated with `node .claude/skills/e2e-tests/scripts/evaluate_spec_coverage.mjs --suite <suite-slug> --suite-root openspec/specs/<spec-name>/e2e --spec openspec/specs/<spec-name>/spec.md --write-summary`.
- If backend coverage was generated, both `backend-coverage/coverage.xml` and `backend-coverage/html/index.html` are under `openspec/specs/<spec-name>/e2e/results/`. Missing HTML is a validation failure for coverage reporting.
- If frontend coverage was generated, raw coverage data and a Monocart/browser-readable report are under `frontend-coverage/`, and the report states whether coverage is source-mapped or bundle-level. Missing raw data is a validation failure for frontend coverage reporting.
- If coverage was generated, `spec-coverage-report.html`, `coverage-summary.json`, backend coverage outputs, and frontend coverage outputs are under `openspec/specs/<spec-name>/e2e/results/`.
- `execution-summary.md` exists once the suite has been run or handed off for execution.
