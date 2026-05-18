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

**Language Rule**: Write planning documents and specs in Korean by default. Preserve exact public identifiers only when they are part of the contract: API paths and methods, request/response fields, event names, configuration keys, environment variables, SQL keywords, test IDs, and requirement IDs.

**Core Rule**: Specs MUST describe observable behavior, not implementation internals. Do not put internal function names, class names, private helper names, module paths, file paths, or line numbers in `openspec/specs/*/spec.md`.

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
   - Step checklist:
     - [ ] `openspec/config.yaml` has been read.
     - [ ] `TEMPLATES.md` has been read.
     - [ ] Every source folder exists and is in scope.
     - [ ] Existing main specs have been checked.
     - [ ] Blocking ambiguity has been resolved by evidence or user input.

2. **Explore observable behavior**
   - Inspect code broadly enough to understand user-visible and client-visible behavior.
   - Prefer public boundaries over internal call graphs: routes, commands, UI workflows, message/event contracts, jobs, persistence effects, configuration behavior, auth/permission checks, validation, error handling, and integration boundaries.
   - Collect evidence as internal notes while analyzing, but do not copy implementation references into final specs.
   - Treat tests, examples, docs, route declarations, schemas, migrations, and UI labels as contract evidence.
   - Step checklist:
     - [ ] Public/API/UI/CLI/job boundaries have been identified where present.
     - [ ] Inputs, outputs, state changes, errors, and permissions have been noted.
     - [ ] Tests/docs/examples were checked when present.
     - [ ] Internal-only helpers were filtered out unless they expose observable behavior.
     - [ ] No domain-specific assumption was introduced unless the code exposes it as a contract.

3. **Plan spec partitioning first**
   - Before writing specs, create `openspec/plannings/code-to-spec-<scope-slug>.md`.
   - Use the planning template in `TEMPLATES.md`.
   - Partition by capability and use case, not by package, class, component, or file.
   - Choose spec folder names in kebab-case that describe stable capabilities.
   - For each proposed spec folder, document:
     - capability purpose,
     - included use cases,
     - observable contracts to capture,
     - excluded implementation details,
     - source evidence categories,
     - open questions or risks.
   - Step checklist:
     - [ ] Planning file exists under `openspec/plannings/`.
     - [ ] Spec folders are capability-oriented and kebab-case.
     - [ ] Every source folder has at least one planned capability or an explicit exclusion reason.
     - [ ] Cross-cutting behavior is assigned to the smallest appropriate capability.
     - [ ] Planning avoids internal function/class/module summaries.

4. **Derive main specs incrementally**
   - For each planned spec folder, create or update `openspec/specs/<capability>/spec.md`.
   - Use the main spec template in `TEMPLATES.md`.
   - Main specs use `## Purpose` and `## Requirements`; do not use delta sections such as `ADDED Requirements`.
   - Each Requirement title must describe a user/client/operator capability.
   - Each Requirement body must use SHALL or MUST and define externally testable behavior.
   - Each Scenario must express observable preconditions, action, and outcome. Prefer `GIVEN`/`WHEN`/`THEN`; use exact public API fields/events only when they are part of the contract.
   - Merge with existing specs intelligently:
     - preserve unrelated requirements,
     - update overlapping requirements instead of duplicating them,
     - add scenarios when behavior is already covered by a requirement,
     - keep the operation idempotent.
   - Step checklist:
     - [ ] Each planned spec folder has a corresponding `spec.md` or a documented skip reason.
     - [ ] Requirements are implementation-independent behavior contracts.
     - [ ] Scenarios are externally verifiable.
     - [ ] Existing specs were preserved and merged, not blindly overwritten.
     - [ ] Public identifiers are exact where needed.

5. **Quality review and validation**
   - Re-read each created or updated spec as if it were used to implement the system from scratch.
   - Remove code-inventory language such as "function", "class", "module", "file", "line", "helper", "calls", "uses", unless it is a public contract term.
   - Check that every planned capability has useful requirements and scenarios rather than low-level implementation summaries.
   - Run OpenSpec validation if the CLI is available, preferably:
     ```bash
     openspec validate --strict
     ```
     If that command is not supported, run the closest repository-supported OpenSpec validation command and report it.
   - Step checklist:
     - [ ] Specs contain no internal function/class/module/file/line references.
     - [ ] Requirements can be tested from outside the implementation boundary.
     - [ ] Scenario outcomes are observable.
     - [ ] Planning and specs agree on folder names and capability scope.
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
- Framework layers such as controllers/services/repositories unless that layer is itself the public contract.
- Domain keyword matching that would not generalize to another domain.
- Internal algorithm steps that users or clients cannot observe.

## Spec Writing Guardrails

- Write from the perspective of "the system", "user", "client", "operator", or named public actor.
- Use implementation-neutral verbs: accepts, validates, returns, persists, emits, rejects, displays, records, resumes, cancels, retries.
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
