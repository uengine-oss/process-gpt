# 검증: 방 규칙과 내장 브라우저의 긴 작업

## 실행
- 실제 BFF(`PRO_PORT=8794 PRO_BACKGROUND=0`) + 공용 Supabase + 실제 Chromium + 회사 게이트웨이 모델. Vite `PRO_API_TARGET=http://127.0.0.1:8794 --port 5196`.
- 규칙·안내: `cd server && node --test test/room-rules.test.js` (사례 `test/room-rules-cases.json`)
- 기다리기·파일·진행(실제 Chromium, 작은 스튜디오 사이트, 대본대로 움직이는 모델): `cd server && node --test test/browser-long-work.test.js`
- 직접 제어(실제 서버·실제 화면, 모델만 대본, 표적은 화면 사진에서 색으로 찾는다): `cd server && node --test test/takeover.e2e.mjs`
- 말로 정하고 링크로 실행(실제 모델·실제 Chromium): `cd server && API_URL=http://localhost:8794 node test/room-rules.e2e.mjs`
- 화면(모델 없음): `cd e2e && PGPT_URL=http://localhost:5196 API_URL=http://localhost:8794 npx playwright test --project=feature tests/feature/room-rules.spec.js`

## 시나리오 ↔ 시험
| 시나리오 | 시험 |
|---|---|
| 규칙을 말한다 | `room-rules.e2e.mjs` 1 |
| 다른 말로 해도 규칙이다 | `room-rules.e2e.mjs` 3 |
| 규칙이 아닌 말 | `room-rules.e2e.mjs` 2, `room-rules-cases.json` |
| 프로젝트 방이 아닌 대화 | `room-rules.e2e.mjs` 8 |
| 모델이 답하지 못한다 | `browser-long-work.test.js` |
| 링크만 붙인다 | `room-rules.e2e.mjs` 5 |
| 모델이 느리거나 계획을 내지 못한다 | `browser-long-work.test.js` |
| 사이트 일이 아닌 규칙 | `room-rules.e2e.mjs` 9 |
| 말이 길다 | `room-rules.test.js`, `room-rules-cases.json` |
| 규칙을 본다 / 끈다 / 다른 사람 | F-RR-01, F-RR-02·`room-rules.e2e.mjs` 7, F-RR-04·`room-rules.e2e.mjs` 4 |
| 생성을 기다린다 / 글자가 나타날 때까지 / 안 끝난다 / 기다리다 취소한다 | `browser-long-work.test.js` |
| 끝날 때까지 지켜본다 / 다운로드 / 첨부를 소스로 넣는다 / 없는 파일 | `browser-long-work.test.js` |
| NotebookLM 일 / 다른 일 | `room-rules.test.js`, `browser-long-work.test.js` |
| 나중에 연 카드 / 창이 낮아도 / 빠르게 친다 / 붙여넣는다 / 입력기 키 / 로그 / 돌려준다 | `takeover.e2e.mjs` |

## 실제 NotebookLM 실행
