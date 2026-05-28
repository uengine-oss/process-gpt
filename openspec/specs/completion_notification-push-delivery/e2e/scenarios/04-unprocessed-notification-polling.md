# E2E 시나리오 04: 미처리 알림 폴링 및 자동 전달

## 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `consumer 가 비어 있는 알림 행은 폴링 워커가 클레임하고 FCM 으로 전달한다`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`

## 목적
폴링 워커(15초 주기)가 `notifications` 테이블에서 `consumer IS NULL` 인 행을 발견하면 자신의 pod 식별자로 클레임하고, 대상 사용자 기기로 FCM 푸시를 전달한다. 또한 메시지 구성 시 `from_user_id` 를 제목으로, `description + title` 을 본문으로 사용하고 `data` 에 `type`, `url`, `notification_id` 를 포함한다.

## 사전 조건
- `db-seed-notification-push-delivery` 가 다음 시드를 적용한다:
  - 테넌트 `e2e-fcm-tenant` (운영 분기 조건 `tenant_id != 'uengine'` 충족).
  - `user_devices` 행: `user_email='e2e-fcm-user@uengine.org'`, `device_token='fake-device-token-e2e-001'`.
  - `notifications` 행: `id` UUID 고정, `user_id='e2e-fcm-user@uengine.org'`, `title='새 워크아이템'`, `description='담당 업무를 확인하세요'`, `type='workitem_bmp'`, `url='/todolist/abc'`, `from_user_id='프로세스봇'`, `consumer=NULL`, `tenant_id='e2e-fcm-tenant'`.
- FCM 서비스 환경 변수에 `ENV=production` 이 설정되어 `tenant_id != 'uengine'` 분기로 미처리 알림을 조회한다.
- `firebase_admin.messaging.send` 는 캡처 함수로 패치되어 있다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_notification-push-delivery/e2e/seed_files/e2e_seed.sql` | 테넌트/유저디바이스/알림 시드 |
| `firebase_patch.py` | stub | `openspec/specs/completion_notification-push-delivery/e2e/scripts/firebase_patch.py` | `messaging.send` 가로채기 |

## 절차
1. Playwright 가 캡처 파일 초기 크기와 `notifications.consumer` 값을 기록한다 (PostgREST 경유 조회).
2. 폴링 주기(최대 약 25초) 동안 다음 조건이 만족될 때까지 폴링 대기:
   - `notifications.consumer` 가 NULL 이 아닌 값(워커 pod 호스트명) 으로 갱신됨.
   - 캡처 파일에 새 FCM 메시지 라인이 추가됨.
3. 캡처된 마지막 FCM 메시지의 페이로드를 검증한다.

## 기대 결과
- `notifications.consumer` 가 `fcm-service` 워커의 hostname 으로 갱신됨 (NULL 이 아님).
- 캡처된 FCM 메시지가 다음 조건을 모두 만족:
  - `token == "fake-device-token-e2e-001"`
  - `notification.title == "프로세스봇"`
  - `notification.body == "담당 업무를 확인하세요\n새 워크아이템"`
  - `data.type == "workitem_bmp"`
  - `data.url == "https://e2e-fcm-tenant.process-gpt.io/todolist/abc"` — `handle_new_notification` 이 `tenant_id` 가 있는 경우 `https://{tenant_id}.process-gpt.io{url}` 형식으로 재작성한 뒤 `send_fcm_message` 에서 `data['url']` 를 덮어쓴다
  - `data.notification_id` 가 시드된 UUID 와 일치

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | 미처리 알림 전달 |
| `completion_notification-push-delivery` | 미처리 알림 자동 전달 | 알림 메시지 구성 |

## 산출물
- 본 시나리오는 비-사용자-facing 프로토콜 테스트이므로 UI 스크린샷이 없습니다.
- 결과 JSON: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- FCM 캡처: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/fcm-captures/fcm-messages.jsonl`
- DB 스냅샷: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/04-consumer-claim.json`
