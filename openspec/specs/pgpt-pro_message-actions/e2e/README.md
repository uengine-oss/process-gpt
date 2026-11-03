# 검증: 메시지 메뉴와 답장

## 실행
- 실제 BFF(`PRO_PORT=8793 PRO_BACKGROUND=0`) + 공용 Supabase + 공용 deepagents + 회사 게이트웨이 모델 `frentis-ai-model`. Vite `PRO_API_TARGET=http://127.0.0.1:8793 vite --port 5193`.
- 단위·사례: `cd server && node --test test/message-actions.test.js` (사례 `test/message-actions-cases.json`)
- HTTP E2E(실제 에이전트): `cd server && API_URL=http://localhost:8793 node test/message-actions.e2e.mjs`
- 화면(모델 없음): `cd e2e && PGPT_URL=http://localhost:5193 API_URL=http://localhost:8793 npx playwright test --project=feature tests/feature/message-actions.spec.js`
- 화면 끝까지(실제 에이전트): `cd e2e && PGPT_URL=http://localhost:5193 API_URL=http://localhost:8793 npx playwright test --project=agent tests/agent/message-reply.spec.js`
- 터치는 Chromium 입력 경로(CDP `Input.dispatchTouchEvent`)로 넣는다. 실제 iOS·Android 기기로는 돌리지 않았다.

## 시나리오 ↔ 시험
| 시나리오 | 시험 |
|---|---|
| 휴대폰에서 길게 누른다 | F-MA-07 |
| 짧게 누르거나 스크롤한다 | F-MA-08 |
| PC 에서 우클릭한다 | F-MA-01 |
| 선택한 글자와 링크를 우클릭한다 | F-MA-03 |
| 화면 끝에서 우클릭한다 | F-MA-02 |
| 문서 카드 | F-MA-12 |
| 평가하고 거둔다 | F-MA-06, `message-actions.e2e.mjs` 8 |
| 평가할 수 없는 경우 | `message-actions.e2e.mjs` 9 |
| 복사한다 | F-MA-04 |
| 글자를 고른다 | F-MA-05 |
| 최근 대화에 없는 말에 답장한다 | `message-actions.e2e.mjs` 3·5, A-MA-01 |
| 인용할 수 없는 대상 | `message-actions.e2e.mjs` 4·6 |
| 어느 대화로 이어 가는지 | `message-actions.test.js`(사례 9건), `message-actions.e2e.mjs` 5 |
| 답장을 쓰고 보낸다 | F-MA-09 |
| 답장을 그만둔다 | F-MA-10 |
| 보낸 답장을 본다 | F-MA-11 |
| 영어 모드 | F-MA-13, `message-actions.test.js` |

## 증거
`results/` 에 시험 출력과 영상 프레임이 있다.
