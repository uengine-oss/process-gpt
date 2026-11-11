# 휴대폰으로 웹 포털 쓰기 — E2E

## 실행

```bash
# process-gpt-vue3 작업 트리에서. 설치본(VM, 비 PAL)에 붙은 프런트를 휴대폰처럼 연다(터치 · 390×844 · screen 도 390×844).
UX_BASE_URL=http://localhost:8088 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json \
MV_TASK_ID=<김민지의 진행 중 업무 id> MV_APPROVAL_TASK_ID=<장진영이 처음 여는 승인/반려 업무 id> \
npx playwright test playwright/e2e/mobile-view --workers=1

# 판단 규칙 단위 시험(묻기 · 새로 열기 · 저장 · 배율 · 설치 안내, index.html 규칙이 배포 뒤에도 살아 있는지)
node --test src/shared/mobileView/*.test.js
# 휴대폰 웹의 인증 관문(세션 없음 → 포털 로그인, aal1 → 포털 2단계 인증, 필수 미등록 → 등록 화면, 앱은 로그아웃)
node --test mobile/src/lib/authGate.test.js
```

- F-MV-14 는 계정 파일의 `mfa`(TOTP 를 등록한 계정, `totp` 에 base32 비밀)가 있어야 돈다. 설치본에 그런 계정을 만드는 스크립트는
  GoTrue 관리 API 로 계정을 만들고 `/factors` 로 TOTP 를 등록 · 검증한 뒤 비밀을 계정 파일에만 쓴다(출력하지 않는다).
- 승인 업무 id 는 한 번도 저장하지 않은 것을 쓴다. 이미 「반려」를 저장한 업무면 F-MV-11 이 실패한다(값이 미리 골라져 보이므로).

- 실행 환경: 튜토리얼 설치본(colima-pgtut, 192.168.64.3), 프런트는 process-gpt-vue3 `fix/phone-web-auth` 를 튜토리얼 빌드(`tutorial/combined-1110`)에 얹어 빌드해 올림, 계정은 관리자 · 2단계 인증 계정(mfa-phone).
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
| 로그인 전에 휴대폰 웹 주소 | F-MV-13 · 단위 `authGate.test.js` | ✅ |
| 비밀번호만 통과한 2단계 인증 계정 | F-MV-14 · 단위 `authGate.test.js` · `phoneWeb.test.js`(포털 라우터가 MFA 게이트 뒤에서만 옮김) | ✅ (고치기 전 #249 판에서는 ✗ — `/m/#/tasks` 가 열렸다) |
| (필수인데 미등록 → 등록 화면 → 휴대폰 웹, 앱은 로그아웃하고 알림) | 단위 `authGate.test.js` | ✅ (E2E 없음) |
| (PAL · uEngine · 네이티브 앱은 옮기지 않음, 운영 run.sh 주입 뒤에도 규칙이 남음) | 단위 `phoneWeb.test.js` · `indexHtml.test.js` | ✅ |

설치본(VM)은 프런트 컨테이너가 옛 run.sh 라 `/m/index.html` 에 `window._env_` 를 넣지 않는다 — 시험 때는 같은 블록을 손으로 넣었다(새 이미지의 run.sh 는 두 index.html 에 넣는다).

## 증거

`results/` 는 저장소에 올리지 않는다(.gitignore). 위 명령을 다시 돌리면 같은 자리에 생긴다. 2026-11-11 실행 결과:

- 인증 관문 고친 판: F-MV-01~14 12개 모두 통과(33초, `mobile-view-auth-e2e.txt`), 단위 31개 통과(`unit-auth.txt`).
  고치기 전 판의 F-MV-13 · 14 실패 기록은 `mfa-before-fix.txt`.

- F-MV-01~07 6개 통과(1.1분, ux-review 묶음과 함께: 19 통과 · 3 건너뜀 — 업무 id 가 필요한 시험)
- 단위 15개 통과
- 화면: 질문 창 · 데스크톱 화면 · 라이트 버전 · 설정 · iPhone 안내 — 튜토리얼 2장 「휴대폰에서 열면」의 그림이 같은 실행에서 찍은 것이다(https://www.uengine.org/docs/process-gpt/tour.html)

## 아직 확인하지 않은 것

- 실제 휴대폰(iPhone Safari · 안드로이드 크롬)에서의 화면 폭 전환과 설치 창 — 에뮬레이션으로만 확인했다.
- 「필수인데 미등록 → 등록 → 휴대폰 웹」 흐름과 네이티브 앱의 로그아웃 안내 — 단위 시험만 있다.
