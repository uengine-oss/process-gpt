# E2E 시나리오 09: 테넌트 격리 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `09`
- Playwright 테스트 제목: `09 [backend-contract] 요청 subdomain 에 속하지 않은 프로세스 정의는 사용할 수 없다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
`X-Forwarded-Host=localhost` 요청이 `altten` 테넌트의 비공개 정의(`wis_altten_only_process`) 에 접근할 수 없고, 응답 본문이 비공개 활동 식별자(`secret_activity`) 를 노출하지 않는지 검증한다. `/initiate` 는 사용자 UI 에서 발화되지 않으므로 백엔드 계약 전용으로 분류한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- `altten` 테넌트에만 존재하는 `wis_altten_only_process` 정의가 존재한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `wis_altten_only_process` proc_def | seed | `e2e_seed.sql` | 타 테넌트 비공개 정의 |

## 절차
1. Playwright `request` 가 `POST /completion/initiate` 에 `{ input: { process_definition_id: 'wis_altten_only_process' } }` 를 `X-Forwarded-Host: localhost` 헤더로 전송한다.
2. 응답 상태 코드가 `200` 이 아니며 본문에 `secret_activity` 가 노출되지 않는지 검증한다.

## 기대 결과
- 응답 상태 코드는 `200` 이 아니다.
- 응답 본문에 `secret_activity` 문자열이 포함되지 않는다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 테넌트 격리 | 테넌트별 데이터 분리 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
