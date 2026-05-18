# E2E Output Contract

Use this contract for every OpenSpec-driven Playwright E2E suite. Do not create alternate folder names or report shapes unless the user explicitly changes this contract. Write scenario documentation with the Korean section contract from `TEMPLATES.md`. Every suite must use the repository root `docker-compose.e2e.yml` as the executable E2E environment contract, and API-backed suites must run the real in-repository frontend-to-gateway-to-backend or frontend-to-backend path. User-facing E2E scenarios must be browser-driven and must produce screenshot evidence that can be reused by the DOCX user manual workflow.

## Suite Slug

Derive a lowercase kebab-case `<suite-slug>` from the covered feature or spec group, for example `text2sql`, `upload-flow`, or `graph-navigation`.

- Reuse an existing suite slug when extending the same user-facing capability.
- Keep one suite focused on one coherent feature area.
- Append new scenarios instead of renumbering or replacing existing ones.

## Canonical Directory Layout

From the repository root:

```text
e2e/
  <suite-slug>/
    seed_files/
      <fixture-or-seed-files>
    e2e_senarios/
      <suite-slug>/
        00-coverage-matrix.md
        01-<scenario-slug>.md
        02-<scenario-slug>.md
        execution-summary.md
    e2e-results/
      <suite-slug>/
        results.json
        html-report/
          index.html
        screenshots/
          <project>-<test-title>-<checkpoint>.png
        artifacts/

docker-compose.e2e.yml

<frontend-folder>/
  e2e/
    <suite-slug>/
      <suite-slug>.spec.mjs
```

Keep the existing spelling `e2e_senarios` for compatibility with the current repository outputs.

## File Naming Rules

- Coverage matrix: always `00-coverage-matrix.md`.
- Scenario documents: `NN-<scenario-slug>.md`, where `NN` starts at `01` and is never reused.
- Execution summary: always `execution-summary.md`.
- Playwright spec: prefer `<frontend-folder>/e2e/<suite-slug>/<suite-slug>.spec.mjs`.
- Docker entrypoint: root `docker-compose.e2e.yml` is required for every suite; keep suite-specific seed data under `e2e/<suite-slug>/seed_files/`.
- Service graph: API-backed suites must include the frontend, owning backend services, gateway or reverse proxy when used by the app, and required data dependencies. Frontend-only Compose is allowed only for explicitly static UI scenarios with no API-backed requirement.

## Result Directory Rules

Configure Playwright so all generated files land under `e2e/<suite-slug>/e2e-results/<suite-slug>/`.

Required result paths:

- JSON reporter: `results.json`.
- HTML reporter: `html-report/index.html`.
- Playwright output artifacts: `artifacts/`.
- Intentional screenshots: `screenshots/`.

If an existing suite uses a flat result directory, preserve it only while updating legacy tests. New suites and newly reorganized suites must use the suite slug subdirectory.

## Screenshot Evidence Rules

Screenshots are first-class E2E outputs because they feed later user manual generation.

- Every user-facing scenario document must list screenshot checkpoints in its `산출물` section.
- Each listed checkpoint must have a matching screenshot file under `e2e/<suite-slug>/e2e-results/<suite-slug>/screenshots/`.
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
- Every user-facing scenario procedure is driven through browser UI interactions rather than direct Playwright `request` calls.
- Every screenshot checkpoint listed in scenario documents has a matching screenshot file, or the missing screenshot is documented as a blocking gap.
- Root `docker-compose.e2e.yml` exists and includes the minimal real service graph needed by the suite.
- For API-backed suites, Compose includes frontend, owning backend services, gateway or reverse proxy when used by the app, and required data dependencies. It must not replace owned services with Playwright route stubs.
- `docker compose -f docker-compose.e2e.yml config` passes from the repository root.
- The Docker stack has been started with `docker compose -f docker-compose.e2e.yml up -d --build` before Playwright tests are written or run.
- A Sanity Check verifies container health, endpoint readiness, required migrations/seeds, frontend load, and at least one real frontend-to-gateway-to-backend or frontend-to-backend route through the Docker Compose stack for API-backed suites.
- The Playwright spec path exists.
- If results were generated, `results.json` and `html-report/index.html` are under the suite result directory.
- `execution-summary.md` exists once the suite has been run or handed off for execution.
