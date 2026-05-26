# E2E Output Contract

Use this contract for every OpenSpec-driven Playwright E2E suite. Do not create alternate folder names or report shapes unless the user explicitly changes this contract. Write scenario documentation with the Korean section contract from `TEMPLATES.md`. Every suite must use the repository root `docker-compose.e2e.yml` as the shared executable E2E environment contract when Docker orchestration is needed, and API-backed suites must run the real in-repository frontend-to-gateway-to-backend or frontend-to-backend path. User-facing E2E scenarios must be browser-driven and must produce screenshot evidence that can be reused by the DOCX user manual workflow.

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
- Docker entrypoint: root `docker-compose.e2e.yml` is the shared orchestration entrypoint when Docker is needed; keep suite-specific seed data, init files, compose overrides, and helper scripts under `openspec/specs/<spec-name>/e2e/`.
- Service graph: suites must include the frontend, owning backend services, gateway or reverse proxy when used by the app, and required data dependencies. Frontend-only Compose is not valid for new suites in this workflow.

## Result Directory Rules

Configure Playwright so all generated files land under `openspec/specs/<spec-name>/e2e/results/`.

Required result paths:

- JSON reporter: `results.json`.
- HTML reporter: `html-report/index.html`.
- Playwright output artifacts: `artifacts/`.
- Intentional screenshots: `screenshots/`.

All suites must use the spec-local `e2e/results/` directory.

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
- Root `docker-compose.e2e.yml` exists and includes the minimal real service graph needed by the suite.
- Compose includes frontend, owning backend services, gateway or reverse proxy when used by the app, and required data dependencies. It must not replace owned services with Playwright route stubs.
- `docker compose -f docker-compose.e2e.yml config` passes from the repository root.
- The Docker stack has been started with `docker compose -f docker-compose.e2e.yml up -d --build` before Playwright tests are written or run.
- A Sanity Check verifies container health, endpoint readiness, required migrations/seeds, frontend load, and at least one real frontend-to-gateway-to-backend or frontend-to-backend route through the Docker Compose stack for API-backed suites.
- The Playwright spec path exists.
- If results were generated, `results.json` and `html-report/index.html` are under `openspec/specs/<spec-name>/e2e/results/`.
- `execution-summary.md` exists once the suite has been run or handed off for execution.
