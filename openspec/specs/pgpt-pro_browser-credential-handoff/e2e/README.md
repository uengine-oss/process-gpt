# E2E — pgpt-pro_browser-credential-handoff

소개 영상(실제 앱 실행 녹화 · 일레븐랩스 나레이션, 1분 57초): https://youtu.be/n5SBj_iRbig — 재생성 `pgpt-pro/docs/demo/vault/` (`node record.mjs && python3 narrate.py && python3 edit.py`).

브라우저 에이전트가 로그인·결제·일회용 코드 요구를 만났을 때 시스템이 대신 받아 보관함에 넣고, 모델에 노출하지 않고 입력하는지를 두 단계로 검증한다.

| 단계 | 무엇으로 | 모델 | 산출물 |
|---|---|---|---|
| 통합 테스트 | `pgpt-pro/server/test/browser-vault.test.js` (Chromium + 테스트 상점 + 모델 대역 서버 + 사용자 흉내) | 대역(모든 요청 기록) | `results/browser-vault.test.txt` |
| UI E2E | `ui-e2e.mjs` (실제 앱 :5180 → BFF :8787) | 실제 모델(`PRO_LLM_*`) | `results/*.png`, `results/results.json`, `results/ui-e2e.webm` |

## 실행 환경

- 인프라(Docker): Supabase(`desktop-linux` 컨텍스트, db :54322, kong :54321).
- 앱(소스 실행): BFF `cd pgpt-pro/server && node index.js` (:8787), 프런트 `cd pgpt-pro && npx vite` (:5180).
- 테스트 상점: 스크립트가 직접 띄운다(:8799, 로그인 `demo@shop.test`, OTP `246810`, 테스트 카드 `4242 4242 4242 4242 / 12/30 / 123`). 단독 실행은 `node pgpt-pro/server/test/fixtures/shop.mjs 8799`.
- 모델 요청 검사: BFF 를 `PRO_LLM_TRACE=<파일>` 로 띄우면 모델 요청 텍스트(이미지 제외)가 파일에 쌓이고, 스크립트가 그 안에서 비밀 값을 찾는다. 평소에는 끈다.

```bash
# 통합 테스트
cd <process-gpt-lite>/server && node --test --test-timeout=120000 test/browser-vault.test.js

# UI E2E (BFF 를 trace 켠 상태로 재시작한 뒤)
PRO_LLM_TRACE=/tmp/pgpt-trace.jsonl node openspec/specs/pgpt-pro_browser-credential-handoff/e2e/ui-e2e.mjs
```

## 시나리오 ↔ 증거

| 스펙 시나리오 | 통합 테스트 | UI E2E 증거 |
|---|---|---|
| 처음 가는 사이트에 로그인 | login 테스트: 카드 순서 `login/request/saved` | `01-login-request-card.png` → `02` → `03-login-saved-chip.png`, 상점 `passwordOk: true` |
| 저장된 카드 없이 결제 | card 테스트: `request/saved`, 입력 필드 순서 | `06-card-request-card.png`, `07-card-filled.png` |
| 카드 두 장 중 선택 | two cards 테스트: 끝자리 4444 결제 | — |
| 로그인·OTP·결제 전 과정의 모델 요청 검사 | 모든 테스트: 대역 서버가 받은 요청에 비밀 값 0건 | `results.json` 의 `model_trace_leak_scan.secrets_found: 0` (39개 요청) |
| 모델이 비밀번호 칸에 직접 입력 시도 | login 테스트: `refused: this is a secret field` | — |
| 처음 입력한 비밀번호가 틀림 | login 테스트: 상점 `[false, true]`, 활동 `reject → update → fill` | — |
| 휴대폰 인증 코드 | login 테스트: 카드 `secret/request/used`, 항목 수 1 | `04-otp-secret-card.png`, 상점 `otps: [{ok: true}]` |
| 로그인 요청 닫기 | closed request 테스트: 요청 1회만 | — |
| 다른 계정으로 직접 로그인 | takeover 테스트: 감지 카드 → 확인 → 계정 2개 | — |
| 결제 승인 | card 테스트: 승인 카드에 `89,000원 … Visa •••• 4242` | `08-approval-card-masked-fields.png`(실시간 화면의 카드 칸이 점으로 가려짐), `10-payment-done.png`, 상점 `payments: [{last4: "4242", ok: true}]` |
| 사람이 없는 실행 / 응답 없는 요청의 만료 | 코드 경로(무인 분기·재시작 정리) | — |

## UI E2E 결과 요약 (2026-10-23, 모델 frentis-ai-model)

- 9단계 모두 통과. 상점이 받은 값: 로그인 1회 성공, OTP 1회 성공, 결제 1회 성공(끝자리 4242).
- `independent_envelope_check`: 서버 키링의 KEK 로 DEK 를 풀고 DEK 로 항목을 풀었을 때 로그인·카드 모두 사용자가 입력한 값과 일치, 항목은 KEK 로 직접 풀리지 않음.
- `database.plaintext_secrets_found_in_rows: 0`, `api_list_returns_secret_fields: false`, `api_proof.ok: true`.
- 설정 화면: `11-settings-accounts.png`, `12-settings-wallet.png`, `13-settings-security.png`, `14-security-proof-detail.png`, `15-security-vault-activity.png`.
