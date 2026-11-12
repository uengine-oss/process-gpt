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

- 실행 환경: 튜토리얼 설치본(colima-pgtut, 192.168.64.3), 프런트는 process-gpt-vue3 `feat/phone-desktop-default-install-bar` 를 튜토리얼 빌드(`tutorial/combined-1110`)에 얹어 빌드해 올림, 계정은 관리자 · 2단계 인증 계정(mfa-phone).
- Playwright 설정의 `Desktop Chrome` 프로젝트가 `screen` 1920×1080 을 물려주므로 휴대폰 컨텍스트에는 `screen` 을 꼭 정한다.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 결과(2026-11-11 데스크톱 기본 · 홈 화면 띠 판) |
|---|---|---|
| 로그인한 뒤(→ 데스크톱 화면 1280px, 로그인은 390px 포털) | F-MV-01 · 단위 `phoneWeb.test.js` · `mobileView.test.js` | ✅ |
| 모바일 버전으로 업무 주소에 바로 들어옴 | F-MV-10 (`MV_TASK_ID`) · 단위 `phoneWeb.test.js` | ✅ |
| 라이트 모드로 포털 주소에 들어옴 | F-MV-18 · 단위 `phoneWeb.test.js` · `indexHtml.test.js` | ✅ (11-12, `/lite/`는 시험용 대체 화면) |
| 컴퓨터 | F-MV-07 | ✅ |
| 승인 · 반려(휴대폰 웹) | F-MV-12 (`MV_APPROVAL_TASK_ID`) · 휴대폰 웹 E2E 반려 9/9 | ✅ |
| 세 가지 선택지 | F-MV-17 | ✅ (11-12) |
| 모바일 버전으로 | F-MV-03 | ✅ |
| 라이트 모드로 | F-MV-18 | ✅ (11-12, `/lite/`는 시험용 대체 화면) |
| Lite가 없는 서버에서 라이트 모드 | F-MV-19 · 단위 `mobileView.test.js` | ✅ (11-12) |
| 라이트 모드에서 데스크톱 화면으로 돌아가기 | F-MV-20 · Lite 쪽 F-PT-01~03(process-gpt-lite `e2e/tests/feature/portal-link.spec.js`) | ✅ (11-12) |
| 데스크톱 화면으로 돌아가기 | F-MV-02 | ✅ |
| iPhone 안내 · 매니페스트와 아이콘 | F-MV-06 | ✅ |
| 띠에서 추가(위쪽 막대는 띠 아래) | F-MV-15 · 단위 `mobileView.test.js` | ✅ |
| 다시 보지 않기(휴대폰 웹 · 포털 모두) | F-MV-15 · F-MV-16 · 단위 `mobileView.test.js` | ✅ |
| 좁은 창에서 관리 주소 | F-MV-09 | ✅ |
| 좁은 창 사이드바 | F-MV-08 | ✅ |
| (결정 칸 — 포털 데스크톱) | F-MV-11 | ✅ |
| 로그인 전에 휴대폰 웹 주소 | F-MV-13 · 단위 `authGate.test.js` | ✅ |
| 비밀번호만 통과한 2단계 인증 계정 | F-MV-14 · 단위 `authGate.test.js` · `phoneWeb.test.js`(포털 라우터가 MFA 게이트 뒤에서만 옮김) | ✅ (고치기 전 #249 판에서는 ✗ — `/m/#/tasks` 가 열렸다) |
| (필수인데 미등록 → 등록 화면 → 휴대폰 웹, 앱은 로그아웃하고 알림) | 단위 `authGate.test.js` | ✅ (E2E 없음) |
| (PAL · uEngine · 네이티브 앱은 옮기지 않음, 운영 run.sh 주입 뒤에도 규칙이 남음) | 단위 `phoneWeb.test.js` · `indexHtml.test.js` | ✅ |

설치본(VM)은 프런트 컨테이너가 옛 run.sh 라 `/m/index.html` 에 `window._env_` 를 넣지 않는다 — 시험 때는 같은 블록을 손으로 넣었다(새 이미지의 run.sh 는 두 index.html 에 넣는다). 컨테이너를 다시 시작한 직후에는 옛 파일이 남아 있어, run.sh 가 끝나 http-server 가 PID 1 이 된 뒤에 넣어야 덮이지 않는다.

- 띠 안내 시험(F-MV-15 · 16)은 iPhone UA 로 돈다 — 헤드리스 크로미움은 설치 창(beforeinstallprompt)을 띄우지 않으므로 기기별 안내가 나온다.

- 튜토리얼 설치본에는 Process GPT Lite가 없다. F-MV-18 · 20은 `/lite/` 문서만 시험용 대체 화면으로 바꿔 실행하고(포털 문서는 건드리지 않는다), F-MV-19는 Lite가 없는 서버에서만 실행한다. 실제 Lite로 이동하는 동작은 운영에서 따로 확인한다.
- 시험 러너(Node)는 `UX_HOST_MAP`을 모른다. 설치본 화면 주소(`localhost:8088`)의 파일을 시험에서 받을 때는 `page.request`가 아니라 브라우저 안의 `fetch`로 받는다.

## 증거

`results/` 는 저장소에 올리지 않는다(.gitignore). 위 명령을 다시 돌리면 같은 자리에 생긴다.

2026-11-12 실행 결과(휴대폰 화면 세 가지 판, process-gpt-vue3 #259):

- 설치본(VM): `playwright/e2e/mobile-view` + `playwright/e2e/rev1112c` 18개 통과 · 3개 건너뜀(1.1분 — 업무 id가 필요한 F-MV-10 · 11 · 12). 처음에는 F-MV-06 · 18 · 19 · 20이 `ECONNREFUSED`로 실패했다(러너가 `localhost:8088`에 연결하지 못함). 브라우저 안의 `fetch`로 바꾼 뒤 통과했다.
- 단위 `src/shared/mobileView/*.test.js` 29개 통과. 전체 단위 1250 통과 · 15 실패(main과 같은 15개).
- Lite 쪽: `/lite/` 아래로 빌드한 Lite에서 F-PT-01 · 03 통과(F-PT-02 건너뜀), 루트 빌드에서 F-PT-01 · 02 통과(F-PT-03 건너뜀).

2026-11-11 실행 결과:

- 데스크톱 기본 · 홈 화면 띠 판: F-MV-01~16 14개 모두 통과(43초, `mobile-view-default-e2e.txt`), 단위 34개 통과, 전체 단위 1101 통과 · 15 실패(main 과 같은 15개 — 채팅 시험).
- 인증 관문 고친 판: F-MV-01~14 12개 모두 통과(33초, `mobile-view-auth-e2e.txt`), 단위 31개 통과(`unit-auth.txt`).
  고치기 전 판의 F-MV-13 · 14 실패 기록은 `mfa-before-fix.txt`.

- F-MV-01~07 6개 통과(1.1분, ux-review 묶음과 함께: 19 통과 · 3 건너뜀 — 업무 id 가 필요한 시험)
- 단위 15개 통과
- 화면: 질문 창 · 데스크톱 화면 · 라이트 버전 · 설정 · iPhone 안내 — 튜토리얼 2장 「휴대폰에서 열면」의 그림이 같은 실행에서 찍은 것이다(https://www.uengine.org/docs/process-gpt/tour.html)

## 아직 확인하지 않은 것

- 「라이트 모드」를 고른 뒤 실제 Process GPT Lite(`/lite/`)가 열리는지, Lite가 포털의 로그인 상태를 그대로 받는지 — Lite가 있는 운영 서버에서만 확인할 수 있다.
- 실제 휴대폰(iPhone Safari · 안드로이드 크롬)에서의 화면 폭 전환과 설치 창 — 에뮬레이션으로만 확인했다.
- 「필수인데 미등록 → 등록 → 휴대폰 웹」 흐름과 네이티브 앱의 로그아웃 안내 — 단위 시험만 있다.
