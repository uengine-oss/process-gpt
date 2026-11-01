# pgpt-pro-team-context — 시험과 증거

## 실행 환경
- 앱: process-gpt-lite 워크트리 `feat/team-context` — BFF `PRO_PORT=8798 PRO_BACKGROUND=0 PRO_TENANT_HOSTS=<기존>,team.localhost=team-demo node index.js`, Vite :5198 (`PRO_API_TARGET=http://127.0.0.1:8798`)
- Process GPT: Supabase(:54321·:54322), context-router :8895, judge :8896(임베딩 bge-m3), deepagents :8888 — 실제. 모델은 회사 게이트웨이(frentis), 판정·요약은 생각을 끈 호출(`think: false`)
- 시드: `server/scripts/seed-team-context.mjs --reset` — 테넌트 team-demo, 5명(윤서진 관리자 · 전략팀 박하늘 장·이도윤 · 제안팀 최유나 장·정하은), 대화 맥락 12개(등급 섞음), 맥락 요약은 실제 모델

## 실행
```
cd server
node --test test/context-visibility.test.js test/refer.test.js test/context-grade.test.js test/team-activity.test.js   # 82
node test/context-share.e2e.mjs      # 자동 참고 + 참고 요청, 8단계
node test/context-grade.e2e.mjs      # 공개 등급, 16단계 · 확인 63
node test/team-activity.e2e.mjs      # 팀 활동, 12단계
cd ../e2e && PGPT_URL=http://localhost:5198 npx playwright test tests/feature/team-context.spec.js   # F-TC-01…05
```
결과: `results/unit.txt`, `results/*.e2e.txt`, `results/playwright.txt` (2026-11-01, 모두 통과). 화면: `results/frame-*.png`(녹화 프레임).

## 스펙 시나리오 ↔ 시험
| 스펙 | 시나리오 | 시험 |
|---|---|---|
| context-visibility | 요약 공개를 같은 팀·다른 팀이 볼 때, 부서 범위, 팀장 덧씌움, 관리자도 원문은 요청, 비공개 404, 민감, 범위 이동 | `context-visibility-cases.json`(39), `context-grade.e2e.mjs` |
| context-visibility | 등급 미리보기(회사로 넓히면 정하은·최유나 새로), 민감 승인 뒤 전체 공개 422, 열람 기록 | `context-grade.e2e.mjs`, 영상 ② |
| context-auto-reference | 경쟁사 가격 → 내 맥락(원문)+박하늘(요약), 인용 블록, 관계없는 질문, 빼기, 끄기, 요청 후보, 「분기 정리」는 후보 아님 | `refer-cases.json`(16), `context-share.e2e.mjs` 1–4, F-TC-01·02 |
| context-auto-reference | 맥락 나누기는 원래 메시지로, 실제 턴에서 [1]·[2] 인용 | 영상 ①(실제 deepagents·라우터) |
| context-access-request | 같은 팀 자동 허용·다른 대화는 요약·하루 모음 카드, 다른 팀 묻기→홈 카드→원문·7일·턴 빼고 허락·409, 민감은 묻기, 비공개 404, 30건 429, 3일 만료, 쓰인 곳·회수 | `context-share.e2e.mjs` 5–8, F-TC-03 |
| role-based-notifications | context_access 카드 안에서 허락, 결과 카드 | F-TC-03, `context-share.e2e.mjs` |
| team-activity | 팀장 카드(문장 없음), 다른 팀은 제목·횟수, 시간순 깊이, 원문 보기 자동 허용, 조직도 403/모아 보기, 겹침(보는 사람의 글로만), 관리자 눈, 비공개로 바꾸면 바로 빠짐 | `team-activity.test.js`(16), `team-activity.e2e.mjs`, F-TC-04, 영상 ② |

## 영상
- ① 자동 참고와 참고 요청 — https://youtu.be/7jat7FFJeKw (1:40)
- ② 팀 활동과 공개 등급 — https://youtu.be/VJpa1aKFbUo (1:48)
