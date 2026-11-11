# CLI 에이전트 회사 API 키 — 시험

## 실행

```bash
# 화면 — process-gpt-vue3(main, #254 · #255). VM 에 붙은 개발 서버로 또는 VM(UX_BASE_URL=http://localhost:8088)에서:
~/.claude/skills/screen-review-ship/scripts/devserver/start.sh $PWD 5311 5313
BASE_URL=http://127.0.0.1:5311 UX_BASE_URL=http://127.0.0.1:5311 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/cli-agent-keys
npm run test:unit     # src/shared/cliAgentKeys · src/utils/cliAgents · orchestration

# DB — VM 에만 적용(운영 DB 는 사람이): supabase/migrations/20261111000001_cli_agent_credentials.sql
docker --context colima-pgtut exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 < supabase/migrations/20261111000001_cli_agent_credentials.sql
docker --context colima-pgtut exec -i supabase-db psql -U postgres < results/verify.sql   # 실제 JWT 역할 전환, 롤백

# cli-agent — process-gpt-cli-agent(main, #2 · #3)
pytest
```

시험이 넣은 키는 끝에 지운다(VM 메타 0 · Vault 0). 가짜 키(`sk-ant-test-…`)만 쓴다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| F-CK-02 관리자가 키를 넣는다 | `F-CK-02` · 단위 `cliAgentKeys` | ✅ VM |
| F-CK-05 관리자가 아닌 사용자 | `F-CK-05`(탭 없음 · 주소로 와도 돌려보냄 · 서버 set/get 거절 · updated_at 가림) | ✅ |
| F-CK-06 키를 지운다 | `F-CK-06` | ✅ |
| F-CK-07 키가 있는 CLI 만 | `F-CK-04`(Anthropic 만 → Claude Code 만) · `F-CK-07`(OpenAI 만 → Codex 만) · 단위 `cliChoicesFor` | ✅ |
| SEC-CK-01 역할별 접근 | `results/verify.sql` 41건 · REST(비관리자 set 403 · anon 401 · 사용자 get 403 · 표 직접 읽기 42501) | ✅ |
| CLI-CK-01 회사 키로 돈다 | cli-agent `tests/test_credentials.py`(실제 runner, 가짜 CLI 가 env 를 출력 — 키 있음 · OAuth 토큰 없음 · os.environ 그대로 · 로그 · 이벤트 · 작업 폴더 · 보관에 키 없음, 가리기를 끄면 4개 실패) · VM 확인 | ✅ |
| CLI-CK-02 회사 키 없는 채팅 거절 | cli-agent 채팅 e2e(실제 runner) — 프로세스가 뜨지 않고 error 하나 | ✅ |

## 증거

`results/`(.gitignore): `vm-cli-agent-keys.txt`(VM 7 통과) · `verify.sql` · `cli-agent-pytest.txt`(209 통과) · 화면 사진.

## 아직 확인하지 않은 것

- 운영 DB 에 SQL 적용 뒤 운영 화면에서 넣기 · 지우기(사람이 적용한 뒤 시험 계정으로).
- 실제 Anthropic · OpenAI 키로 CLI 실행(가짜 키로 환경만 확인했다).
