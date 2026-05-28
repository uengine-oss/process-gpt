# E2E 시나리오 06: process_instance_id 누락 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `06`
- Playwright 테스트 제목: `06 [backend-contract] process_instance_id 가 누락되면 400 을 반환한다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
필수 식별자(`process_instance_id` 와 `task_id`) 가 모두 누락된 malformed 요청에 대해 `400`/`Process instance id is required` 가 반환되는지 검증한다. SPA 는 항상 두 식별자를 함께 전송하므로 본 분기는 사용자 UI 에서 발화되지 않는다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| malformed body | runtime | `POST /completion/complete` | 필수 식별자 누락 검증 |

## 절차
1. Playwright `request` 가 `POST /completion/complete` 에 `process_instance_id` 와 `task_id` 가 모두 없는 body 를 전송한다.
2. 응답 상태 코드와 본문 메시지를 검증한다.

## 기대 결과
- 응답 상태 코드는 `400`.
- 응답 본문에 `Process instance id is required` 메시지가 포함된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 워크아이템 제출 | 프로세스 인스턴스 식별자 누락 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
