# 알림 푸시 전달 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`
- 백엔드/제품 계약:
  - `services/completion/fcm_service` 알림 워커 + FastAPI: `fcm_service.send_notification`, `fcm_service.get_device_token`, `fcm_service.health_check`, `fcm_service.notification_polling_task`
  - 데이터베이스 어댑터: `services/completion/fcm_service/database.py` 의 `fetch_device_token`, `send_fcm_message`, `handle_new_notification`, `fetch_unprocessed_notifications`, `check_new_notifications`
  - 데이터 계약: `public.user_devices(user_email, device_token)`, `public.notifications(id, user_id, title, type, description, is_checked, from_user_id, consumer, tenant_id, url, time_stamp)`
  - DB 트리거 경로: `public.notifications` 행은 (a) `handle_chat_insert()` (chat_rooms 메시지 트리거), (b) `handle_todolist_change()` (todolist IN_PROGRESS 진입 트리거), (c) 다른 서비스의 직접 INSERT 로 생성된다. 본 명세는 트리거 자체가 아니라 그 행이 생성된 이후 FCM 으로 전달되고 + 인앱 UI 에 표시되는 단계를 검증한다.
  - 외부 boundary: Firebase Cloud Messaging — 모바일 단말 도달은 리포지토리 경계 밖. E2E 에서는 `firebase_admin.messaging.send` 를 결정적으로 가로채는 `firebase_patch.py` 로 대체하고 캡처 파일을 검증한다.

## 사용자 검증 표면 (Real-Frontend Rule 재평가)
본 명세는 일부 요구사항이 백엔드 서비스-투-서비스 계약이지만, "사용자에게 알림이 도착했음을 알리는 사용자 가치"는 두 갈래로 실제 UI 에 존재한다.
1. **인앱 알림 표시 UI (실제 프론트엔드)**: `services/frontend/src/layouts/full/vertical-header/NotificationDD.vue` 의 벨 아이콘 + 미확인 카운트 배지 + 드롭다운 + 클릭 라우팅 + `is_checked=true` 마킹. 백엔드의 알림 행 생성은 `backend.watchNotifications` (Supabase realtime 채널 `notifications`) 로 SPA 가 수신하여 즉시 화면에 반영한다. → 시나리오 05 가 이 경로를 사용자 액션(로그인 → 헤더 벨 클릭 → 알림 항목 클릭 → 라우팅 + 읽음 처리) 으로 구동하고 스크린샷을 남긴다.
2. **모바일 푸시 도달 (외부 FCM)**: Firebase → 단말 사이는 리포지토리 외부 책임 영역이라 사용자 UI E2E 가 불가능하다. → 시나리오 03/04 에서 백엔드 계약 (`/send-notification` REST 응답, 캡처된 FCM 메시지, `notifications.consumer` 클레임 상태) 만 검증하고, Real-Frontend Rule 의 사용자-facing UI 시나리오 및 스크린샷 의무는 면제한다 (사유: 리포지토리 경계 밖, FCM SDK 가 단말 OS 에 의해 처리).
3. **REST 헬스/토큰 조회 (`/health`, `/device-token/{user_id}`)**: 운영/다른 백엔드용 점검 엔드포인트로 사용자 UI 가 직접 호출하지 않는다. → 시나리오 01/02 는 비-사용자-facing 프로토콜 테스트로 유지하고 스크린샷 의무를 면제한다.

- E2E 루트: `openspec/specs/completion_notification-push-delivery/e2e/`
- Playwright 명세:
  - 백엔드 프로토콜: `openspec/specs/completion_notification-push-delivery/e2e/tests/completion_notification-push-delivery.spec.mjs`
  - 인앱 UI: `openspec/specs/completion_notification-push-delivery/e2e/tests/notification-display.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_notification-push-delivery/e2e/results/`

## 재사용 산출물
- `docker-compose.e2e.yml`: 기존 `db`(supabase/postgres), `kong`, `auth`, `rest`, `frontend`, `gateway` 인프라를 그대로 재사용한다. 본 스위트용으로 `fcm-service`, `fcm-firebase-capture` 볼륨, `db-seed-notification-push-delivery` 시드를 사용한다. 인앱 UI 시나리오는 `frontend` + `gateway` (:8088) 의 실제 SPA 진입점을 그대로 사용한다.
- 메모리: [[coverage-py-usr2-flush]] (long-running uvicorn 의 `coverage.py` flush 패턴을 폴링 워커에도 동일 적용), [[mem0-vecs-table-reinit]] (DB 컨테이너 재시작 시 초기화 주의 — 본 스위트는 별도 시드만 사용하므로 직접 영향은 없지만 동일 db 컨테이너 공유 시 참고).
- 로그인 + 라우팅 패턴: `openspec/specs/completion_process-workitem-submission/e2e/tests/completion_process-workitem-submission.spec.mjs` 의 `login(page)` 헬퍼를 본 스위트에서 재사용한다 (`.cp-id`/`.cp-pwd`/`.cp-login` 셀렉터, `/auth/login` 경로).
- `openspec/specs/completion_automated-task-execution/e2e/docker/Dockerfile.polling-coverage` 의 coverage 패턴(서명/USR2 + coverage combine + xml/html 생성)을 참고해 본 스위트용 `Dockerfile.fcm-coverage` 를 작성한다.

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 | 사용자-facing 여부 |
| --- | --- | --- | --- | --- |
| 01 | `01-health-check.md` | `FCM 서비스 헬스 엔드포인트는 정상 상태와 서비스 이름을 반환한다` | GET /health 응답이 `{status:"healthy", service:"fcm-service"}` | 아니오 (운영용 프로토콜) |
| 02 | `02-device-token-lookup.md` | `등록된 사용자는 device_token 을 반환하고 미등록 사용자는 빈 토큰을 반환한다` | user_devices 시드 후 GET /device-token/{user_id} 두 경우 | 아니오 (서비스 간 프로토콜) |
| 03 | `03-send-notification-on-demand.md` | `POST /send-notification 은 발신자 제목·결합 본문·data 페이로드로 FCM 메시지를 구성한다` | 온디맨드 전송 + 캡처 검증 (from_user_id 제목 규칙, data.type/url 포함) | 아니오 (외부 FCM 도달 — 면제) |
| 04 | `04-unprocessed-notification-polling.md` | `consumer 가 비어 있는 알림 행은 폴링 워커가 클레임하고 FCM 으로 전달한다` | 시드된 알림 행이 consumer 로 채워지고 캡처에 도달 | 아니오 (외부 FCM 도달 — 면제) |
| 05 | `05-inapp-notification-display.md` | `로그인한 사용자는 새 알림이 도착하면 헤더 벨 배지와 드롭다운에서 확인하고 클릭으로 읽음 처리할 수 있다` | 실제 SPA 로그인 → 알림 행 도착 → 벨 배지/드롭다운 표시 → 클릭 라우팅 + is_checked=true | **예 (실제 프론트엔드 UI + 스크린샷)** |

> 시나리오 05 는 Real-Frontend Rule 에 따라 신규 추가되었다. 시나리오 03/04 의 외부 FCM 도달 부분은 리포지토리 경계 밖이므로 사용자-facing UI 의무가 면제되며 백엔드 프로토콜 증거(REST 응답 + 캡처 JSONL + DB 스냅샷) 로 대체한다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | SHALL | 04 (외부 FCM), 05 (인앱 UI) | 동일한 `notifications` 행이 외부 푸시와 인앱 표시 양쪽으로 전달됨을 검증 |
| `completion_notification-push-delivery` | 온디맨드 알림 전송 | SHALL | 03 | 응답 스키마 및 FCM 페이로드 |
| `completion_notification-push-delivery` | 기기 토큰 조회 | SHALL | 02 | 등록/미등록 두 분기 |
| `completion_notification-push-delivery` | 서비스 상태 점검 | SHALL | 01 | health 응답 스키마 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | 미처리 알림 전달 | 04, 05 | (04) `notifications.consumer` 가 워커 pod 으로 클레임됨 + 캡처된 FCM 메시지 존재. (05) 동일 알림 행이 SPA realtime 채널을 통해 벨 배지/드롭다운에 표시됨 + 클릭 시 `is_checked=true` |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | 알림 메시지 구성 | 04, 05 | (04) 캡처된 FCM 메시지의 `notification.title == from_user_id`, `body` 결합, `data.type/url/notification_id` 포함. (05) 드롭다운 항목의 표시 제목·본문·라우팅 URL 이 `notifications.title/description/url` 와 일치 |
| `completion_notification-push-delivery` | 온디맨드 알림 전송 | 알림 전송 성공 | 03 | REST 응답 `{success, message}` + 캡처된 FCM 메시지 페이로드 (외부 FCM 면제) |
| `completion_notification-push-delivery` | 기기 토큰 조회 | 기기 토큰 조회 | 02 | REST 응답 `{user_id, device_token}` + 미등록 시 빈 토큰 |
| `completion_notification-push-delivery` | 서비스 상태 점검 | 상태 점검 응답 | 01 | REST 응답 `{status:"healthy", service:"fcm-service"}` |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/fcm_service/fcm_service.py` | `send_notification`, `get_device_token`, `health_check`, `notification_polling_task`, `run_fcm_service_async` | 4개 요구사항 전부 | line >= 70%, function >= 80% | FastAPI 라우트 진입점 + 폴링 진입점 |
| `services/completion/fcm_service/database.py` | `fetch_device_token`, `send_fcm_message`, `handle_new_notification`, `fetch_unprocessed_notifications`, `check_new_notifications` | 4개 요구사항 전부 | line >= 60% | 라우트/폴링이 실제로 호출하는 데이터 어댑터 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/layouts/full/vertical-header/NotificationDD.vue` | 벨 메뉴(`menuOpen`), 미확인 카운트 (`notiCount`), `mounted()` 의 `backend.fetchNotifications()` + `backend.watchNotifications()`, `checkNotification(value)` 의 라우팅 + `setNotifications` 읽음 처리 | 미처리 알림 자동 전달 | line >= 60% (소스맵 가능 시), 그렇지 않으면 번들 보조 증거 | 인앱 알림 표시 + 클릭 읽음 처리의 사용자 입구. 시나리오 05 가 실제로 마운트하고 클릭하는 컴포넌트 |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` (`fetchNotifications`, `watchNotifications`, `setNotifications` 영역) | 알림 목록 조회, Supabase realtime 채널 구독, `is_checked=true` 업데이트 | 미처리 알림 자동 전달 | line >= 40% (소스맵 가능 시) | NotificationDD.vue 가 호출하는 백엔드 API 어댑터. 사용자 UI 흐름의 데이터 경로 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| Firebase 자격 증명 로딩 실패 분기 (`firebase_app` 초기화 실패) | E2E 에서는 `firebase_admin.messaging.send` 를 결정적으로 패치하므로 자격 증명 로딩 경로가 우회됨 | 단위 테스트로 보강 권장 |
| 다중 pod 동시 클레임 경합 | `fetch_unprocessed_notifications` 의 폴백 개별 업데이트 분기는 멀티 pod 시나리오가 필요 | 별도 부하/경합 테스트로 분리 |
| 푸시 알림 모바일 단말 수신 | 단말 도달은 FCM 외부 책임 영역 | 본 스위트 범위 외 — Real-Frontend Rule 면제 (사용자 검증 표면 항목 참조) |
| 워크아이템/채팅 트리거 사용자 액션을 통한 `notifications` 행 생성 | `handle_chat_insert` / `handle_todolist_change` DB 트리거의 동작은 `completion_process-workitem-submission` 등 다른 스위트와 채팅 스위트의 책임 범위 | 본 스위트는 알림 행이 도착한 이후 단계만 검증한다. 시나리오 05 는 행 도착을 PostgREST 시드로 모사한다 (테스트 대상은 행 생성 트리거가 아니라 알림 전달·표시 단계). |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐(알림 푸시 전달) 범위입니다.
- [x] 원본 명세의 서비스 접두어(`completion`)는 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다 (fcm_service + user_devices/notifications).
- [x] 스위트 슬러그가 원본 명세 ID 와 동일합니다.
- [x] E2E 시나리오/테스트/seed/결과는 `openspec/specs/completion_notification-push-delivery/e2e/` 아래에 응집되어 있습니다.
- [x] Real-Frontend Rule 재평가: (1) 인앱 알림 표시 UI 가 `NotificationDD.vue` 에 존재하므로 사용자-facing 시나리오 05 를 신규 추가했고, (2) 외부 FCM 도달(시나리오 03/04) 은 리포지토리 경계 밖이므로 사용자-facing UI 의무를 명시적으로 면제했습니다.
- [x] 스펙 관련 백엔드 파일/함수가 코드 표면 표에 기록되어 있습니다. 프론트엔드 표면(NotificationDD.vue + ProcessGPTBackend.ts) 이 기록되어 있습니다.
- [x] 커버리지 기준이 스펙 관련 fcm_service 파일에 한정되어 있고, 프론트엔드 표면은 인앱 알림 표시 경로에 한정되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
