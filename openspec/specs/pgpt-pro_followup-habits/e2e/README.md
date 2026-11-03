# 검증: 후행 습관

## 실행
- 실제 BFF(`PRO_PORT=8794 PRO_BACKGROUND=0`) + 공용 Supabase + 공용 deepagents + 회사 게이트웨이 모델 `frentis-ai-model`. Vite `PRO_API_TARGET=http://127.0.0.1:8794 vite --port 5196`. 표는 `server/sql/031_followups.sql`.
- 규칙: `cd server && node --test test/followups.test.js` (사례 `test/followups-cases.json`)
- HTTP E2E(실제 모델, 수락 단계는 실제 에이전트): `cd server && API_URL=http://localhost:8794 node test/followups.e2e.mjs`
- 화면(모델 없음): `cd e2e && PGPT_URL=http://localhost:5196 API_URL=http://localhost:8794 npx playwright test --project=feature tests/feature/followups.spec.js`
- 끝까지(실제 에이전트가 슬라이드를 세 번 만든다): `… --project=agent tests/agent/followups.spec.js`
- 판단 품질: `cd server && node scripts/eval-followups.mjs all test --check` (사례 `test/followup-eval/*.json` 260건, 구현을 모르는 별도 에이전트가 작성. 문구와 기준은 dev 절반으로만 정함)

## 시나리오 ↔ 시험
| 시나리오 | 시험 |
|---|---|
| 결과물 뒤에 후행 작업을 시킨다 | `followups.e2e.mjs` 2·3, A-FU-01 |
| 결과물에 대한 말은 에이전트가 받는다 | `followups.e2e.mjs` 4, A-FU-01 |
| 감사와 내용 질문은 습관이 아니다 | `followups.e2e.mjs` 5, `eval` followup |
| 다른 말로 같은 일을 시킨다 | `followups.e2e.mjs` 6, `eval` same_action |
| 새 대화에서 슬라이드가 나온다 | `followups.e2e.mjs` 7, A-FU-01, F-FU-01 |
| 묻지 않는 경우 | `followups.e2e.mjs` 8·14·15, `followups.test.js` |
| 어울리지 않는 결과물 | `eval` fits |
| 모델이 읽지 못한다 | `followups.e2e.mjs` 20 |
| 네를 누른다 | `followups.e2e.mjs` 11, A-FU-01, F-FU-02 |
| 말로 사양한다 | `followups.e2e.mjs` 10, `eval` answer |
| 말로 수락한다 | `followups.e2e.mjs` 12, `eval` answer |
| 답이 아닌 말 | `followups.e2e.mjs` 13, `eval` answer |
| 연달아 거절한다 | F-FU-04, `followups.test.js` |
| 두 번 답한다 | `followups.e2e.mjs` 9 |
| 직접 말한다 | `followups.e2e.mjs` 18, F-FU-10 |
| 습관이 아닌 말 | `followups.e2e.mjs` 19, `eval` explicit |
| 습관을 관리한다 | F-FU-05·06·07, `followups.e2e.mjs` 14·17 |
| 남의 습관 | `followups.e2e.mjs` 15 |
| 잘못된 요청 | `followups.e2e.mjs` 16 |
| 영어 모드 | F-FU-09, `followups.test.js` |

## 판단 품질(test 절반, 회사 게이트웨이 모델)
수치는 `results/eval-test.txt`. 사람이 쓴 뚜렷한 글이고, `frentis-ai-model` 하나로만 쟀다.

| 판단 | test | 쓰는 기준 |
|---|---|---|
| 후행 작업인가 | 33건 100% | 0.7 |
| 같은 일인가 | 28건 89% | 0.6 |
| 물어봐도 되는가 | 26건 88% (dev 24건 67%, 합쳐 50건 78%) | 0.7 |
| 말로 한 답 | 25건 96% | 0.5 |
| 직접 말한 습관 | 25건 96%, 결과물 종류 11/11 | 0.5 |

「물어봐도 되는가」의 문구와 기준은 test 를 한 번 읽은 뒤 실제 실행(논문 요약 슬라이드를 막음) 때문에 바꿨다. 그래서 이 항목의 test 는 깨끗한 평가가 아니고, 틀린 쪽은 대부분 **묻지 않아도 될 때 묻는 것**이다. 처음 문구는 test 88%였지만 논문 요약 슬라이드(p=0.32)를 막았다.
