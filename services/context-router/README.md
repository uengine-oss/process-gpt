# context-router

에이전트(deepagents, cliagents) 앞에서 동작하는 두 가지 기능을 제공한다.

1. **판단 전략** (`POST /decide`): 선택지 중 하나와 확률. 전략 패턴 — 판단 모델(judge) → logprob → JSON 순으로 시도하고, 측정된 확신도가 `DECIDE_ESCALATE_BELOW` 미만이면 다음 전략으로 에스컬레이션한다.
2. **대화 맥락 라우팅** (`POST /route`, `POST /chat/stream`): 채팅 메시지가 어느 대화의 후속인지/새 주제인지 판단해 `conversation_id` 를 정하고 에이전트로 전달한다(요청별 `metadata.auto_route`). 그 밖의 경로는 기본 에이전트로 그대로 전달한다.

스펙: `openspec/specs/context-router_decision-strategies`, `openspec/specs/context-router_conversation-routing` (측정 결과·시연 영상 포함).

## 실행
```bash
uv venv .venv && uv pip install --python .venv/bin/python -r requirements.txt
psql ... < sql/001_context_threads.sql
cp .env.example .env   # DECIDE_*, SUPABASE_*
.venv/bin/python server.py            # :8895
.venv/bin/python -m pytest -q         # 단위 검증
```

### 참조 판단 서버 (선택)
```bash
uv venv .venv-judge --python 3.12
uv pip install --python .venv-judge/bin/python "git+https://github.com/ikermoel/open-alternative-jev" torch transformers accelerate starlette uvicorn
JUDGE_MODEL=Qwen/Qwen3-4B-Instruct-2507 JUDGE_PERMUTATIONS=2 .venv-judge/bin/python judge_server.py   # :8896
```
`DECIDE_JUDGE_URL=http://localhost:8896/judge` 로 연결한다. 같은 계약(`{state, question, options}` → `{choice, probabilities}`)을 지키는 다른 판단 모델(예: TypeSafe JEV 어댑터)로 바꿀 수 있다.

`EMBED_MODEL=BAAI/bge-m3` 을 함께 주면 같은 서버가 OpenAI 형식 `POST /embeddings` 도 제공한다(후보 좁히기용, `ROUTER_EMBED_URL=http://localhost:8896`).

## 맥락이 많을 때
판단 모델에는 대화 이력이 아니라 후보 6개 이하의 짧은 설명만 간다(`router/select.py`).
- 저장소: 30일 넘게 잠든 맥락 제외(`ROUTER_DORMANT_DAYS`), 최근 200개(`ROUTER_SCAN`) + 메시지 단어로 제목·요지 검색
- 좁히기: 진행 중 작업과 최근 2개(`ROUTER_KEEP_RECENT`) 고정, 나머지는 단어 겹침 + 의미 유사도(`ROUTER_EMBED_URL`, 선택) + 최근성으로 `ROUTER_TOP_K`(6)까지, 같은 제목은 한 자리
- 압축: 하루 이내 160자, 일주일 이내 100자, 그 뒤 60자. 요약을 바꿀 때 이전 요청은 요지(`gist`)로 접힌다(`sql/002_context_gist.sql`)
- 판단 모델이 근거(겹치는 단어, 유사도 `ROUTER_EVIDENCE_SIM`) 없는 대화를 고르면 판단 모델을 건너뛰고 다시 판단한다

## 측정
- `eval/bench.py` (문항 `eval/cases.json`) → `eval/results.json`, `eval/report.py` → HTML 보고서.
- `eval/scale.py [N ...]` → `eval/scale.json`: 무관한 대화 N개를 섞어 기존·전부 넣기·좁히기 비교. `eval/report_scale.py out.html [브라우저 게이트 결과.json]` → HTML 보고서.
