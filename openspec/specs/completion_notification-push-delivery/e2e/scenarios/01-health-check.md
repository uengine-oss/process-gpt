# E2E 시나리오 01: FCM 서비스 상태 점검 응답

## 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `FCM 서비스 헬스 엔드포인트는 정상 상태와 서비스 이름을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`

## 목적
배포된 FCM 서비스 컨테이너가 기동 후 헬스 엔드포인트(`GET /health`)에 정상 응답하는지 확인한다. 운영자가 컨테이너 헬스 체크와 K8s liveness/readiness 신호로 사용하는 계약이다.

## 사전 조건
- `db`, `kong`, `auth`, `rest`, `fcm-service` 컨테이너가 모두 정상 (fcm-service 헬스체크 통과).
- Firebase 호출은 본 시나리오에서 발생하지 않음.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| (없음) | - | `GET http://localhost:8666/health` | 헬스 응답 스키마 검증 |

## 절차
1. Playwright `request` 픽스처로 FCM 서비스의 `GET /health` 를 호출한다.
2. 응답 본문을 파싱해 `status`, `service` 필드를 확인한다.

## 기대 결과
- HTTP 200 응답.
- 응답 JSON 이 `{ "status": "healthy", "service": "fcm-service" }` 와 정확히 일치.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_notification-push-delivery` | 서비스 상태 점검 | 상태 점검 응답 |

## 산출물
- 본 시나리오는 비-사용자-facing 프로토콜 테스트이므로 UI 스크린샷이 없습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- 보조 증거: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/01-health.json` (응답 본문 캡처)
