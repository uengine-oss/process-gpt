## 1. 바탕

- [x] 1.1 `server/sql/029_team_context.sql`: 등급·규칙·장·요청·허락·참고·열람·요약 표 10개(RLS 켬, 정책 없음). 공용 DB 에 적용함
- [x] 1.2 시드 `server/scripts/seed-team-context.mjs`(`--reset|--live|--clean|--status`): 테넌트 team-demo, 5명, 조직도, 장, 맥락 12개(등급 섞음), 실제 모델로 만든 맥락 요약
- [x] 1.3 판정 사례 `server/test/context-visibility-cases.json`(39) — 같은 팀·다른 팀·부서·장·장의 장·관리자·민감·조직도 밖·두 팀·허락 만료 직전/직후·회수·다른 대화 — `context-visibility.test.js`

## 2. 자동 참고 (pgpt-pro_context-auto-reference)

- [x] 2.1 고르기 사례 `server/test/refer-cases.json`(기준 0.55, 회색 0.45~0.55, 판정 0.49/0.50, 판정 실패, 고정, 빼기, 세 대화 빼기 학습, 요청 후보 0.5, 상한) — `refer.test.js`
- [x] 2.2 `lib/agent.js` 연결: 턴 앞 고르기 → 인용 블록 + 사람 메시지의 고른 결과, 답·요청의 맥락 표지, 턴 뒤 요약 다시 만들기
- [x] 2.3 화면: 사람 메시지 아래 칩(빼기·고정·원문 요청·자동 참고 끄기), 답 아래 요청 후보, 「지금 반영해 다시 답하기」
- [x] 2.4 HTTP E2E `server/test/context-share.e2e.mjs` 1~4단계(고르기·관계없는 질문·빼기·끄기)

## 3. 참고 요청 (pgpt-pro_context-access-request)

- [x] 3.1 같은 팀 자동 허용 → 다음 턴 원문, 다른 대화는 요약, 하루 모음 카드
- [x] 3.2 다른 팀 묻기 → 홈 카드(미리보기) → 원문·7일·턴 빼고 허락 → 409 재결정, 카드 내려감, 요청자 결과 카드
- [x] 3.3 민감은 묻기, 비공개 404(관리자 포함, 제목 없음), 하루 30건 429, 3일 만료
- [x] 3.4 쓰인 곳 → 회수 → 다음 턴 요약, 회수 카드, 맥락 보기도 요약

## 4. 공개 등급·팀 활동

- [x] 4.1 등급 선택·미리보기·민감 제안 승인, 맥락 보기, 설정 › 공유와 허락 — `server/test/context-grade.test.js`(11)·`context-grade.e2e.mjs`(16단계, 확인 63)
- [x] 4.2 팀 활동 카드·시간순·조직도·겹침·다른 사람 눈으로 — `server/test/team-activity.test.js`(16)·`team-activity.e2e.mjs`(12단계). 시험이 진행 중 작업 줄의 제목 누출을 잡아 고침

## 5. 회귀·증거·문서

- [x] 5.1 Playwright `e2e/tests/feature/team-context.spec.js`(F-TC-01…05), 카탈로그 `e2e/README.md` 절
- [x] 5.2 이 변경의 스펙 증거(`e2e/results/`)
- [x] 5.3 영상 2편(7jat7FFJeKw · VJpa1aKFbUo, 일부 공개), 튜토리얼 27장 「팀 맥락 공유」, 제품 소개 07 팀 협업 — 영문판 미반영
