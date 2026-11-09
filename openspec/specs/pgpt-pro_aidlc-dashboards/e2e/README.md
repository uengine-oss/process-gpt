# E2E — pgpt-pro_aidlc-dashboards

AI-DLC 저장소를 연결형 공유 폴더로 붙였을 때, 폴더 구성원만 작업 요약을 보고, 요약 수치가 기록과 맞으며, 홈에 대시보드 패널 6개가 생기고 작업 사본의 변화가 패널에 스스로 반영되는지 실제 서버로 확인한다. 고정 자료는 AX School AI-DLC 핸즈온 레벨 2 실습 기록(사건을 대시보드가 읽는 것만 남김)과, 헤드리스로 시작해 첫 질문에서 멈춘 poc 기록이다.

```bash
cd /Users/uengine/uengine-platform/process-gpt-lite-robodlc/server
node --test test/aidlc.test.js                                   # 단위·사례(경로 16, 이름 10)·프리셋 패널 실행
PRO_E2E_API=http://127.0.0.1:8798/api node --test test/aidlc.e2e.test.js   # 실제 서버 6단계
cd ../e2e && PGPT_URL=http://127.0.0.1:5197 API_URL=http://127.0.0.1:8798 npx playwright test tests/feature/robo-dlc.spec.js
```

실행 환경: Supabase(Docker, kong :54321, db :54322) + 기능 브랜치 BFF 소스 실행(`feat/robo-dlc`, `PRO_PORT=8798 PRO_BACKGROUND=0`) + 화면 `vite build` 후 `vite preview --port 5197`(`PRO_API_TARGET=http://127.0.0.1:8798`).

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| 보기 권한 구성원은 프로젝트와 작업 목록을 본다 | E2E 2단계, F-RD-02 | `results/e2e.txt` |
| 구성원이 아니면 목록에도 없고 요약은 403 | E2E 2단계, F-RD-02 | `results/e2e.txt` |
| 끝난 classic 작업 | 단위 「감사 기록」·「유닛」·「요약」, E2E 3단계 | `results/unit.txt` |
| 팀 규칙 단계의 시간 | 단위 「설계 단계」 | `results/unit.txt` |
| 질문을 남기고 기다린 시간 | 단위 「질문을 남기고 사람을 기다린 시간은 AI 작업이 아니다」, 영상 | `results/unit.txt` |
| 진행 중인 poc 작업 | 단위 「질문」, E2E 3단계 | `results/unit.txt` |
| 시작 전 유닛은 의존이 풀린 것만 시작 가능 | 단위 「유닛 상태」 | `results/unit.txt` |
| 유닛을 알 수 없는 사건 | 단위 「유닛 표시가 없는 사건」 | `results/unit.txt` |
| 답을 다 적은 뒤의 요약 확인 | 단위 「요약 확인도 열린 질문」, 영상(실제 AI-DLC 헤드리스) | `results/unit.txt` |
| 승인 대기가 생긴다 | 단위 「승인 대기」, E2E 6단계 | `results/unit.txt`, `results/e2e.txt` |
| 상위 폴더로 가는 이름 · 없는 작업 | 단위 「이름 검사」·사례 `recordName`, E2E 4단계 | `results/unit.txt` |
| 여섯 개를 추가 · 구성원이 아니거나 없는 작업 | E2E 5단계, F-RD-01·02 | `results/e2e.txt` |
| 허용되는 경로 · 밖으로 나가는 경로 | 단위 「panel.aidlc 경로」·사례 `panelPath`(`server/test/aidlc-cases.json`) | `results/unit.txt` |
| 홈에서 보는 동안 승인 대기가 생긴다 | F-RD-03 | `results/playwright.txt` |
| 구성원이 아니게 된 뒤 처음 연다 | 단위 「프리셋 패널」 | `results/unit.txt` |
| 폴더에서 홈으로 | F-RD-01, 영상 | `results/playwright.txt`, `results/*.png` |

## 결과 (2026-11-09)

| 묶음 | 결과 | 파일 |
|---|---|---|
| 단위·사례·프리셋 | 18/18 통과 | `results/unit.txt` |
| 실제 서버 E2E | 6/6 통과(1.2초) | `results/e2e.txt` |
| 화면 회귀 F-RD-01~03 | 3/3 통과(25초) | `results/playwright.txt` |

녹화 전 화면 점검에서 세 가지를 고쳤다: 작업 현황의 프로젝트 줄이 낱말 가운데서 잘림, 볼트 보드에 "(missing marker)" 유닛, 감사 타임라인의 글자 그대로 `\n`.
녹화 1판(실제 AI-DLC 헤드리스)에서 하나를 더 찾았다: 답을 받은 AI-DLC 는 결과물을 쓰기 전에 질문 파일에 요약 확인 절을 붙이고 사람을 기다리는데, 대시보드가 이를 열린 질문으로 세지 않았다. 2판에서는 의도 정리의 「AI 작업 55분」을 보고, 질문 답을 기다린 53분이 AI 작업에 들어가던 것을 고쳤다(고정 자료에 질문·세션 사건을 되살림).
