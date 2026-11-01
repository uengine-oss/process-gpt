# pgpt-pro_context-repeat-request — 시험과 증거

실행(process-gpt-lite `feat/team-context`, `server/`):

```
node --test test/repeat.test.js                                   # 순수 함수 5
PRO_TENANT_HOSTS="<server/.env 값>,team.localhost=team-demo" node test/repeat.e2e.mjs   # BFF :8798 · 시드 team-demo · 실제 임베딩·게이트웨이 모델·에이전트(새로 하기)
cd ../e2e && PGPT_URL=http://localhost:5198 API_URL=http://127.0.0.1:8798 npx playwright test tests/feature/team-context.spec.js -g F-TC-08
```

| 스펙 시나리오 | 시험 |
|---|---|
| 내가 했던 요청을 말만 바꿔 다시 | `repeat.e2e.mjs` 1 (카드·에이전트 답 없음), F-TC-08 |
| 결과물이 다르면 묻지 않는다 | `repeat.e2e.mjs` 5, 판별 사례(표↔그래프·고객 B↔C·이번 주↔지난주·참고해서 다른 것) |
| 비공개 맥락은 후보가 아니다 | `repeat.e2e.mjs` 10, `repeat.test.js` 후보 단위 |
| 그 답 보기 | `repeat.e2e.mjs` 2, F-TC-08 |
| 같은 팀 최유나가 이미 만든 비교표 | `repeat.e2e.mjs` 6–9 |
| 새로 하기 | `repeat.e2e.mjs` 3–4, F-TC-08(fresh 로 다시 보냄) |

증거: `results/` — 단위·E2E·Playwright 출력, 영상 ① 2판 프레임.
