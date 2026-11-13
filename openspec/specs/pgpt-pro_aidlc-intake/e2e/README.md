# E2E — pgpt-pro_aidlc-intake

작업 접수와 볼트 줄(Lite 앱 둘: `intake` · `line`, 앱 규약 v2는 `pgpt-pro_mcp-apps`)을 실제 서버와 실제 DB를 사용해 확인한다. 시험에서 범위 추정은 고정 답(`PRO_AIDLC_COMPOSE_STUB`, 추정할 때마다 다시 읽는 JSON)이고, 세션에는 `pgpt-pro_aidlc-team`과 같은 대역(tmux 안에서 화면을 그리고 받은 키를 적는 스크립트)을 써서 모델을 호출하지 않는다. 실제 Claude Code + AI-DLC 2.11.2 한 판(운영 중인 「회의실 예약」 저장소에 알림 메일 중복 버그 접수 → 줄 끝에 반복 예약 → 맞지 않는 요청 → 보안 멈춤 → 폐기)은 영상 판(`pgpt-pro/demo/product/robo-dlc-intake-ko`)에서 같은 단계로 돌렸고, 그 화면을 `results/real-*.png`에, 해당 실행의 기록(계획안·볼트 키·원장·걸린 시간)을 `results/real-run.json`에 두었다. 영상은 유튜브 `JzDnkSjWzOU`(작업 접수) · `WdA-gH8igrc`(볼트 줄)이다. 결과 파일은 저장소의 `.gitignore`에 지정되어 올라가지 않으며 사본이 `pgpt-pro/docs/robo-dlc/results/intake/`에 있다.

```bash
cd /Users/uengine/uengine-platform/process-gpt-lite-mcpapps/server            # feat/mcp-apps
node --test test/aidlc.test.js test/aidlc-line.test.js test/aidlc-snapshot.test.js   # 화면 읽기·보관 · 줄 계산(사례 JSON) · 되돌리기 (36)
node --test test/aidlc-chat-router.test.js                                     # 대화 갈래(라우터 모델을 거침)
PRO_E2E_API=http://127.0.0.1:8795/api node --test --test-concurrency=1 test/aidlc-intake.e2e.test.js test/aidlc-chat.e2e.test.js
cd ../e2e && PGPT_URL=http://127.0.0.1:5191 API_URL=http://127.0.0.1:8795 npx playwright test --project=feature tests/feature/robo-dlc.spec.js -g "F-RD-1[0-3]"
```

실행 환경: Supabase(Docker) + 기능 브랜치 BFF(`feat/mcp-apps`, `PRO_PORT=8795 PRO_BACKGROUND=0 PRO_AIDLC_WATCH=1 PRO_AIDLC_WATCH_ONLY=<임시 폴더> PRO_AIDLC_COMPOSE_STUB=<고정 답 파일>`) + `vite preview --port 5191`(고정 빌드). 표 `pro_aidlc_requests` · `pro_aidlc_line`은 `server/sql/041_aidlc_intake.sql` 이다. 실제 판은 따로 띄운 서버(`PRO_PORT=8789`, 고정 답 없음, 감시 폴더 = 녹화용 저장소)에서 돌렸다.

판단 사례: `server/test/aidlc-line-cases.json` — 볼트 줄의 묶음(내보냄·지금·다음 릴리스·줄 끝), 의존을 깨는 이동, 함께 옮길 볼트, 내보낼 수 있는지. 줄 계산이 바뀌어 판단 결과가 달라지면 이 시험이 실패한다.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| 버그를 적으면 bugfix 를 추천한다 | E2E S1, F-RD-11, 실제 실행(「예약 알림 메일이 두 번 와요」 → bugfix · 유닛 하나) | `results/e2e.txt`, `results/playwright.txt`, `results/real-plan.png` |
| 기록에 없는 유닛은 싣지 않는다 | E2E S1(고정 답에 없는 유닛을 섞어 넣음 → 계획안에서 빠지고 빠진 목록에 남음) | `results/e2e.txt` |
| 접수 권한이 없는 사람의 요청은 접수함으로 간다 | E2E S1, 대화 E2E 「대놓고 말하기」, F-RD-10 | `results/e2e.txt`, `results/playwright.txt` |
| 진행 중인 작업이 있으면 지금 시작은 거절된다 | E2E S3(도는 볼트가 있을 때 「지금 시작」 → 409), 실제 실행(두 번째 요청에는 「앞 작업 뒤에 세우기」만 열림) | `results/e2e.txt`, `results/real-queued.png` |
| 처음 여는 폴더는 사람이 믿는다고 답한 뒤에 시작한다 | 단위 「처음 여는 폴더의 "믿을 수 있나요"…」, E2E S1(대역이 믿기 화면을 그림 → `trust` → 답한 뒤 `/aidlc`), F-RD-11, 실제 실행(Claude Code가 처음 여는 저장소 사본) | `results/unit.txt`, `results/e2e.txt`, `results/playwright.txt`, `results/real-trust.png` |
| 세션이 만든 의도가 요청과 이어진다 | E2E S1(감시기 한 바퀴 뒤 요청에 의도 · 줄의 「도는 중」 볼트), 실제 실행(엔진이 만든 의도가 수 초 뒤 요청의 유닛으로 줄에 섬) | `results/e2e.txt`, `results/real-line-running.png` |
| 대화에 적은 요청의 계획안이 카드로 온다 | 대화 E2E 「대놓고 말하기」, F-RD-10, 실제 실행(팀 리드의 「작업 접수: …」) | `results/e2e.txt`, `results/playwright.txt`, `results/real-chat-card.png` |
| 두 프로젝트에 있으면 어느 프로젝트인지 묻는다 | 대화 E2E 「두 프로젝트에 있는 사람에게는…」, 대화 갈래 시험 | `results/e2e.txt`, `results/unit.txt` |
| 줄 끝에 세운 기능이 유닛마다 볼트로 선다 | 사례 JSON, E2E S2, F-RD-12, 실제 실행(「반복 예약」 → 줄 끝 볼트 셋) | `results/unit.txt`, `results/e2e.txt`, `results/playwright.txt`, `results/real-tail.png` |
| 기대는 볼트를 두고 혼자 앞으로 갈 수 없다 | 사례 JSON, E2E S2(409 + 함께 옮길 볼트), F-RD-12, 실제 실행(「함께 옮기기」) | `results/unit.txt`, `results/e2e.txt`, `results/playwright.txt`, `results/real-blocked.png` |
| 없앨 것을 고치는 볼트가 돌고 있다 | E2E S3(고정 답), 실제 실행(추정이 도는 볼트를 이름으로 가리키고 까닭을 붙임 — 그 판의 판단은 「함께 갈 수 있음」, 모델의 판단) | `results/e2e.txt`, `results/real-conflict.png` |
| QA 가 보안 사유로 멈춘다 | E2E S4(멈춤 권한 없는 사람 · 대역 세션이 받은 키 = Esc 하나), F-RD-13, 실제 실행 | `results/e2e.txt`, `results/playwright.txt`, `results/real-stopped.png` |
| 까닭 없이는 폐기되지 않는다 | E2E S3 · S4(400), F-RD-13 | `results/e2e.txt`, `results/playwright.txt` |
| 멈춘 볼트를 폐기하면 줄의 앞이 빈다 | E2E S4, F-RD-13, 실제 실행(의도 보관 · 줄 머리 비움 · 원장) | `results/e2e.txt`, `results/playwright.txt`, `results/real-discarded.png`, `results/real-ledger.png` |
| 고친 파일은 시작 전으로, 기록은 그대로 | 단위(되돌리기 스냅숏), E2E S3(바뀐 파일·새 파일 → 시작 전, `aidlc/`는 그대로), F-RD-13 | `results/unit.txt`, `results/e2e.txt`, `results/playwright.txt` |

## 시험이 못 덮는 것

- 범위 추정의 질: 시험은 고정 답으로 실행한다. 실제 추정(헤드리스 Claude Code 한 번, 그 판에서 53 · 64 · 86초)은 실제 판에서만 확인했고, 맞지 않는 요청을 짚는 것은 모델의 판단이라 놓칠 수 있다. 실제 판에서는 도는 볼트와 「함께 갈 수 있음」으로 보았고, 「맞지 않음」이 나오는 경우는 고정 답 시험에만 있다.
- Esc 한 번이 뒤에서 도는 하위 에이전트까지 멈추는지는 화면으로 확인하지 못했다(폐기 때 세션에 그만하라는 말을 따로 보낸다). 실제 판에서 세션은 권한을 묻던 중이었고, Esc 하나로 그 자리에서 멈췄다.
- 고친 파일 되돌리기: 실제 판은 코드를 고치기 전에 폐기해 되돌릴 파일이 0개였다. 바뀐 파일·새 파일을 시작 전으로 돌리는 것은 E2E S3과 단위 시험이 확인한다.
- 메신저 방에서의 접수, 작업 트리(유닛마다 가지) 격리는 구현 범위 밖이다. 공개 저장소 `docs/robo-dlc/plan-p3-impl.md`의 「남은 공백」에 적었다.
| 범위를 알고 있는 팀 리드 (P4) | E2E S5, F-RD-15 | `results/e2e-p4.txt`, `results/playwright-p4.txt` |
| 접수 권한이 없는 사람 (P4) | E2E S5(개발자 403, 없는 범위 400) | `results/e2e-p4.txt` |
| classic 을 작업 트리로 (P4) | E2E S5(세션에 들어간 말·결정 기록), F-RD-15, 실제 판 3(「팀 공지 게시판」: 세션이 「유닛 병렬 구축으로 진행합니다」) | `results/e2e-p4.txt`, `results/playwright-p4.txt` |
| bugfix 는 기본으로 꺼져 있다 (P4) | F-RD-11(켜짐 아님 · 요청에 말이 붙지 않음) | `results/playwright-p4.txt` |
