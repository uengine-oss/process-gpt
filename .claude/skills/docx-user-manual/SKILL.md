---
name: docx-user-manual
description: Create polished Korean DOCX end-user manuals from product specs, UI behavior references, scenario notes, and screenshot artifacts. Use when the user asks to generate a Word user guide, usage manual, user manual, DOCX manual, or beginner-friendly product documentation from spec-driven evidence.
argument-hint: "<spec-name>"
arguments: [spec_name]
disable-model-invocation: true
license: MIT
compatibility: Requires Python with python-docx and Pillow, or an equivalent DOCX generation tool. Prefer the repository's existing DOCX skill/tooling when available.
metadata:
  author: project
  version: "1.0"
---

# Evidence-Driven DOCX End-User Manual

Create a professional `.docx` user manual from product specs, scenario documents, UI behavior references, execution notes, and screenshots.

**Input**: One or more OpenSpec `spec.md` files, scenario documents, UI behavior references, screenshot artifacts, related app/service folders, and the spec-local output directory `openspec/specs/<spec-name>/docs/`.

**Direct command input**: When invoked as `/docx-user-manual <spec-name>`, use `$spec_name` as the exact OpenSpec folder name. Project feature specs MUST use the service-prefixed OpenSpec ID format: `<microservice>_<domain>-<feature>` for cross-domain services or `<microservice>_<feature>` for single-domain/domain-expressive services (for example `completion_agent-memory-chat` or `billing_invoice-search`). If `$spec_name` is empty, ask for the spec folder name. Find `openspec/specs/<spec-name>/spec.md`, read it and related artifacts, then find related E2E scenario documents, test code, result files, execution summaries, and screenshots under `openspec/specs/<spec-name>/e2e/` before generating the manual. If the folder or E2E evidence is missing or ambiguous, report what was found and ask for the missing selection instead of guessing.

**Feature Traceability Rule**: For service-prefixed specs, use the exact spec folder name as the E2E suite slug and manual output slug. For example, `openspec/specs/completion_agent-memory-chat/spec.md` maps to `openspec/specs/completion_agent-memory-chat/e2e/` and `openspec/specs/completion_agent-memory-chat/docs/completion_agent-memory-chat-user-manual.docx`. Do not rewrite underscores or hyphens because they preserve the service/domain/feature boundary.

**Spec-Local Output Rule**: Generated manuals MUST be colocated with the source spec. For `openspec/specs/<spec-name>/spec.md`, create or update `openspec/specs/<spec-name>/docs/` and put both the generation script and the `.docx` output there. Do not create manual outputs under root `docs/`.

**Microservice Prefix Consistency Rule**: If the source spec, E2E evidence, or related service path shows that the feature belongs to a specific microservice/service folder, the spec ID must start with that service name followed by `_`. For example, manuals for `services/completion` features should be based on specs such as `completion_agent-memory-chat`, `completion_mcp-server-config`, or `completion_notification-push-delivery`. If the source spec replaces the service prefix with a discovered subdomain or resource name, such as `agent_memory-chat`, `mcp_server-config`, or `notification_push-delivery`, or if it drops the underscore boundary, such as `agent-feedback-feedback-processing` for `services/agent-feedback`, stop and report that the OpenSpec/E2E evidence should be regenerated or renamed around the service-name prefix first.

**Backend-Associated Evidence Rule**: Generate manuals only for specs and E2E evidence tied to repository-owned backend/product behavior. Do not generate a manual from frontend-only specs or spec IDs whose service prefix or domain discriminator is an implementation layer such as `frontend`, `ui`, `react`, `page`, or `component`. If the source spec is frontend-only, stop and report that the spec/E2E evidence should be regenerated around the owning backend/product capability first.

**Core Rule**: The DOCX must read like a product manual for first-time end users. Use verification artifacts only as evidence. Do not copy their structure, headings, commands, internal identifiers, assertions, routes, fixtures, or pass/fail summaries into the user-facing document.

**Korean Writing Rule**: Generate the DOCX manual in Korean by default. Use Korean for the document title, section headings, body text, captions, table headers, workflow names, error guidance, FAQ, and procedure text. If source OpenSpec specs, E2E documents, execution summaries, or screenshots contain English prose, translate the user-facing meaning into Korean instead of copying it. Keep product names, UI labels, paths, API routes, field names, event names, enum values, SQL keywords, and identifiers in their original form only when they are visible to users or required for accuracy. Use another language only when the user explicitly requests it.

**Style Consistency Rule**: Use [STYLE_REFERENCE.py](STYLE_REFERENCE.py) as the default visual style baseline. It is a compressed copy of the previous polished manual generator with one representative user flow. Before writing or rewriting a generation script, read it and reuse its document structure, helper functions, spacing, table style, cover layout, heading colors, font choices, caption style, and page footer approach unless the user asks for a new design.

**Workflow Gate Rule**: Execute the workflow strictly in order. Do not draft, generate, validate, or report a later-step output until the current step checklist passes. If a checklist item cannot pass because evidence is missing, screenshots are incomplete, product behavior is ambiguous, or the DOCX tooling fails, stop at that step and tell the user what failed, what evidence was checked, and what input or fix is needed.

## End-User Only Rule

The generated manual body must avoid development and verification vocabulary unless the user explicitly asks for an operator or developer appendix.

Do not expose these terms in the DOCX body:

- E2E, test, 테스트, smoke, Playwright, stub, fixture, assert, coverage, pass/fail, report path.
- API contract, endpoint, route, request body, response body, status code, header, NDJSON, SSE, JSON line.
- Internal state or field names such as `conversation_state`, `session_state`, `feedback_required`, `from_cache`, `max_tool_calls`, `max_sql_seconds`, `pipeline_stage`, `completed`, `needs_user_input`.
- Docker, seed data, healthcheck, service wiring, command output, unless the user explicitly requests an administrator guide.

Translate them into user-visible behavior instead:

| Evidence term | Manual wording |
| --- | --- |
| E2E scenario | 사용자 작업 흐름 |
| Preconditions | 사용 전 확인 |
| Steps | 따라 하기 |
| Expected Results | 화면에서 확인할 내용 |
| cache hit | 이전과 같은 질문의 빠른 결과 확인 |
| terminal event | 처리 완료, 추가 입력 요청, 또는 오류 표시 |
| validation/assertion | 화면에서 확인할 내용 |
| fixture/stub/test data | 필요한 경우에만 예시 화면 기준 |
| API field | 화면 항목 또는 사용자 옵션 |

## Required References

Before writing the manual, read all relevant inputs the user provides:

- OpenSpec `spec.md` files: extract purpose, requirements, scenarios, public fields, status values, and user-visible labels.
- If OpenSpec Requirement/Scenario text is in English, translate its user-facing meaning into Korean for the manual while preserving exact identifiers.
- Scenario and coverage documents under `openspec/specs/<spec-name>/e2e/scenarios/`: use them to identify which user behaviors must be covered, not as the manual outline.
- UI automation or execution references: confirm exact user actions, visible labels, screenshots, and observable screen outcomes. Do not copy assertions, commands, or internal data.
- Execution summaries/results: use them only to understand available screenshots and known evidence quality. Do not include run status, pass/fail counts, commands, report paths, or known test gaps in an end-user manual.
- Screenshot directory under `openspec/specs/<spec-name>/e2e/results/screenshots/`: insert meaningful screenshots at the matching workflow sections.
- Existing DOCX generation guidance or scripts in the repo, especially any `docx` skill or helper script.
- [STYLE_REFERENCE.py](STYLE_REFERENCE.py): bundled style reference copied and compressed from the previous polished manual generator. Use it as the canonical layout, helper, table, caption, cover, and footer baseline.

## Output Contract

Write generated manuals under the source spec folder:

```text
openspec/specs/<spec-name>/
  docs/
    <suite-or-feature>-user-manual.docx
    generate_<suite-or-feature>_user_manual.py
```

For service-prefixed specs, `<suite-or-feature>` should be the exact spec folder name, for example `completion_agent-memory-chat` or `billing_invoice-search`. Keep the generation script when practical so the document can be regenerated after specs, screenshots, or E2E results change.

## Required Manual Structure

The DOCX must include these sections in this order unless the user explicitly asks otherwise:

1. **표지**
   - 서비스명, 문서 제목, 문서 버전, 작성일, 작성자 또는 조직명
2. **문서 정보 및 변경 이력**
   - 문서 버전, 변경일, 변경 내용, 작성자, 검토자
3. **목차**
   - Word TOC field if the DOCX library supports it; otherwise a generated section list
4. **개요**
   - 서비스 목적, 매뉴얼 목적, 기능 범위
5. **대상 사용자**
   - 일반 사용자, 분석 사용자, 검토자 등 제품 사용자 관점의 사용 목적
6. **사용 전 확인 사항**
   - 계정, 권한, 접속 URL, 브라우저, 데이터소스, 질문 준비 사항
7. **시작하기**
   - 접속, 로그인 또는 화면 진입, 최초 화면, 기본 설정, 질문 전송 절차
8. **화면 구성**
   - 주요 메뉴, 버튼, 입력 필드, 진행 영역, 결과 영역, 히스토리, 알림/오류 영역
9. **주요 사용 흐름**
   - 각 흐름은 "이럴 때 사용합니다", "사용 전 확인", "따라 하기", "화면에서 확인할 내용" 형식으로 작성
   - Scenario IDs, test titles, source paths, commands, assertions, and internal event names must not appear
10. **화면 항목 및 옵션 설명**
    - 화면에 보이는 입력값, 필수 여부, 형식, 기본값, 예시, 사용자에게 의미 있는 유효성 조건
11. **결과 확인**
    - 완료 후 확인할 화면 상태, 메시지, 결과 표, 저장/히스토리 여부, 다음 질문 가능 여부
12. **오류 및 예외 상황**
    - 사용자에게 보이는 문제 상황, 원인, 해결 방법
13. **권한 및 역할별 기능 차이**
    - 제품 사용자 역할별 접근 메뉴, 수행 작업, 제한 기능
14. **FAQ / 자주 묻는 질문**
    - 초보 사용자가 막힐 가능성이 높은 질문과 짧은 답변
15. **효과적인 질문 작성 팁**
    - 좋은 질문 예시, 조건 좁히기, 결과가 없을 때 다시 묻는 방법

## Workflow

1. **Collect evidence**
   - Read all source specs before drafting.
   - For service-prefixed source specs, preserve the exact spec ID as the suite/manual evidence key.
   - If source evidence ties the feature to a microservice/service folder, confirm the spec ID starts with that service folder name followed by `_`.
   - If the service spans multiple domains, confirm the spec ID includes a domain discriminator after the service prefix. If the service is single-domain or domain-expressive, confirm the spec ID keeps the `<microservice>_` prefix and does not redundantly repeat the same domain.
   - Confirm the source spec service prefix and domain discriminator are backend/product capability terms, not `frontend`, `ui`, `react`, `page`, or `component`.
   - Confirm related E2E evidence exercised the real frontend-to-gateway/backend path, not frontend-only behavior.
   - Read the coverage/scenario documents to identify user-visible behaviors.
   - Read UI automation references only to confirm exact labels, actions, and screenshots.
   - Read execution summaries only to understand which screenshot artifacts are available.
   - List screenshot files and map each screenshot to a scenario checkpoint.
   - Locate E2E evidence under the source spec folder, for example `openspec/specs/completion_agent-memory-chat/e2e/` for `openspec/specs/completion_agent-memory-chat/spec.md`.
   - Read [STYLE_REFERENCE.py](STYLE_REFERENCE.py) before choosing visual styles.
   - Step checklist:
     - [ ] Every provided or discoverable source spec has been read.
     - [ ] English prose from source specs or E2E evidence has been translated into Korean user-facing wording, except exact identifiers.
     - [ ] Service-prefixed spec IDs, E2E suite slugs, and manual output slugs are aligned exactly when present.
     - [ ] Manual output path is `openspec/specs/<spec-name>/docs/`.
     - [ ] Related E2E evidence has been searched under `openspec/specs/<spec-name>/e2e/`.
     - [ ] Microservice/service-backed specs start with the service-name prefix followed by `_`, not a discovered subdomain/resource name or `<microservice>-<feature>`.
     - [ ] Cross-domain specs include a domain discriminator, while single-domain/domain-expressive specs avoid redundant domain repetition and keep the `<microservice>_` prefix.
     - [ ] Source specs and E2E evidence are backend-associated and not frontend-only.
     - [ ] Related scenario, coverage, execution summary, result, and screenshot artifacts have been located or explicitly reported missing.
     - [ ] Screenshots are mapped to scenario checkpoints or marked as unavailable.
     - [ ] User-visible labels, actions, roles, states, and error messages are identified from evidence.
     - [ ] Bundled style reference [STYLE_REFERENCE.py](STYLE_REFERENCE.py) has been read.
     - [ ] Missing or ambiguous evidence has been resolved with repository evidence or reported to the user before outlining.

2. **Build the user-facing outline**
   - Use the required manual structure exactly.
   - Draft every user-facing title, heading, paragraph, caption, table header, and procedure in Korean.
   - Translate English OpenSpec/E2E scenario names and descriptions into Korean task names and guidance. Do not copy English prose into the manual body.
   - Rename technical scenario titles into user tasks, for example "cache hit" → "이전과 같은 질문 빠르게 확인하기".
   - Keep domain-specific examples only when they come from the source material. Do not add unrelated domain terminology.
   - Treat verification fixtures as examples, not as production promises, and do not label them as fixtures.
   - Remove operator/developer-only content unless explicitly requested.
   - Step checklist:
     - [ ] The outline contains every required manual section in the required order.
     - [ ] Every relevant source behavior is assigned to a user-facing workflow, screen explanation, result section, error section, FAQ, or tips section.
     - [ ] Technical scenario IDs, commands, assertions, internal routes, internal event names, and verification wording are excluded from the outline.
     - [ ] English source prose has not been copied into the outline; it has been converted to Korean user-facing wording.
     - [ ] All planned headings, workflow names, table titles, and captions are Korean unless the user requested another language.
     - [ ] No DOCX generation has started before the outline is complete.

3. **Map screenshots**
   - Insert screenshots near the workflow step they demonstrate, not only in an appendix.
   - Include a short Korean caption for every screenshot.
   - Prefer these placements:
     - First progress screenshot → **화면 구성** or the first normal-use scenario.
     - Final result screenshot → normal completion scenario and **결과 확인**.
     - Cache screenshot → cache/repeated-question scenario.
     - User-input screenshot → clarification or session-resume scenario.
     - Error screenshot → **오류 및 예외 상황** or error-handling scenario.
     - Empty-result screenshot → empty-result workflow or **결과 확인**.
     - Cancel/pause screenshot → cancellation/pause/resume workflow.
     - Feedback screenshot → quality feedback workflow.
     - Operator or environment screenshots → omit from an end-user manual unless explicitly requested.
   - If a screenshot mentioned by a scenario is missing, state that the artifact was not found instead of inventing one.
   - Step checklist:
     - [ ] Every available screenshot is accepted, rejected, or deferred with a reason.
     - [ ] Every inserted screenshot has a target manual section, nearby workflow step, and Korean caption.
     - [ ] Required workflow screenshots such as first screen, progress, final result, error, empty result, cancellation, feedback, or repeated-question states are mapped when available.
     - [ ] Missing scenario-mentioned screenshots are recorded as gaps instead of invented.
     - [ ] Screenshot count and placement plan are known before DOCX generation.

4. **Generate DOCX**
   - Prefer a script using `python-docx` plus Pillow when available. Use another DOCX generator only if the repo already standardizes on it.
   - Start from [STYLE_REFERENCE.py](STYLE_REFERENCE.py). Preserve its helper pattern for cover page, `set_run_font`, `set_cell_text`, table header shading, heading styling, numbered steps, screenshot insertion, captions, TOC field, footer page numbers, and image sizing.
   - Set Korean-capable fonts such as `Malgun Gothic` for body and headings.
   - Use real Word headings so the TOC can be updated in Word.
   - Use tables for change history, roles, screen areas, field descriptions, error handling, permissions, related documents, and status values.
   - Use numbered lists for procedures and bullet lists for conditions or checks.
   - Ensure every separate procedure list restarts at 1. With `python-docx`, the built-in `List Number` style can continue numbering across sections; create a fresh numbering definition or write explicit `1.`, `2.`, `3.` prefixes for each procedure list.
   - Add page numbers in the footer when supported.
   - Keep image width within the page margins and preserve aspect ratio.
   - Write the generation script and `.docx` output under `openspec/specs/<spec-name>/docs/`.
   - Step checklist:
     - [ ] The generation approach and spec-local output path are selected before writing files.
     - [ ] [STYLE_REFERENCE.py](STYLE_REFERENCE.py) has been mirrored for layout, colors, fonts, tables, captions, and footer unless intentionally changed.
     - [ ] The DOCX includes every required section in order.
     - [ ] Korean-capable fonts, real headings, tables, page layout, captions, and image sizing are applied.
     - [ ] Every procedure list starts at 1 and does not inherit numbering from another section.
     - [ ] The regeneration script is created or updated when practical.
     - [ ] The regeneration script and DOCX output are under `openspec/specs/<spec-name>/docs/`.

5. **Validate**
   - Open or parse the generated DOCX with the available tool/library to confirm it is readable.
   - Count headings, tables, and inline images; compare image count with the screenshot map.
   - Check that every required section is present.
   - Check that each relevant behavior is represented as a user workflow or user-facing guidance.
   - Check that each "따라 하기" or procedure block starts at 1 and does not continue numbering from a previous section.
   - Extract DOCX text and scan for forbidden development/verification terms from the End-User Only Rule.
   - Run lints for any generation script you create or modify.
   - Step checklist:
     - [ ] The generated DOCX is readable.
     - [ ] Visual structure is consistent with the selected previous manual reference: cover layout, margins, heading hierarchy, table appearance, captions, image width, and footer.
     - [ ] Required sections, heading order, tables, screenshots, and captions match the outline and screenshot map.
     - [ ] Every relevant behavior is represented as a user workflow or user-facing guidance.
     - [ ] Procedure numbering restarts correctly in each procedure block.
     - [ ] Forbidden development or verification terms are absent from the DOCX body unless explicitly requested.
     - [ ] The generation script has no new lint or syntax errors.

6. **Report completion**
   - Provide the DOCX path and generation script path.
   - Summarize validation results: readable DOCX, number of headings/tables/images, and any missing screenshots or known gaps.
   - Answer the user's checklist directly.
   - Step checklist:
     - [ ] DOCX path and regeneration script path are reported.
     - [ ] Validation results include readability, section coverage, heading/table/image counts, and forbidden-term scan outcome.
     - [ ] Missing screenshots, evidence gaps, or manual limitations are clearly stated.
     - [ ] The final response does not expose development-only details in a way that would be copied into the user manual.

## Evidence Conversion Rules

Convert scenario documents into manual content using this mapping:

| Source heading | Manual content |
| --- | --- |
| Purpose | 이럴 때 사용합니다 |
| Preconditions | 사용 전 확인 |
| Steps | 따라 하기 |
| Expected Results | 화면에서 확인할 내용 |
| Test Data And Stubs | Usually omit; if needed, convert to neutral examples |
| Covered Requirements | Internal traceability only; do not include in the DOCX body |
| Artifacts | Screenshot placement and user-facing caption |

Do not copy automation assertions verbatim into the manual. Translate assertions into visible outcomes, for example "expect final SQL visible" → "최종 SQL 영역이 표시됩니다."

## Recommended DOCX Quality Bar

- The manual should be useful without reading the specs or verification artifacts.
- The generated document should feel visually consistent with [STYLE_REFERENCE.py](STYLE_REFERENCE.py); avoid introducing a new visual language for the same product family.
- The first normal-use scenario should include a screenshot of progress and a screenshot of final results.
- Every inserted screenshot should have a caption and be referenced by nearby text.
- Error guidance should include cause and recovery action, not only the error message.
- Screen option tables should include required/optional status and default values when specified.
- Permissions should be conservative: mark features as "권한 필요" when the source does not prove every user can perform them.
- Do not include known verification gaps, command output, report paths, or implementation caveats in an end-user manual unless explicitly requested.
- Do not copy English prose from source specs, E2E documents, or execution notes into the user-facing manual. Translate the meaning to Korean and keep only exact identifiers unchanged.

## Style Reference

Use [STYLE_REFERENCE.py](STYLE_REFERENCE.py) as the style floor and helper pattern. Copy its proven helper functions and adapt only content, screenshot map, output paths, and feature-specific wording.

## Gate Failure Reporting

When any step checklist cannot pass, stop the workflow and report:

- The current step number and name.
- The checklist item that failed.
- The evidence, screenshots, scripts, or DOCX artifacts already checked.
- The reason it cannot be completed safely.
- The specific user decision, missing input, missing screenshot, or repository/tooling fix needed before continuing.
