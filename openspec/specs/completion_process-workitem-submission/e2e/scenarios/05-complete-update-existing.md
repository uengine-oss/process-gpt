# E2E 시나리오 05: task_id 단독 lookup 으로 기존 워크아이템 갱신 (백엔드 계약)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `05 [backend-contract] task_id 만 주어져도 기존 워크아이템이 SUBMITTED 로 갱신된다`
- 분류: 백엔드 계약 전용 (스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
`task_id` 만으로 기존 워크아이템을 lookup 하고 `SUBMITTED` 로 전이시키는 백엔드 계약 분기를 검증한다. `ProcessGPTBackend.putWorkItemComplete()` 는 항상 `process_instance_id` 와 `task_id` 를 함께 전송하므로 `task_id` 단독 분기는 사용자 UI 에서 발화되지 않는다. 따라서 본 시나리오는 백엔드 계약 전용으로 분류한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- 시드로 생성된 TODO 워크아이템(`task_id = 11111111-1111-1111-1111-111111111111`, `proc_inst_id = wis-existing-inst`) 이 존재한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 기존 TODO 워크아이템 | seed | `e2e_seed.sql` (todolist row `11111111-...`) | `task_id` 단독 lookup 대상 |

## 절차
1. Playwright `request` 가 `POST /completion/complete` 에 `{ input: { task_id, email, tenant_id, form_values: { leave_days: 7 } } }` 를 전송한다 (`process_instance_id` 누락).
2. 응답 본문 JSON 을 검증한다.

## 기대 결과
- 응답 상태 코드는 `200`.
- 응답 본문의 `id` 는 기존 `task_id` 와 동일하며, `status=SUBMITTED` 로 전이된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 워크아이템 제출 | 기존 워크아이템 갱신 제출 |

## 산출물
- 스크린샷 체크포인트: 없음 (백엔드 계약 전용).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
