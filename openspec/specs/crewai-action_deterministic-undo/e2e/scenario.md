# E2E 시나리오 — 결정론적 Undo(실행 취소)

## 목적
LLM 에이전트 실행이 남긴 DB 부수효과를, 기록된 이벤트 로그로부터 생성된
역연산(undo) 코드로 되돌리고(80→20 원복, 감사 로그 삭제, 다른 실행 결과 보존),
정정된 입력으로 고착화된 순방향 코드를 재실행(redo, 20+40=60)하는 전 과정을
실물 구성요소로 검증한다.

## 전제 (실행 순서 중요)
`crewai-action_deterministic-replay/e2e/run_e2e.py`가 먼저 21/21 PASS로 실행되어
1차 실행 이벤트·순방향 코드·DB 상태(iPhone=80, Galaxy=250)가 준비되어 있어야 한다.
1차 실행 에이전트는 **상대 연산**(`stock = stock + N`)으로 UPDATE하도록 지시받는다 —
이벤트 로그에는 도구 **인자만** 기록되므로(SELECT 결과 없음), 절대값 대입은
로그만으로 역연산이 불가능하다. 이 제약이 undo 가능성의 핵심 전제다.

## 구성 (mock 없음)
| 구성요소 | 실물 |
|---|---|
| undo 코드 생성 | `services/completion/compensation_handler.py`의 `generate_deterministic_compensation_code` (배포 코드 그대로 import, completion `database` 의존성만 실측 구현 주입) |
| undo 실행 | 생성된 스크립트를 `MCP_CONFIG` + `{"event_logs": [...]}` 입력으로 서브프로세스 실행 |
| redo 실행 | `DeterministicCodeTool._execute_code` (PyPI `process-gpt-agent-utils`) — 순방향 코드 |
| DB/MCP | 로컬 Supabase + postgres-mcp(`execute_sql`) — replay e2e와 동일 |

## 실행 방법
```bash
cd openspec/specs/crewai-action_deterministic-replay/e2e
<venv>/bin/python run_e2e.py          # 전제 상태 준비 (21/21)
cd ../../crewai-action_deterministic-undo/e2e
<venv>/bin/python run_e2e.py          # undo/redo 검증 (19/19)
<venv>/bin/python record_demo.py      # demo.html 렌더 검증 (9/9)
```

영상(별도 2편): `demo-recordings/deterministic-undo-demo/`의
`narration.json`/`record_undo_demo.py` → `assemble_narrated_video.py` →
`docs/demo/deterministic-undo-demo.mp4`
