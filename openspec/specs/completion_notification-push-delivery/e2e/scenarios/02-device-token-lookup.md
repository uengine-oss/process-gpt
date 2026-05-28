# E2E 시나리오 02: 사용자 기기 토큰 조회

## 메타데이터
- 스위트 슬러그: `completion_notification-push-delivery`
- 원본 명세 ID: `completion_notification-push-delivery`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `등록된 사용자는 device_token 을 반환하고 미등록 사용자는 빈 토큰을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_notification-push-delivery/spec.md`

## 목적
`GET /device-token/{user_id}` 가 `user_devices` 테이블의 `device_token` 을 정확히 반환하고, 등록 정보가 없는 사용자는 토큰 값이 비어 있는 응답을 반환하는지 검증한다.

## 사전 조건
- `db-seed-notification-push-delivery` 가 완료되어 `user_devices` 테이블에 다음 행이 적재됨:
  - `user_email='e2e-fcm-user@uengine.org'`, `device_token='fake-device-token-e2e-001'`
- 미등록 사용자: `user_email='unknown-fcm-user@uengine.org'` (행이 존재하지 않음)
- `fcm-service` 컨테이너가 supabase 클라이언트로 Kong 을 통해 `user_devices` 를 조회한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_notification-push-delivery/e2e/seed_files/e2e_seed.sql` | `tenants`, `user_devices` 시드 |

## 절차
1. Playwright `request` 로 `GET /device-token/e2e-fcm-user@uengine.org` 호출.
2. Playwright `request` 로 `GET /device-token/unknown-fcm-user@uengine.org` 호출.

## 기대 결과
- 등록 사용자: HTTP 200, `{ "user_id": "e2e-fcm-user@uengine.org", "device_token": "fake-device-token-e2e-001" }`.
- 미등록 사용자: HTTP 200, `user_id` 는 요청 값과 동일, `device_token` 은 `null` 또는 빈 문자열.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_notification-push-delivery` | 기기 토큰 조회 | 기기 토큰 조회 |

## 산출물
- 본 시나리오는 비-사용자-facing 프로토콜 테스트이므로 UI 스크린샷이 없습니다.
- 결과 JSON: `openspec/specs/completion_notification-push-delivery/e2e/results/results.json`
- 보조 증거: `openspec/specs/completion_notification-push-delivery/e2e/results/artifacts/02-device-token.json`
