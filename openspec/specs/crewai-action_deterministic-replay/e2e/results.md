# E2E 결과 — 실행 경로 고착화 (Deterministic Replay) — 2026-07-23

## 요약
- `run_e2e.py`: **21/21 PASS** (실 Supabase + 실 MCP 서버 + 실 LLM, mock 없음)
- `record_demo.py`(Playwright): **11/11 PASS** (demo.html 렌더 검증 + 무음 원본 녹화)
- 최종 데모 영상: `docs/demo/deterministic-replay-demo.mp4`
  (= `demo-recordings/deterministic-replay-demo-narrated.mp4`, 225.5s, 1280x720,
  **OpenAI TTS 내레이션(marin) + 한국어 자막**, 실제 Process GPT UI 5개 장면
  — 로그인 / MCP 서버 설정 / 업무 목록 / 워크아이템 상세 2건 — 포함,
  `assemble_narrated_video.py` 검증 PASS)

## 실행 방식 표시 (신규 요구사항 검증)
워크아이템 화면(에이전트 모니터)에서 두 실행 방식이 구분된다:
- 1차(LLM): `task_started`(crew_type `action`) 카드 + 같은 job_id의
  `tool_usage_started/finished` 이벤트 → 화면에 "execute_sql 도구 사용 완료: SELECT/UPDATE/INSERT" 이력 표시
- 2차(고착화 코드): `task_started/completed`(crew_type `result`, role
  "결정론적 코드 실행 결과") — crewai-action `_run_deterministic`이 발행하는 이벤트와 동일 형식.
  작업 결과에 `실행_방식: 고착화된 코드 (LLM 추론 0회)`와 재현 스텝 목록 표시, 도구 추론 이력 없음.
표시용 proc_def에는 최소 BPMN(시작→재고 반영→종료)을 시드해 워크아이템 상세의
프로세스/에이전트 모니터 탭이 활성화되게 했다.

## 측정치
| 항목 | 1차 실행 (LLM) | 재실행 (고착화 코드) |
|---|---|---|
| LLM 추론(에이전트 루프) 호출 | 3회 | **0회** |
| MCP 도구 호출 | 3건 (SELECT/UPDATE/INSERT) | 3건 (동일 경로) |
| 소요 시간 | 5.2s | 3.1s |
| DB 반영 | iPhone stock=80 + 로그 | Galaxy stock=250 + 로그 |

재실행 시 LLM은 새 지시문에서 파라미터 **값 추출**(`_extract_parameters_from_query`,
1회 경량 호출)에만 쓰이고, 무엇을 어떤 순서로 어떻게 실행할지는 전부 고착화된
코드에 고정되어 있다 — 경로에 대한 재량(할루시네이션 여지)은 0이다.

## 검증 목록 (run_e2e.py)
0. seed 적용 / `tenants.mcp` Supabase MCP 등록 / `execute_sql` 툴 노출 — PASS
1. Phase A: LLM이 UPDATE·INSERT 실행, iPhone=80 반영, `tool_usage_finished` 3건 기록 — PASS
2. Phase B: 코드 생성·저장, `call_tool`만 사용(LLM 호출 없음), `${...}` 파라미터화,
   3스텝 순서 보존, 파라미터 명세(product_name/stock_quantity/reason) — PASS
3. Phase C: ok=true, 3스텝 재현, Galaxy=250 반영, 감사 로그 기록, 1차 결과 보존,
   도구 추론 이벤트 0건 + '결정론적 코드 실행 결과' 표시 이벤트 기록 — PASS

## 이번 검증으로 발견한 업스트림 이슈 (process-gpt-agent-utils 0.3.4)
`run_e2e.py`에 동일 로직의 워크어라운드를 적용해 검증했다. 두 건 모두
`processgpt_agent_utils/tools/deterministic_code_tool.py` 수정 제안 대상:

1. **코드펜스 미제거로 파라미터 제안이 항상 폴백으로 떨어짐** —
   `_suggest_parameters_via_llm`이 LLM 응답의 ```json 펜스를 벗기지 않고
   `json.loads` → gpt-4o에서 항상 예외 → 퇴화된 정규식 폴백(`${sql}` 전체 치환)
   사용. 같은 파일의 `_extract_parameters_from_query`는 펜스를 벗긴다(수정 방법 동일).
2. **바인딩 맵이 스텝 순서를 무시** — `_compile_steps_to_code`가 바인딩을
   `(tool, arg)` 키 하나로 매핑해, 동일 툴 반복 시(연속 `execute_sql` 경로에서 항상)
   마지막 바인딩이 모든 스텝을 덮어씀. 스텝 순서대로 FIFO 소진해야 한다.
3. (참고) **SELECT 제외 필터의 인자명 의존** — `_event_row_to_step`의 SELECT 전용
   `execute_sql` 제외가 `args["query"]` 기준이라, 인자명이 `sql`인 MCP 서버
   (예: postgres-mcp)에는 적용되지 않는다. 이번 데모에서는 SELECT 스텝이 코드에
   포함되어 재실행되었다(읽기라 무해). 스펙의 "SELECT 전용 제외" 계약을 일반화하려면
   `query`/`sql` 인자 모두 검사해야 한다.
4. (참고) **crewai-action 실행기 훅 비활성** — `crewai_action_executor.py`의
   `_run_deterministic`(실행 전 258행)·`_generate_deterministic`(완료 후 423행)
   호출부가 주석 처리되어 있어, 배포 상태에서는 이 기능이 자동으로 타지 않는다.
   본 E2E는 그 안쪽의 실제 구현(`DeterministicCodeTool`)을 직접 검증했다.

## 재현 아티팩트
- `demo_data.json` — 이벤트/생성 코드/DB 결과/시간 실측값 (DB URI 패스워드 마스킹)
- `screenshots/s0~s8.png` — 데모 각 섹션
- 영상 제작 방식: `demo.html`(demo_data.json을 로드하는 스토리 페이지)을
  Playwright `recordVideo`로 섹션별 자막과 함께 스크롤 녹화 → ffmpeg 무음 mp4 변환
