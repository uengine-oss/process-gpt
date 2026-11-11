# E2E — pgpt-pro_mcp-apps

Lite 앱 규약 v2(MCP Apps)를 실제 서버와 실제 DB, 실제 브라우저에서 확인한다. 앱 세 개(검토 보드·볼트 보드·산출물 보기)는 대역 세션(tmux 안의 Claude Code 선택 창 화면)으로 모델 호출 없이 실행한다. ArtCraft·이음오피스는 실제 웹 빌드와 실제 office-host로 실행한다. 결과 파일은 저장소의 `.gitignore`에 포함되어 올라가지 않는다. 사본은 `pgpt-pro/docs/robo-dlc/results/mcp-apps/`에 있다.

```bash
cd process-gpt-lite (feat/mcp-apps)/server
node --test test/apps.test.js                                                  # 규약·입구 도구·import 경계·ArtCraft·이음오피스·바이트·프록시 (21)
PRO_E2E_API=http://127.0.0.1:8799/api node --test test/apps.e2e.test.js        # 실제 서버 9단계: 검토 보드 흐름을 MCP 로, MCP 끝점 보호, 프록시 머리, 홈 패널
cd ../e2e && PGPT_URL=http://127.0.0.1:5198 API_URL=http://127.0.0.1:8799 \
  npx playwright test tests/feature/robo-dlc.spec.js tests/feature/editors-live.spec.js tests/feature/conversations.spec.js \
  tests/feature/english-fixes.spec.js tests/smoke -g "F-RD|F-ED|F-CR|F-CV-04|F-EN-02|S-30"
```

실행 환경: Supabase(Docker) + 기능 브랜치 BFF(`feat/mcp-apps`, `PRO_PORT=8799 PRO_BACKGROUND=0 PRO_AIDLC_WATCH=1`, 감시기는 임시 폴더의 시험 저장소만 `PRO_AIDLC_WATCH_ONLY`) + `vite preview --port 5198`(`/api`·`/craft`·`/office` 대리) + office-host(:5390) + ArtCraft 웹 빌드·CLI(`PRO_CRAFT_WEB_ROOT`, `PRO_<APP>_CLI`). 샌드박스 출처는 같은 미리보기의 다른 호스트 이름이다. 페이지는 `http://127.0.0.1:5198`, 샌드박스는 `PRO_APPS_SANDBOX_ORIGIN=http://localhost:5198`, `PRO_APPS_HOST_ORIGINS=http://127.0.0.1:5198`이다.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| 입구 도구와 화면 | 단위 「앱마다 입구 도구가 MCP Apps 화면(ui://)을 가리키고…」, E2E 8단계(실서버 `review_open` → `ui://review/board`) | `results/apps.test.txt`, `results/apps.e2e.txt` |
| 감시기 훅은 모델에게 숨는다 | 단위 같은 시험 | `results/apps.test.txt` |
| 토큰 없이 | E2E 8단계(401, GET 405) | `results/apps.e2e.txt` |
| 구성원이 아니다 | E2E 6·7단계(산출물 목록·세션 화면 403), 9단계(패널의 AI-DLC 읽기 403) | `results/apps.e2e.txt` |
| 남의 이름으로 카드 | E2E 8단계(`notify_user` 403) | `results/apps.e2e.txt` |
| import 경계 | 단위 「앱 코드는 호스트 모듈을 import 하지 않는다」 | `results/apps.test.txt` |
| 따로 도는 앱 | E2E 8단계(`/api/apps/_host/mcp`의 `aidlc_work`) | `results/apps.e2e.txt` |
| 정해지지 않은 화면으로 옮기기 | 단위 「앱 화면의 링크…」 | `results/apps.test.txt` |
| 다른 사람의 이의가 바로 보인다 | F-RD-06(두 브라우저) | `results/playwright.txt` |
| 편집기는 샌드박스 출처에서 | F-CR-<앱>(중첩 틀 출처 = `appsSandbox`), F-ED-01(이음오피스 틀 출처), 출처 실험(저장소·글꼴) | `results/playwright.txt`, `results/origin-experiment.txt` |
| 프록시를 남이 담는다 | E2E 8단계(`frame-ancestors`, sandbox 없음, 허락 출처 주입), 단위 「샌드박스 프록시…」(허락된 부모에게만 답함) | `results/apps.e2e.txt`, `results/apps.test.txt` |
| 출처가 필요한 앱만 | 단위 「들어 있는 앱의 매니페스트는 모두 규약 v2…」 | `results/apps.test.txt` |
| 패널 저장 | F-RD-09(화면에서 저장 → 다시 열기), E2E 9단계(남의 패널 404) | `results/playwright.txt`, `results/apps.e2e.txt` |
| 패널이 기록 밖을 읽는다 | E2E 9단계, 단위 `aidlc-cases.json` panelPath | `results/apps.e2e.txt` |
| 카드를 열면 연결된다 | F-CR-<앱> 다섯(대화와 연결됨 + 앱 MCP 도구가 열린 화면을 읽음), F-CR-10(도구로 레이어 추가 → 열린 문서), F-ED-04(다섯 앱 최대화 다이얼) | `results/playwright.txt` |
| 앱에서 저장 | F-CR-11 | `results/playwright.txt` |
| 누르면 멘션 | F-ED-05(셀 범위) | `results/playwright.txt` |
| 한글 그림 왕복 | F-ED-08, 영문 F-EN-02(워드 그림) | `results/playwright.txt` |
| 깨진 앱 둘 | 단위 「한 앱이 깨져도 다른 앱은 올라오고…」 | `results/apps.test.txt` |

바꾸기 전 기준선: ArtCraft 12개(F-CR 7·F-ED-04 다섯 앱)는 ArtCraft를 옮기기 전 빌드에서 통과했다. 편집기 묶음 21개는 이음오피스를 옮기기 전 빌드에서 실행했다(`results/editors-before.playwright.txt`). 그때 F-ED-08 하나가 ArtCraft 틀 주소를 바깥 틀에서 찾다가 실패했다. 검사 대상을 중첩 틀로 고친 뒤 통과했다.
