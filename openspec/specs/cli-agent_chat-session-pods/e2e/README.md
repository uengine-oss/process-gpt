# CLI 에이전트 대화별 파드 채팅 — 시험

## 실행

```bash
# 라우터 — process-gpt-session-router(feat/auth-and-starting-events)
go vet ./... && go test ./... -race

# 라우터를 실제 파드로 — kind 클러스터 router-e2e
#   런너: SDK 0.12.0 + /health 가 12초 동안 503(콜드 스타트 흉내)
#   라우터: ROUTER_SUPABASE_JWT_SECRET=kind-test-secret
kubectl --context kind-router-e2e port-forward svc/session-router 18090:8080 &
python e2e.py      # RT-KIND-01~05
python e2e2.py     # RT-KIND-06(진행 중인 턴에 수정 지시)

# cli-agent — process-gpt-cli-agent(feat/chat-session-routing)
pytest

# 화면 — process-gpt-vue3(feat/chat-session-routing). 이 워크트리의 개발 서버(포털 :5297, 휴대폰 웹 :5198 을
# /m/ 으로)를 VM 게이트웨이에 붙이고, 에이전트 스트림만 시험이 띄운 SSE 서버로 돌린다
# (starting ×3 → ready → 토큰 → done 을 시간 두고 — page.route 의 fulfill 은 한 번에 내보내 표시가 깜빡이고 끝난다)
BASE_URL=http://127.0.0.1:5297 UX_BASE_URL=http://127.0.0.1:5297 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json CR_SHOTS=<폴더> \
npx playwright test playwright/e2e/chat-session-routing
npm run test:unit
# 로컬 실행(VM Supabase, 실제 claude-code): CLIAGENTS_PROCESS_POLLING=false, 포트 8892
```

kind 시험 파일은 `/Users/uengine/pgfix/router-kind/`(로컬)에 있다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| RT-KIND-01 토큰 없음 | kind e2e 1 · router 단위 | ✅ 401, 런너 0→0 |
| RT-KIND-02 틀린 토큰 | kind e2e 2 · router 단위(HS256 · JWKS · GoTrue · 만료) | ✅ |
| RT-KIND-03 콜드 스타트 「준비 중」 | kind e2e 3 | ✅ 첫 이벤트 0.0초, starting 8번, ready 15.0초, 답변 done |
| RT-KIND-04 웜 파드 | kind e2e 4 | ✅ session_status 0개 |
| RT-03 준비 실패 | router 단위(timeout · failure · 한도) | ✅ |
| RT-04 기다리던 사용자가 떠남 | router · session 단위 | ✅ (옛 코드에서는 실패하는 시험) |
| RT-KIND-05 파드 없는 대화 | kind e2e 5 | ✅ attach active:false · stop no_active_turn · steer 409, 런너 1→1 |
| RT-KIND-06 방향 바꾸기 경로 | kind e2e2 · router 단위 | ✅ accepted + steer_accepted |
| CLI-01 CLI 미선택 | cli-agent 단위 · 로컬 실행 | ✅ cli_not_selected |
| CLI-02 Claude Code 두 턴 | 로컬 실행 | ✅ 3.8초 답, 두 번째 턴 --resume |
| CLI-03 busy | 로컬 실행 | ✅ |
| CLI-04 계정 사용량 이벤트 | `test_account_rate_limit_events_never_reach_the_browser` | ✅ |
| UI-01 포털 준비 중 표시 | Playwright F-CR-01 · F-CR-01b(상태 프레임 없으면 안 보임) · 단위 `sessionStatus.test.js` · `agentStreamSessionStatus.test.js` | ✅ |
| UI-02 휴대폰 웹 준비 중 표시 | Playwright F-CR-02 | ✅ |
| UI-03 CLI 에이전트로 묻기 | Playwright F-CR-01(본문 `metadata.agent_cli`, 맨 위에는 없음) · F-CR-03(`cli_not_selected` 문구) · 단위 `cliAgents.test.js` · `orchestration.test.js` | ✅ |

## 증거

`results/`(.gitignore). 2026-11-11 실행:
- `router-tests.txt` — 55 통과(auth 4 · config 3 · router 31 · session 17)
- `router-kind-e2e.txt` — kind 실제 파드
- `cli-agent-tests.txt` — 169 통과, `cli-agent-local-e2e.txt` — 로컬 실행 기록(비밀값 없음)
- `vue3-unit.txt` — 1158 중 1143 통과 · 15 실패(origin/main 과 같은 15개), Playwright 4 통과
- `portal-preparing.png` · `m-preparing-390x844.png` · `portal-cli-not-selected.png`

## 아직 확인하지 않은 것

- 운영 클러스터의 실제 codex · cli-agent 런너(이미지 1.75GB pull 포함 기동 시간).
- 튜토리얼 VM 에는 쿠버네티스가 없어 라우터를 VM 화면과 함께 돌리지 못했다 — 라우터는 kind 에서, 화면은 스트림을 흉내 내 확인했다.
- VM Supabase 에 `agent_sessions` 표 · `agent-sessions` 버킷 · Memento `artifacts` 버킷이 없어, 로컬 실행에서 세션 보관과 산출물 링크는 경고만 남기고 넘어갔다(턴은 끝났다).
