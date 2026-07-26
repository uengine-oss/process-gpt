# Strategy/Ontology feature demo — 2026-07-20

`strategy-features-demo.mp4` (~25s, screen-recorded with Playwright) drives the **real**
`StrategyBoard.vue`/`OntologyExplorer.vue` production components against the **real**
`services/strategy` backend (Apache AGE graph on Postgres) and a **real** OpenAI call —
nothing in the recording is mocked. It shows, in order:

1. An empty Strategy Board.
2. The new **AI 편집** chat panel: a single natural-language message —
   "고객 만족 전략을 만들고, 그 아래에 만족도라는 이름의 설문 기반 KPI를 목표 90점으로
   추가해줘" — creates a `고객 만족` strategy objective and a `만족도` (survey-based) KPI
   via `POST /api/strategy/chat` (Feature 1: chat-based strategy map editor).
3. The board updating live to show the new objective/KPI.
4. The KPI creation dialog with the new **외부 시스템 연동** (`external_source`) measure
   type selected, showing the URL/value-path fields (Feature 2: KPI → System of Record).
5. The Ontology Explorer (`/analytics/ontology`) showing the exact same `Strategy`→`KPI`
   graph nodes the chat just created, moments earlier — the same graph an ontology-driven
   agent (Feature 4) reads from.

## Features not shown on-screen (verified another way)

- **Feature 3 (survey collection, verification-only)** and **Feature 4 (ontology-driven
  agent)** are backend/API-only, so instead of a browser recording they were verified with
  real HTTP/DB round trips:
  - `openspec/specs/strategy_survey-dispatch/e2e/` — 11/11 PASS (dispatch → todolist
    workitem → REST response → KPI recompute), see `results.md`.
  - `services/strategy/app/ontology_agent/run_demo.py` — live run with a real
    `OPENAI_API_KEY`: the agent called `get_kpi_impact`, picked the top bottleneck
    resource, and called `notify_top_bottleneck`, which created a real `todolist` alert
    row (verified via direct SQL query afterward).

## Full test evidence (all run live against Postgres/AGE, not mocked)

- `services/strategy` unit tests: **98/98 passed** (`pytest tests/`).
- E2E suites (real HTTP against a live `uvicorn` server + live Postgres/AGE): all 6 suites
  green — `strategy_kpi-measurement` (13/13, includes the new `external_source` block),
  `strategy_survey-dispatch` (11/11, new), `strategy_strategy-map-graph` (20/20),
  `strategy_ontology-view` (16/16), `strategy_ontology-sync` (24/24),
  `strategy_impact-analysis` (21/21).
- Frontend: `vue-tsc --noEmit` clean (zero type errors) after the chat panel + KPI dialog
  changes.

## How the recording was made

A throwaway, login-free Vite entry (`services/frontend/demo-strategy.html` +
`src/demo-strategy-entry.ts` + `src/DemoStrategyApp.vue`, since removed) mounted the real
`StrategyBoard.vue`/`OntologyExplorer.vue` components directly (bypassing the app's
Supabase auth flow, which needs real login credentials this session intentionally avoided
touching) with `window.$tenantName` set to a scratch tenant, and the dev server's
`/strategy-service` proxy pointed at a locally running `services/strategy` instance.
Playwright (`chromium`, `recordVideo`) drove it and the `.webm` output was transcoded to
`.mp4` with ffmpeg. The scratch tenant's graph data was deleted afterward.

---

# Main toolbar + layout settings demo — 2026-07-20

`toolbar-layout-settings-demo.mp4` (~13s) drives the **real** production
`VerticalHeader.vue` / `FullLayout.vue` / `AccountSettings.vue` components — same
login-free-harness technique as above (see below), nothing mocked in what's shown. It
demonstrates two frontend navigation changes:

1. A new **Strategy Board** icon added to the main pill toolbar (`VerticalHeader.vue`'s
   `sidebarItems`), with its tooltip, and clicking it actually routes to `/strategy-board`.
2. The toolbar's settings (gear) button, which used to open a standalone Customizer
   drawer, now navigates to `/account-settings?tab=LayoutSettings` — landing directly on a
   new **레이아웃 설정** tab inside the existing tabbed account-settings dialog (the same
   `Customizer.vue` theme-color UI, now embedded as a tab instead of a separate drawer).
   The recording also switches to the **계정 설정** tab and back to confirm it's a real
   tab, not a modal.

## How this recording was made

Same technique as the strategy demo above: a throwaway, login-free Vite entry
(`services/frontend/demo-toolbar.html` + `src/demo-toolbar-main.ts`, since removed)
mounted the real app router (`src/router/index.ts`) with a minimal bootstrap (Pinia,
Vuetify, vue-i18n, no Supabase/Keycloak/IP-locale calls), pushed to `/todolist` so
`FullLayout.vue` renders with `VerticalHeader.vue` on top, and Playwright
(`chromium`, `recordVideo`) drove the interaction. Verified via `vue-tsc --noEmit`
(clean) plus DOM inspection confirming the new button's `icon="strategy-map"` and the
settings button's post-click URL before recording.

---

# Contribution-attribution demo — 2026-07-21

`contribution-attribution-demo.mp4` (~30s, Playwright headed 녹화) — openspec change
`strategy-contribution-attribution` 구현 검증 데모. **3개 실서비스**(strategy :8014,
agent-feedback :6789, analytic :8022)가 실제 supabase-db(관계형)·AGE Postgres(그래프)·
deepagents 스킬 API(:8888)를 상대로 응답한 값을 그대로 렌더링한다 — mock 없음.

보여주는 것 (8개 섹션):
1. 전략맵의 전략적 중요도(`importance`, 미지정 시 기본값 3)
2. KPI 기준 성과자 기여도 — 측정에 실제 반영된 인스턴스·태스크 이력 근거, 사람·에이전트 통합 순위
3. **중요도 가중 합산으로 순위 역전** — 개별 KPI 1위(사람 66.7%)를 에이전트가 합산에서 역전(3.67 > 3.33)
4. 성과자 기준 역방향 조회(전략별 가중 기여 내역)
5. manual KPI 의 추적 불가(`traceable:false`) 정직 표시
6. 스킬별 사람 기여자(김지은 66.7% · 박민수 33.3%) — 실제 agent-feedback 서비스 경유
7. `(User)-[:CONTRIBUTED_TO]->(Skill)` 온톨로지 엣지 (agent-feedback 이력 → strategy 증분 동기화)
8. `GET /api/dashboard/contribution` 통합 대시보드 — 중요도 내림차순, 하위 전략 이중 집계 방지

재현 스크립트·시나리오·스크린샷·결과:
`openspec/specs/strategy_contribution-attribution/e2e/` (seed_demo.py / demo.html /
record_demo.py / results.md). 데모 스크래치 테넌트는 녹화 후 삭제됨.

---

# Deterministic-replay (실행 경로 고착화) demo — 2026-07-23

`deterministic-replay-demo.mp4` (~3분 49초, **OpenAI TTS 음성 내레이션(marin) + 한국어
자막**, Playwright 녹화 — 원본·중간 산출물은 `demo-recordings/deterministic-replay-demo/`,
최종본 `demo-recordings/deterministic-replay-demo-narrated.mp4`와 동일) —
LLM 에이전트가 Supabase MCP(`execute_sql`)로 한 번 수행한 활동의 실행 경로를
Python 코드로 **고착화**하고, 다음 실행부터는 **LLM 추론 0회**로 같은 경로를
결정론적으로 재실행하는 기능(구현: `processgpt-agent-utils`의
`DeterministicCodeTool`, 저장소: `mcp_python_code` 테이블, 스펙:
`openspec/specs/crewai-action_deterministic-replay`) 데모.

보여주는 것 (13개 장면 — **실제 Process GPT UI 5개 장면 포함**):
1. 타이틀/기능 소개
2. **실제 UI** — 데모 계정 로그인 (`:5199` 프론트 dev 서버, 실제 Supabase auth)
3. **실제 UI** — 설정 > MCP 서버 탭: `tenants.mcp`에 등록된 Supabase MCP(execute_sql)
   서버와 편집 창의 실제 저장 JSON (녹화 중 DATABASE_URI 패스워드는 DB에서 마스킹 후 복원)
4. **실제 UI** — 업무 목록: `발주 입고 처리`의 `재고 반영` 워크아이템 2건
   (1차=LLM 실행, 2차=고착화 코드 재실행)
5. **실제 UI** — 1차 워크아이템 상세(에이전트 모니터): LLM 실행 카드(`crew_type: action`)
   + `execute_sql` 도구 사용 이력 3건(SELECT/UPDATE/INSERT) — **LLM 실행의 흔적이 화면에 표시**
6. **실제 UI** — 2차 워크아이템 상세: **`결정론적 코드 실행 결과` 카드**(`crew_type: result`),
   작업 결과에 `실행_방식: 고착화된 코드 (LLM 추론 0회)` + 재현 스텝 목록, 도구 추론 이력 없음
   — 두 실행 방식이 화면에서 명확히 구분됨 (spec의 "실행 방식 표시" 요구사항)
7. 문제 제기 — LLM 재량 실행의 리스크와 고착화 파이프라인
8. 1차 실행 — LLM 에이전트가 실제 실행한 SELECT/UPDATE/INSERT 3건과
   `tool_usage_finished` 이벤트 기록 (LLM 3회, 5.2s)
9. 고착화 — 생성된 파라미터화 Python 코드(`${product_name}`/`${stock_quantity}`/`${reason}`)
   와 `mcp_python_code` 저장 키
10. 재실행 — 다른 지시(Galaxy, 250)에서 값만 추출해 같은 경로 3스텝 실행 (LLM 추론 0회, 3.1s)
11. DB 검증 — inventory/inventory_log 실측 반영 결과 (1차=LLM, 2차=고착화 코드)
12. 비즈니스 가치 — 정확성·비용·감사 가능성·프로그래밍 없는 자동화·보상(undo)까지
13. 마무리 — 스펙/구현 위치

내레이션 스크립트/타이밍/녹화 스크립트: `demo-recordings/deterministic-replay-demo/`
(narration.json, scenes-timing.json, record_full_demo.py) — `assemble_narrated_video.py`
자체 검증 PASS (h264+aac, 229s, mean_volume -24dB). 1차 실행은 감사·undo가 가능하도록 상대 연산(stock = stock + N) UPDATE를 사용한다 — 2편(undo) 데모의 전제.

전부 실물이다: 로컬 self-hosted Supabase, `postgres-mcp`(uvx) MCP 서버,
배포 PyPI 패키지 `process-gpt-agent-utils==0.3.4`의 `DeterministicCodeTool`,
실제 OpenAI 호출. 재현 스크립트·시나리오·검증 결과:
`openspec/specs/crewai-action_deterministic-replay/e2e/`
(seed.sql / run_e2e.py **21/21 PASS** / demo.html / record_demo.py —
Playwright 검증 **11/11 PASS** / results.md — 업스트림 버그 2건 발견·문서화 포함).

---

# Deterministic Undo (실행 취소) demo — 2026-07-23 (고착화 2편)

`deterministic-undo-demo.mp4` (~2분 10초, **OpenAI TTS 내레이션(marin) + 한국어 자막**,
1편 `deterministic-replay-demo.mp4`에 이어지는 **별도 영상**) — LLM 에이전트 실행이
DB에 남긴 부수효과를, 기록된 이벤트 로그로부터 자동 생성된 **역연산(undo) 코드**로
되돌리고, 정정된 값으로 고착화 경로를 재실행(redo)하는 기능 데모.
스펙: `openspec/specs/crewai-action_deterministic-undo` (별도 스펙),
구현: `services/completion/compensation_handler.py`(undo 코드 생성) +
`mcp_python_code.compensation`(보존) + 결정론적 실행 경로(실행).

보여주는 것 (8장면, 실제 UI 1장면 포함):
1. 타이틀 — 1편에 이어, Undo
2. 왜 undo — 이미 실행된 업무의 부수효과, 이력 기반 역연산 파이프라인
3. 생성된 undo 코드 — UPDATE 역연산·INSERT→DELETE, 값은 로그에서 동적 파싱 (실측)
4. undo 실행 — iPhone 80→20 원복, 감사 로그 삭제, **같은 테이블의 Galaxy 결과는 보존** (실측 표)
5. **실제 UI** — 재작업 워크아이템의 `Undo(실행 취소) 후 재실행 결과` 카드 +
   "다시 수행하기" 버튼 (실행 방식·undo/redo 스텝 기록)
6. redo — 정정 입고 수량 40으로 고착화 경로 재실행 → 최종 재고 60 + 재작업 로그 (실측)
7. 비즈니스 가치 — 안전망·정밀 복구·재작업 자동화·감사 추적
8. 아웃트로 — "실행할 용기는, 되돌릴 수 있음에서"

재현·검증: `openspec/specs/crewai-action_deterministic-undo/e2e/`
(run_e2e.py **19/19 PASS** / record_demo.py **9/9 PASS** / results.md — 핵심 발견:
undo 가능성은 상대 연산 등 "로그만으로 역연산 가능한 형태"에 의존, 업스트림 이슈
3건 추가 발견·문서화). 영상 원본: `demo-recordings/deterministic-undo-demo/`,
합성 검증 PASS (h264+aac, 130.5s, mean_volume -23.8dB).

---

# Contribution-attribution **UI** demo — 2026-07-23

`contribution-attribution-ui-demo.mp4` (~21s) — 위 API 데모의 후속. 승인된 스토리보드
(openspec/changes/strategy-contribution-attribution/storyboard.html)대로 **실제 제품 컴포넌트**
`StrategyBoard.vue`/`OntologyExplorer.vue`에 기여도 조망을 통합한 화면을 녹화했다. 백엔드
3개(strategy/agent-feedback/analytic)와 supabase-db·AGE 모두 실서비스 — mock 없음.

보여주는 것 (스토리보드 장면 순서):
1. 보드 카드의 전략적 중요도(★) 배지
2. 카드 클릭 → 상세 패널 **기여도 탭**: 사람·에이전트 통합 가중 순위(에이전트가 중요도
   가중으로 1위 역전), 행 확장 시 KPI별 산출 내역(비중 × 중요도), 스킬 성장 기여자
3. KPI 행 확장의 KPI 단위 기여도 블록
4. 성과자 이름 클릭 → 역방향 요약 다이얼로그(전략별 가중 내역 테이블)
5. 온톨로지 탐색기의 CONTRIBUTED_TO('기여') 엣지

## How this recording was made

이전 데모들과 같은 로그인 프리 하네스 기법: 임시 Vite 엔트리(`demo-contribution.html` +
`src/demo-contribution-main.ts`, 녹화 후 제거)가 실제 StrategyBoard/OntologyExplorer 를
Pinia+Vuetify+i18n+해시 라우터만으로 마운트하고(`window.$tenantName`=스크래치 테넌트,
`window.$mode`='ProcessGPT'), `/strategy-service` 프록시→:8014, `/api/analytics` 프록시→:8899.
Playwright(chromium, recordVideo) 스크립트는
`openspec/specs/strategy_contribution-attribution/e2e/record_ui_demo.py` — 각 단계를
expect() assert 로 검증하며 진행(전부 PASS). 스크래치 테넌트는 녹화 후 삭제됨.

---

# Prompt Chaining 에이전틱 패턴 demo — 2026-07-26

`prompt-chaining-demo.mp4` (~2분 46초, **OpenAI TTS 내레이션(marin)**, Playwright 녹화 —
원본·중간 산출물은 `demo-recordings/prompt-chaining-demo/`, 최종본은
`demo-recordings/prompt-chaining-demo-narrated.mp4`와 동일) — "Prompt Chaining"(순차적
프롬프트 연쇄) 에이전틱 패턴을 `process-gpt-demo` 스킬의 신규 시나리오 9로 실제
ProcessGPT 인스턴스에서 시연한 데모. `.claude/skills/process-gpt-demo/references/
scenario-9-prompt-chaining.md` 참고.

**전부 실물**: 로컬 docker-infra(Supabase) + `process-gpt-infra-docker`에서 브링업한
frontend/completion/deepagents/polling-service 등 앱 서비스, 실제 OpenAI 호출, 실제
Supabase DB — mock 없음.

보여주는 것 (9개 장면, 실제 UI 6개 장면 포함):
1~2. 오프닝 슬라이드 — Prompt Chaining 패턴 정의(순차적 의존성·작업 분해·단계별
   최적화·명확한 관찰 가능성)와 이번 데모("시장조사 인사이트 체인") 개요
3. **실제 UI** — 데모 계정 로그인(`:5199` 프론트 dev 서버, 실제 Supabase auth)
4~5. **실제 UI** — 채팅으로 프로세스 생성: "1단계는 사람이 입력, 2·3단계는 딥에이전트가
   순서대로 자동 처리하고 이전 단계 출력을 반드시 참조해야 한다"를 명시적으로 요청 →
   에이전트가 3단계 체이닝 흐름을 그대로 제안 → 스킬 3개(시장 트렌드 근거 추출/트렌드
   기반 마케팅 이메일 작성/인사이트 체이닝 품질 점검) + 에이전트 1개 후보 선택
6. **실제 UI** — 저장된 프로세스의 실제 BPMN 스윔레인(담당자 1개 활동 / 딥에이전트 2개
   활동)
7. **실제 UI** — 핵심 트렌드 식별 활동의 "에이전트에 맡기기" 탭: 실제로 있었던 실행
   이력 그대로(1차 진행중 → 2차 샌드박스 연결 오류로 실패 → docker.sock 마운트 후 3차
   재실행 성공, 체크포인트 3/3 충족)
8. **실제 UI** — 마케팅팀 이메일 초안 작성 활동: `get_related_workitem_outputs` 도구로
   2단계 출력을 실제로 조회해, 이메일 본문에 68%/42%/55%/CAC 22% 등 2단계가 식별한
   구체 수치를 그대로 인용(요약이 아닌 근거 기반 체이닝의 증거)
9. 클로징 슬라이드 — 체이닝 성과 요약

**실측 데이터**: `proc_def.id = market_research_insight_email_process`(활동 3개 모두
`orchestration: "deepagents"`, `inputData`가 선행 활동 출력을 참조), 에이전트 "시장조사
인사이트 자동화 담당"(`effe1f55-0c5e-4d95-a99e-ab61aa177c71`), 인스턴스
`market_research_insight_email_process.d9ef3099-a01c-4cc9-beb0-89d06043d71b` —
`enter_market_report`(사람 제출) → `identify_key_trends`(무인, DONE) →
`draft_marketing_email`(무인, DONE) → `bpm_proc_inst.status = COMPLETED`.

**발견한 실제 이슈 2건** (정직하게 기록): (1) `bpmn-process-generation-skill`의
4단계 자체 검증 도구(`validate_process_definition`)가 `FileNotFoundError`로 반복
실패해, 채팅의 스킬/에이전트 JSON 반영 단계를 완주하지 못함 — 이번 데모는 그 직전에
"저장"을 눌러 BPMN만 먼저 저장한 뒤, 실제 생성된 SKILL.md 3개 내용을 그대로 살려
`orchestration`/`skills`/`agent` 필드를 API로 보완했다. (2) deepagents의
`SkillsMiddleware.before_agent`가 스킬 사용 활동마다 테넌트 샌드박스 컨테이너를 띄우려
하는데, 로컬 docker-infra 브링업 경로는 기본적으로 `/var/run/docker.sock`을 마운트하지
않아 최초 실행이 실패했다 — 사용자 승인을 받아 마운트를 추가한 뒤 재실행해 정상
완료됐다(이 실패 이력 자체가 장면 7에 그대로 남아 있다).

## How this recording was made

`.claude/skills/process-gpt-demo/scripts/record_prompt_chaining_demo.mjs` —
`record_strategy_alignment_live_demo.mjs`의 오프닝 슬라이드 + 실제 UI 혼합 패턴을
재사용. `recording-and-narration.md` 절차대로 무음 webm 녹화 →
`narration.json`(실측 값 반영, 에이전트가 직접 작성) → `gen_narration_openai.py`(voice
marin) → `assemble_narrated_video.py`(PASS: h264/aac, 166.36s, mean_volume -23.7dB).

---

# Prompt Chaining 에이전틱 패턴 demo — English version — 2026-07-26

`prompt-chaining-demo-en.mp4` (~2분 14초, **OpenAI TTS 내레이션(marin), 화면 UI와
채팅 생성 콘텐츠까지 전부 영어**) — 위 한국어 데모와 동일한 "Prompt Chaining"
패턴을 처음부터 끝까지 **영어로 다시 실행**한 버전. 단순히 내레이션만 번역한
것이 아니라, 계정 설정의 언어를 English로 전환하고, 채팅 프롬프트도 영어로
보내 별도의 영어 프로세스(`market_research_report_insight_email_process`)·
영어 스킬(`market-trend-extractor`, `marketing-insight-email-writer`)·영어
에이전트("Market Insight Automation Agent")를 새로 생성·실행했다. 절차는
`.claude/skills/process-gpt-demo/references/scenario-9-prompt-chaining.en.md`
(영문 시나리오 문서)와 `SKILL.md`의 "영문 데모 녹화 시 주의사항" 절 참고.

**실행 중 실제로 발견한 문제와 정직한 우회**: 1단계 승인 시점에는 영어로
요청해도 에이전트가 한국어로 응답해, 자유 입력 칸에 "지금부터 영어로만
응답하라"는 지시를 명시적으로 추가해야 했다. 더 중요한 문제는 마케팅 이메일
초안 활동(3단계)이 **세 번 연속** 이전 단계 출력을 참조하지 못하고 한국어로
일반적인(무관한) 트렌드를 지어내는 것으로 실패했다는 점이다 — `identify_key_
trends` 참조 조회 도구(`get_related_workitem_outputs`)를 에이전트가 스스로
호출하지 않을 때 벌어지는 재현 가능한 실제 버그다. 네 번째 시도에서 해당
활동의 `instruction`/`query`에 2단계의 정확한 산출물 텍스트를 인용문으로
직접 박아 넣어(조회 도구 호출에 의존하지 않도록) 재시도했고, 그제서야
영어로, 정확히 이전 단계 수치(71%, 39% vs 33%, 61% vs 26%, CAC -19%, 구독
관심도 -11pt)를 인용하며 완료됐다. 이 영상의 장면 8(Agent Delegation 탭)은
이 네 번째(성공) 시도 카드로 스크롤해서 보여준다 — 실패한 이전 시도들은
DB에 그대로 남아있다.

보여주는 것 (9개 장면, 실제 UI 6개 장면 포함, 전부 영어):
1~2. 오프닝 슬라이드 — Prompt Chaining 패턴 정의 + 이번 데모 개요(영문)
3. **실제 UI** — 로그인 화면 자체가 영어(계정 설정에서 English로 전환한
   상태가 로그아웃 상태에서도 유지됨)
4~5. **실제 UI** — 영어 프롬프트로 요청한 채팅: 3단계 체이닝 흐름 제안 →
   스킬 2개(Market Trend Extractor, Marketing Insight Email Writer) + DeepAgent
   1개 후보를 전부 선택해 실제로 생성
6. **실제 UI** — 저장된 프로세스의 실제 BPMN 스윔레인(Person in Charge 1개
   활동 / DeepAgent 2개 활동), 전부 영어 라벨
7. **실제 UI** — Identify Key Trends 활동의 Agent Delegation 탭: 첫 시도에
   바로 성공, `get_related_workitem_outputs tool completed` 근거와 체크포인트
   3/3
8. **실제 UI** — Draft Marketing Team Insight Email 활동의 네 번째(성공) 시도:
   2단계의 정확한 수치를 그대로 인용한 최종 이메일 초안
9. 클로징 슬라이드 — 체이닝 성과 요약(영문)

**실측 데이터**: `proc_def.id = market_research_report_insight_email_process`,
에이전트 "Market Insight Automation Agent", 인스턴스
`market_research_report_insight_email_process.6d648c7c-6ba1-4bf4-adca-
69add976906b` — 전 활동 DONE, `bpm_proc_inst.status = COMPLETED`.

## How this recording was made (English version)

`.claude/skills/process-gpt-demo/scripts/record_prompt_chaining_demo_en.mjs` —
한국어 버전과 동일한 오프닝 슬라이드 + 실제 UI 혼합 구조. 로그인 화면부터
영어로 보이도록, 미리 언어를 English로 전환한 뒤 인증 토큰만 제거한
"로그아웃+영문" Playwright `storageState`를 재사용했다. `narration.json`(영문,
실측값 반영) → `gen_narration_openai.py`(voice marin) → `assemble_narrated_
video.py`(PASS: h264/aac, 134.28s, mean_volume -24.9dB).
