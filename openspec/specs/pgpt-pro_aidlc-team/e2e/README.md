# E2E — pgpt-pro_aidlc-team

AI-DLC 저장소를 연결형 공유 폴더로 붙이고 팀 세션을 띄웠을 때, 사람을 기다리는 것이 역할 담당자에게 카드로 가고, 결정 화면의 결정이 세션의 선택 창에 들어가며, 질문 파일의 답이 적히는지 확인한다. 시험의 세션은 대역이다(tmux 안에서 Claude Code 선택 창 화면을 그리고 받은 키를 적는 스크립트). 실제 Claude Code + AI-DLC 로는 영상 판(`pgpt-pro/demo/product/robo-dlc-team-ko`)과 poc 탐색 판에서 같은 흐름을 돌렸다.

```bash
cd /Users/uengine/uengine-platform/process-gpt-lite-robodlc/server
node --test test/aidlc.test.js                                               # 선택 창 읽기(승인·요약·답하는 방식·권한), 답 쓰기
PRO_E2E_API=http://127.0.0.1:8798/api node --test test/aidlc-team.e2e.test.js   # 실제 서버 3단계 (PRO_AIDLC_WATCH=1)
cd ../e2e && PGPT_URL=http://127.0.0.1:5197 API_URL=http://127.0.0.1:8798 npx playwright test tests/feature/robo-dlc.spec.js -g "F-RD-0[45]"
node --test test/aidlc-ask.test.js                                           # P4 대화로 물은 것·훅·멈춘 화면·막힌 세션 (19)
```

실행 환경: Supabase(Docker) + 기능 브랜치 BFF(`feat/robo-dlc`, `PRO_PORT=8798 PRO_BACKGROUND=0 PRO_AIDLC_WATCH=1 PRO_AIDLC_PATH=<aidlc CLI>`) + `vite preview --port 5197`. 세션 tmux 소켓 `pgpt-aidlc`.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| 보기 권한은 읽기만 | F-RD-05 | `results/playwright.txt` |
| 서버가 다시 시작해도 세션이 이어진다 | 수동(실제 세션으로 서버 두 번 재시작) | 이 README |
| 코드가 만들어지는 중에 쉘에서 지시한다 | 실제 classic 실행(영상 판 30·32단계): 개발자가 작업실 쉘에 적은 글 → AI-DLC 세션 메시지 기록(`source: prompt`) → 화면 유닛 기능 설계 규칙의 출처 「사람 요청」 → 코드 계획 승인 창의 「제목 100자 제한」 → 생성된 앱의 E2E 「101자 제목 … 이유를 보여 주고 저장하지 않는다」 통과 | `results/steer-*.png`, 영상 |
| 구성원이 아닌 사람에게 역할 | E2E 1단계 | `results/e2e.txt` |
| 요구사항 단계의 승인 창 | E2E 2단계, F-RD-04 | `results/e2e.txt`, `results/playwright.txt` |
| 기다림이 끝나면 카드가 내려간다 | E2E 3단계 | `results/e2e.txt` |
| 코드 생성 중 도구 권한 | 단위 「세션 화면」(권한 창 고정 화면), 실제 poc 판 | `results/unit.txt` |
| PO 가 승인한다 | E2E 2단계, F-RD-04 | `results/e2e.txt` |
| 그새 바뀐 화면 | E2E 2단계 | `results/e2e.txt` |
| 수정 요청과 그 글 | 실제 세션(탐색 판·영상 판) | 영상 |
| 질문 세 개의 답 · 기록 밖 경로 | E2E 3단계, 단위 「질문 파일에 합의한 답 쓰기」 | `results/e2e.txt`, `results/unit.txt` |
| 몹 정교화 | 실제 서버 + 실제 세션(회의 받아쓰기는 typed lines): 합의 Q1~Q5, 보류한 Q6 은 비움 | 이 README, 영상 |
| 대화로 물은 승인 (P4) | E2E 4단계(훅 → 카드 → 「Approve」 가 입력창에), F-RD-14(훅 없이 화면만), 단위 사례 9개(실제 판 2 의 말) | `results/e2e-p4.txt`, `results/playwright-p4.txt`, `results/unit-p4-ask.txt` |
| 글이 필요한 선택지 (P4) | F-RD-14(「Request Changes」 → 입력칸에 「Request Changes: 」), 단위 사례 needsText | `results/playwright-p4.txt`, `results/unit-p4-ask.txt` |
| 말하고 멈춘 세션 (P4) | 단위 사례 「코드 생성으로 넘어가겠습니다.」, 실제 판 3(세션을 다시 띄운 뒤 빈 화면 → 「멈춰 있어요」 → 「계속 진행해 주세요」 → 다시 일함) | `results/unit-p4-ask.txt`, 이 README |
| 훅이 알리면 곧바로 (P4) | E2E 4단계(훅 뒤 6초 안 카드, 서명 없는 알림 403), 실제 판 3(실제 Claude Code 2.1.325 의 UserPromptSubmit·Stop 이 서버에 옴, `PRO_AIDLC_HOOK_LOG=1`) | `results/e2e-p4.txt`, 이 README |
| 일하는 중이거나 적는 중 (P4) | 단위 「화면」(녹화한 스피너 `✶ …(14s · ↓ 1.0k tokens)` · 백그라운드 대기 · 적는 중 · 흐린 제안 「Try "…"」은 적는 중이 아님) | `results/unit-p4-ask.txt` |
| 로그인이 풀린 세션 (P4) | E2E 5단계(StopFailure 훅 → 폴더 주인에게 「세션이 로그인되어 있지 않아요」, PO 에게는 없음), F-RD-16(훅 없이 실제 판 3 의 막힌 화면), 단위 「막힌 세션(화면)」, 실제 판 3(2026-11-14 10:11~10:29 KST 로그아웃 — 고치기 전 판은 이를 「멈춰 있어요」로 읽어 「계속」 100번) | `results/e2e-p4b.txt`, `results/playwright-p4b.txt`, `results/unit-p4b-ask.txt` |
| 오류 해결 전에 반복해서 보낸 「계속」 (P4) | E2E 5단계(두 번째 429, 입력창에 한 번), F-RD-16(두 번째 「방금 보냈어요」), 단위(같은 오류는 같은 카드) | `results/e2e-p4b.txt`, `results/playwright-p4b.txt`, `results/unit-p4b-ask.txt` |
| 오류 후 응답을 재개한 세션 · 도구의 오류 출력 (P4) | 단위 「막힌 세션(화면)」(오류 뒤 ⏺ 말이 있으면 null, `⏺ Bash(npm test)` 아래 「Error: 2 tests failed」는 null) | `results/unit-p4b-ask.txt` |
