# E2E 시나리오 03: 담당 사용자 이메일 해소 실패 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `03 [backend-contract] 담당 사용자 이메일을 해소할 수 없으면 400 메시지를 반환한다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
role default 가 없고 요청에 `email` 이 없는 결함 정의(`wis_no_user_process`) 로 `/initiate` 를 호출했을 때 `No default user email found` 메시지가 보존되는지 검증한다. `/initiate` 는 사용자 UI 에서 발화되지 않으므로 백엔드 계약 전용이다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- `wis_no_user_process` 정의(role default/endpoint 모두 없음) 가 존재한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `wis_no_user_process` proc_def | seed | `openspec/specs/completion_process-workitem-submission/e2e/seed_files/e2e_seed.sql` | 사용자 해소 실패 정의 |

## 절차
1. Playwright `request` 가 `POST /completion/initiate` 에 `{ input: { process_definition_id: 'wis_no_user_process' } }` 를 전송한다.
2. 응답 텍스트가 `No default user email found` 를 포함하는지 검증한다.

## 기대 결과
- 응답 상태 코드는 `200` 이 아니며, 본문에 `No default user email found` 메시지가 포함된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 담당 사용자 이메일을 해소할 수 없음 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
