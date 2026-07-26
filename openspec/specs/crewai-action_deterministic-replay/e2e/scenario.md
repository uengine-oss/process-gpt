# E2E 시나리오 — 실행 경로 고착화 (Deterministic Replay)

## 목적
LLM 에이전트가 Supabase MCP(`execute_sql`)로 한 번 수행한 활동의 실행 경로를
Python 코드로 고착화하고, 동일 활동의 다음 실행을 **LLM 추론 없이** 그 코드로
결정론적으로 재실행하는 전 과정을 실물 구성요소로 검증한다.

## 구성 (mock 없음)
| 구성요소 | 실물 |
|---|---|
| DB | 로컬 self-hosted Supabase (`supabase-db`, kong `:54321`, pg `:54322`) |
| Supabase MCP 서버 | `postgres-mcp` (uvx, `execute_sql` 툴) — `tenants.mcp`에 프로덕션 형식으로 등록 |
| 이벤트 기록 | `processgpt_agent_utils.utils.database.save_event_sync` (프로덕션 SDK 함수) |
| 고착화·재실행 | `processgpt_agent_utils.tools.deterministic_code_tool.DeterministicCodeTool` (PyPI 0.3.4, crewai-action이 쓰는 배포 패키지) |
| LLM | OpenAI gpt-4o (1차 실행 에이전트 루프, 코드 생성 시 파라미터 제안, 재실행 시 값 추출) |

## 업무 시나리오
프로세스 `order_fulfillment_demo`(발주 입고 처리)의 활동 `update_inventory`(재고 반영).

1. **Phase A — 1차 실행 (LLM):** 워크아이템 지시
   *"iPhone 상품의 재고를 80으로 업데이트하고, inventory_log에 변경 사유(발주 입고)를 남겨라"*
   를 LLM 에이전트가 `execute_sql`로 수행 (SELECT → UPDATE → INSERT).
   각 호출은 `tool_usage_finished`(`crew_type: action`) 이벤트로 기록된다.
2. **Phase B — 고착화:** `DeterministicCodeTool(action='generate')` 가 이벤트 이력을
   파라미터화된 Python 코드(`${product_name}`, `${stock_quantity}`, `${reason}`)로 컴파일해
   `mcp_python_code` 테이블에 `(proc_def_id, activity_id, tenant_id)` 키로 저장한다.
3. **Phase C — 결정론적 재실행:** 다른 입력의 새 워크아이템
   *"Galaxy 상품의 재고를 250으로 업데이트하고 …"* 에 대해
   `DeterministicCodeTool(action='execute')` 가 저장된 코드를 서브프로세스로 실행한다.
   경로·SQL 구조는 코드에 고정되어 있고, 새 지시에서 **값만** 추출된다.
   에이전트 크루(LLM 추론 루프)는 생성되지 않는다.

## 실행 방법
```bash
# 사전: docker-infra 스택 기동(supabase-db 등), docker-infra/.env 존재,
#       OPENAI_API_KEY (docker-infra/.env 또는 리포 루트 .env)
uv venv detdemo-venv --python 3.12
uv pip install --python detdemo-venv/bin/python \
    process-gpt-agent-utils==0.3.4 langchain-openai fastmcp playwright
detdemo-venv/bin/playwright install chromium

detdemo-venv/bin/python run_e2e.py       # 19개 검증 + demo_data.json 생성
detdemo-venv/bin/python record_demo.py   # Playwright 11개 검증 + 무음 mp4 녹화
```

산출물:
- `demo_data.json` — 실측 아티팩트(이벤트, 생성 코드, DB 반영 결과, 시간)
- `screenshots/*.png`, `video/*.webm`
- `../../../../docs/demo/deterministic-replay-demo.mp4` (무음, 한국어 자막)
