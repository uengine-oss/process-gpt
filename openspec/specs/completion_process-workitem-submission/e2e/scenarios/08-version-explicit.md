# E2E 시나리오 08: 명시 버전 처리 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `08`
- Playwright 테스트 제목: `08 [backend-contract] version_tag/version 이 주어지면 해당 버전 정의가 적용된다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
`/completion/initiate` 가 요청의 `version_tag='major'`, `version='1.0'` 를 우선 적용해 `proc_def_version` 의 버전 정의(`submit_request_v1`) 로 워크아이템을 생성하는지 검증한다. `/initiate` 는 사용자 UI 에서 발화되지 않으므로 백엔드 계약 전용으로 분류한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- `wis_versioned_process` 의 `proc_def.definition` 활동은 `submit_request_current`, `proc_def_version(major,1.0)` 활동은 `submit_request_v1` 이다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `wis_versioned_process` proc_def + proc_def_version | seed | `e2e_seed.sql` | 버전 분기 검증 |

## 절차
1. Playwright `request` 가 `POST /completion/initiate` 에 `{ input: { process_definition_id: 'wis_versioned_process', version_tag: 'major', version: '1.0' } }` 를 전송한다.
2. 응답 본문의 `activity_id`, `proc_def_id` 를 검증한다.

## 기대 결과
- 응답 상태 코드는 `200`.
- 응답 본문의 `activity_id` 는 `submit_request_v1`, `proc_def_id` 는 `wis_versioned_process`.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 명시한 버전으로 처리 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
