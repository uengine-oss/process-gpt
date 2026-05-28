# E2E 시나리오 03: 온디맨드 알림 전송과 FCM 메시지 구성

## 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `POST /send-notification 은 발신자 제목·결합 본문·data 페이로드로 FCM 메시지를 구성한다`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`

## 목적
다른 백엔드 서비스가 `POST /send-notification` 으로 알림 정보를 보내면 FCM 서비스가 즉시 FCM 메시지를 구성해 전송한다는 계약을 검증한다. 발신자(`from_user_id`)가 포함되면 메시지 제목은 발신자, 본문은 `body\ntitle` 결합 형식이 되고, `data` 페이로드에는 `type`, `url`, 사용자 지정 필드가 포함된다.

## 사전 조건
- 시나리오 02 와 동일하게 `e2e-fcm-user@uengine.org` 의 `device_token` 이 시드되어 있다.
- `firebase_admin.messaging.send` 는 결정적 캡처 함수로 패치되어 있다 (`scripts/firebase_patch.py`).
- 캡처 파일 경로: `/captures/fcm-messages.jsonl` (호스트: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/fcm-captures/fcm-messages.jsonl`).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `firebase_patch.py` | stub | `openspec/specs/completion_notification-push-delivery/e2e/scripts/firebase_patch.py` | `messaging.send` 가로채 캡처 JSONL 작성 |
| `e2e_seed.sql` | seed | `openspec/specs/completion_notification-push-delivery/e2e/seed_files/e2e_seed.sql` | `user_devices` 토큰 확보 |

## 절차
1. Playwright 가 캡처 파일 초기 크기를 기록한다.
2. Playwright 가 `POST /send-notification` 을 호출하며 다음 JSON 을 본문으로 보낸다:
   ```json
   {
     "user_id": "e2e-fcm-user@uengine.org",
     "title": "워크아이템 검토 요청",
     "body": "오늘까지 회신해주세요",
     "type": "workitem_bmp",
     "url": "/todolist/123",
     "from_user_id": "프로세스봇",
     "data": { "extra": "ok" }
   }
   ```
3. 응답을 확인하고, 캡처 JSONL 마지막 줄을 읽어 FCM 메시지 페이로드를 검증한다.

## 기대 결과
- HTTP 200, 응답 본문 `{ "success": true, "message": "Message sent successfully" }`.
- 캡처된 FCM 메시지가 다음 조건을 모두 만족:
  - `token == "fake-device-token-e2e-001"`
  - `notification.title == "프로세스봇"` (발신자가 제목)
  - `notification.body == "오늘까지 회신해주세요\n워크아이템 검토 요청"` (body + title 결합)
  - `data.type == "workitem_bmp"`, `data.url == "/todolist/123"`, `data.title == "프로세스봇"`, `data.body == "오늘까지 회신해주세요\n워크아이템 검토 요청"`, `data.extra == "ok"`

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_notification-push-delivery` | 온디맨드 알림 전송 | 알림 전송 성공 |

## 산출물
- 본 시나리오는 비-사용자-facing 프로토콜 테스트이므로 UI 스크린샷이 없습니다.
- 결과 JSON: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- FCM 캡처: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/fcm-captures/fcm-messages.jsonl`
