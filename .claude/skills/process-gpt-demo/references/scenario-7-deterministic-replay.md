# 시나리오 7 — 실행 경로 고착화 (Deterministic Replay, Supabase MCP)

LLM 에이전트가 Supabase MCP(`execute_sql`)로 한 번 수행한 활동의 도구 호출
경로를 Python 코드로 고착화하고, 같은 활동의 다음 실행을 **LLM 추론 0회**로
결정론적으로 재실행하는 것을 보여준다.

- 구현: `processgpt-agent-utils`(PyPI)의 `DeterministicCodeTool`
  (generate = 이벤트 이력 → 파라미터화 코드 저장, execute = 저장 코드 재실행),
  저장소는 `mcp_python_code` 테이블(`proc_def_id, activity_id, tenant_id` 키).
- 스펙: `openspec/specs/crewai-action_deterministic-replay/spec.md`
- 완성 영상: `docs/demo/deterministic-replay-demo.mp4`
  (= `demo-recordings/deterministic-replay-demo-narrated.mp4`, ~3분 17초,
  OpenAI TTS 내레이션(marin) + 자막, 실제 UI 3개 장면 포함)

## 전제

- docker-infra 스택의 Supabase가 떠 있어야 한다 (kong `:54321`, pg `:54322`).
  게이트웨이/프론트는 필요 없다 — 이 시나리오는 백엔드 도구 계층 데모다.
- OPENAI_API_KEY (docker-infra/.env 또는 리포 루트 .env).
- 주의: crewai-action 실행기의 자동 훅(`_run_deterministic`/`_generate_deterministic`)
  은 업스트림에서 주석 처리되어 있어, 배포 스택의 프로세스 실행 중에 자동으로
  타지 않는다. 데모는 그 안쪽 실제 구현을 직접 구동한다.

## 실행 절차 (전부 스크립트화되어 있음)

```bash
cd openspec/specs/crewai-action_deterministic-replay/e2e

# 1) 환경 (1회): 배포 패키지 그대로 설치
uv venv detdemo-venv --python 3.12
uv pip install --python detdemo-venv/bin/python \
    process-gpt-agent-utils==0.3.4 langchain-openai fastmcp playwright
detdemo-venv/bin/playwright install chromium

# 2) E2E: seed → Supabase MCP 등록(tenants.mcp) → 1차 LLM 실행(이벤트 기록)
#         → 고착화(generate) → 결정론적 재실행(execute) → DB 검증. 19개 체크.
detdemo-venv/bin/python run_e2e.py

# 3) Playwright: demo.html 검증(11개 체크) + 무음 자막 영상 녹화
detdemo-venv/bin/python record_demo.py

# 4) (권장 최종본) 실제 UI 포함 + TTS 내레이션 녹화 — recording-and-narration.md 절차
#    전제: 프론트 dev 서버(:5199, services/frontend에서 npm run dev -- --port 5199)
#    demo@localhost / Demo1234! 로그인, 워크아이템 user_id는 auth uuid여야 UI에 보임
cd ../../../../demo-recordings/deterministic-replay-demo
python3 ../../.claude/skills/process-gpt-demo/scripts/gen_narration_openai.py \
    --script narration.json --out-dir narration --voice marin
<detdemo-venv>/bin/python record_full_demo.py     # 실제 UI 3장면 + 스토리 7장면
python3 ../../.claude/skills/process-gpt-demo/scripts/assemble_narrated_video.py \
    --video raw/demo-raw.webm --timing scenes-timing.json \
    --narration-dir narration --out ../deterministic-replay-demo-narrated.mp4
```

## 실행 방식 구분 표시 (워크아이템 화면)

워크아이템 상세의 "에이전트에 맡기기" 탭(AgentMonitor)이 `events`(todo_id 기준)를
카드로 렌더링한다. 실행 방식이 화면에서 구분되려면:
- LLM 실행: `task_started`(crew_type `action`) + 같은 job_id의
  `tool_usage_started/finished` → 에이전트 카드 + 도구 사용 이력으로 표시.
- 고착화 재실행: `task_started/completed`(crew_type `result`,
  role "결정론적 코드 실행 결과") — crewai-action `_run_deterministic`이 발행하는
  형식 그대로. run_e2e.py가 재실행 후 이 이벤트를 기록한다.
- 탭 자체는 proc_def에 `bpmn`이 있어야 활성화된다(seed가 최소 BPMN 주입).
- 워크아이템이 업무 목록에 보이려면 `todolist.user_id`가 로그인 계정의
  **auth uuid**여야 한다(이메일 아님 — seed가 auth.users에서 조회해 넣음).

## 시연 포인트 (말로 짚어줄 것)

1. `tenants.mcp`에 등록된 MCP 서버 구성은 프로덕션 형식 그대로다
   (MCP 서버 설정 화면이 편집하는 그 JSON).
2. 1차 실행에서 LLM이 SELECT→UPDATE→INSERT를 스스로 결정했고, 각 호출이
   `events`(`tool_usage_finished`, `crew_type=action`)에 남았다.
3. 고착화된 코드에는 LLM 호출이 전혀 없고, 업무 값만 `${...}` 파라미터다.
4. 재실행은 다른 지시(Galaxy/250)에서 값만 추출해 같은 경로를 그대로 탄다 —
   경로 재량이 없으므로 할루시네이션이 개입할 수 없다.
5. 비즈니스 가치: 검증된 실행의 기억 → 프로그래밍 없이, 매번 정확하게, 더 싸게.

## 알려진 함정

- `postgres-mcp`는 python 3.13+에서 `pglast` 빌드가 깨진다 — `uvx --python 3.12`.
- `process-gpt-agent-utils==0.3.4`의 두 가지 버그(코드펜스 미제거, 바인딩 순서
  붕괴) 워크어라운드가 `run_e2e.py`에 문서화되어 있다. 업스트림 수정 제안은
  `e2e/results.md` 참고.
- 재실행 결과 검증은 반드시 DB로 한다: `inventory`(Galaxy=250)와
  `inventory_log`에 실측 행이 생겨야 성공이다.
