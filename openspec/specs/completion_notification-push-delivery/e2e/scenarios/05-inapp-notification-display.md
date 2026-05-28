# E2E 시나리오 05: 인앱 알림 표시와 클릭 읽음 처리

## 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `로그인한 사용자는 새 알림이 도착하면 헤더 벨 배지와 드롭다운에서 확인하고 클릭으로 읽음 처리할 수 있다`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`

## 목적
본 명세의 "미처리 알림 자동 전달" 요구사항이 외부 FCM 푸시뿐 아니라 **실제 웹 SPA 의 인앱 알림 UI** 로도 사용자에게 전달됨을 검증한다. 사용자는 `services/frontend` 의 헤더 벨 아이콘(`NotificationDD.vue`)을 통해 미확인 알림 카운트 배지와 드롭다운 목록을 확인하고, 항목을 클릭해 해당 URL 로 이동하면서 `notifications.is_checked = true` 로 마킹된다. Real-Frontend Rule 재평가에 따른 신규 사용자-facing 시나리오이다.

## 사전 조건
- 전체 Docker Compose 스택이 기동되어 있다 (`db`, `kong`, `auth`, `rest`, `frontend`, `gateway`, `fcm-service`).
- 시드(`e2e_seed.sql`) 가 다음을 보장한다:
  - `auth.users` + `public.users` 에 로그인 가능한 테스트 사용자 `e2e-fcm-ui@uengine.org` / `e2epassword`, `tenant_id = localhost`.
  - `public.user_devices` 에 동일 사용자의 디바이스 토큰 (인앱 표시와 무관하지만 다른 시나리오와 동일 구조 유지).
- 본 시나리오 시작 시점에는 해당 사용자에 대한 미확인 알림 행이 존재하지 않거나 모두 `is_checked=true` 이다 (테스트 첫 단계에서 PostgREST 로 명시적으로 정리).
- 푸시 폴링 워커가 인앱 행을 가로채지 못하도록, 테스트가 새 알림 행을 INSERT 할 때 `consumer = 'inapp-ui-test'` (NULL 아님) 로 설정한다. 폴링 워커는 `consumer IS NULL` 만 클레임하므로 해당 행은 FCM 전송 대상에서 제외된다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_notification-push-delivery/e2e/seed_files/e2e_seed.sql` | 로그인 사용자 + `public.users` 행 + 디바이스 토큰 |
| PostgREST INSERT | setup | `POST {SUPABASE_REST}/notifications` (Service Role) | 인앱 알림 행 도착 모사. 실제 트리거(`handle_chat_insert`, `handle_todolist_change`) 는 본 명세의 책임 범위가 아니므로 결과물(행 도착) 만 모사한다. |
| `firebase_patch.py` | (해당 없음) | - | 본 시나리오는 FCM 전송을 트리거하지 않는다 (`consumer != NULL` 시드). |

## 절차
1. 테스트 시작 시 PostgREST 로 `notifications` 테이블의 `user_id = 'e2e-fcm-ui@uengine.org'` 인 모든 미확인 행을 `is_checked = true` 로 정리한다.
2. Playwright 가 `frontend`/`gateway` 진입점(`http://localhost:8088/auth/login`) 으로 이동한다.
3. 사용자가 이메일/비밀번호 입력 칸을 채우고 로그인 버튼을 클릭한다.
4. SPA 메인 레이아웃이 렌더링된 뒤 헤더에 벨 아이콘이 나타나는지 확인한다 (체크포인트 `01-after-login-bell-idle`).
5. PostgREST 로 새 알림 행을 INSERT 한다:
   - `id = <고정 UUID>` (예: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0005`)
   - `user_id = 'e2e-fcm-ui@uengine.org'`
   - `title = '신규 워크아이템'`
   - `description = '담당 업무를 확인하세요'`
   - `type = 'workitem'`
   - `url = '/todolist'`
   - `is_checked = false`
   - `from_user_id = '프로세스봇'`
   - `tenant_id = 'localhost'`
   - `consumer = 'inapp-ui-test'` (폴링 워커가 클레임하지 않도록)
   - `time_stamp = now()`
6. SPA 의 `backend.watchNotifications` Supabase realtime 채널이 INSERT 이벤트를 수신해 `notiCount > 0` 이 되고 벨 옆 점 표시(`.notify`) 가 활성화되는지 확인한다. 활성화될 때까지 최대 15초 폴링 (체크포인트 `02-bell-badge-active`).
7. 벨 아이콘을 클릭해 드롭다운을 열고 알림 항목이 한 줄로 나열되는지 확인한다 (제목 `신규 워크아이템`, 설명 `담당 업무를 확인하세요`) (체크포인트 `03-dropdown-list`).
8. 알림 항목을 클릭한다. SPA 가 `/todolist` 로 라우팅되고 `backend.setNotifications(value)` 가 호출되어 DB 의 해당 행 `is_checked = true` 로 마킹된다 (체크포인트 `04-after-click-routed`).
9. PostgREST 로 해당 행을 다시 조회해 `is_checked = true` 임을 검증한다 (보조 증거 JSON 으로 저장).

## 기대 결과
- 로그인 직후 헤더에 벨 아이콘이 표시되고 미확인 카운트는 0 이다.
- INSERT 후 15초 이내에 `notiCount` 가 1 이상으로 증가하고 벨 옆 알림 점 표시(`.notify`) 가 활성화된다.
- 드롭다운에 신규 알림 항목이 표시되고, 항목의 제목/설명이 시드 값과 일치한다.
- 항목 클릭 후 페이지 경로가 `/todolist` 로 이동하고, `notifications` 행의 `is_checked` 가 `true` 로 변경된다.
- 스크린샷 4개가 `openspec/specs/completion_notification-push-delivery/e2e/results/screenshots/` 아래에 생성된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | 미처리 알림 전달, 알림 메시지 구성 (인앱 표시 경로) |

## 산출물
- 스크린샷 (각 항목은 매뉴얼 캡션 포함):
  - `process-gpt-completion_notification-push-delivery-05-01-after-login-bell-idle.png` — 로그인 직후 헤더 벨 (미확인 0)
  - `process-gpt-completion_notification-push-delivery-05-02-bell-badge-active.png` — 새 알림 도착 후 벨 배지 활성화
  - `process-gpt-completion_notification-push-delivery-05-03-dropdown-list.png` — 드롭다운에 알림 항목 표시
  - `process-gpt-completion_notification-push-delivery-05-04-after-click-routed.png` — 항목 클릭 후 `/todolist` 라우팅 + 드롭다운 닫힘
- 결과 JSON: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- 보조 증거: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/05-inapp-display.json` (INSERT 페이로드 + 최종 `is_checked` 검증 스냅샷)
- Trace/video: Playwright 실패 시 보존된다.
