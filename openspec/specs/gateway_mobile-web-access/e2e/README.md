# 휴대폰으로 웹 포털 쓰기 — E2E

## 실행

```bash
# process-gpt-vue3 작업 트리에서. 설치본(VM, 비 PAL)에 붙은 프런트를 휴대폰처럼 연다(터치 · 390×844 · screen 도 390×844).
UX_BASE_URL=http://localhost:8088 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json \
npx playwright test playwright/e2e/mobile-view --workers=1

# 판단 규칙 단위 시험(묻기 · 새로 열기 · 저장 · 배율 · 설치 안내, index.html 규칙이 배포 뒤에도 살아 있는지)
node --test src/shared/mobileView/*.test.js
```

- 실행 환경: 튜토리얼 설치본(colima-pgtut, 192.168.64.3), 프런트는 process-gpt-vue3 `feat/mobile-desktop-default`(PR #245)를 빌드해 올림, 계정은 관리자 한 명.
- Playwright 설정의 `Desktop Chrome` 프로젝트가 `screen` 1920×1080 을 물려주므로 휴대폰 컨텍스트에는 `screen` 을 꼭 정한다.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 결과(2026-11-11 휴대폰 웹 배포 판) |
|---|---|---|
| 로그인한 뒤(→ 휴대폰 웹 할 일, 로그인은 390px 포털) | F-MV-01 | ✅ |
| 업무 주소로 바로 들어옴 | F-MV-10 (`MV_TASK_ID`) · 단위 `phoneWeb.test.js` | ✅ |
| 컴퓨터 | F-MV-07 | ✅ |
| 승인 · 반려(휴대폰 웹) | F-MV-12 (`MV_APPROVAL_TASK_ID`) · 휴대폰 웹 E2E 반려 9/9 | ✅ |
| 데스크톱 화면으로 | F-MV-02 | ✅ |
| 휴대폰 웹으로 돌아가기 | F-MV-03 | ✅ |
| iPhone 안내 · 매니페스트와 아이콘 | F-MV-06 | ✅ |
| 좁은 창에서 관리 주소 | F-MV-09 | ✅ |
| 좁은 창 사이드바 | F-MV-08 | ✅ |
| (결정 칸 — 포털 데스크톱) | F-MV-11 | ✅ |
| (PAL · uEngine · 네이티브 앱은 옮기지 않음, 운영 run.sh 주입 뒤에도 규칙이 남음) | 단위 `phoneWeb.test.js` · `indexHtml.test.js` | ✅ |

설치본(VM)은 프런트 컨테이너가 옛 run.sh 라 `/m/index.html` 에 `window._env_` 를 넣지 않는다 — 시험 때는 같은 블록을 손으로 넣었다(새 이미지의 run.sh 는 두 index.html 에 넣는다).

## 증거

`results/` 는 저장소에 올리지 않는다(.gitignore). 위 명령을 다시 돌리면 같은 자리에 생긴다. 2026-11-11 실행 결과:

- F-MV-01~07 6개 통과(1.1분, ux-review 묶음과 함께: 19 통과 · 3 건너뜀 — 업무 id 가 필요한 시험)
- 단위 15개 통과
- 화면: 질문 창 · 데스크톱 화면 · 라이트 버전 · 설정 · iPhone 안내 — 튜토리얼 2장 「휴대폰에서 열면」의 그림이 같은 실행에서 찍은 것이다(https://www.uengine.org/docs/process-gpt/tour.html)

## 아직 확인하지 않은 것

- 실제 휴대폰(iPhone Safari · 안드로이드 크롬)에서의 화면 폭 전환과 설치 창 — 에뮬레이션으로만 확인했다.
