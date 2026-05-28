# E2E 시나리오 03: 작업 상세 조회

## 메타데이터
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `작업 상세 조회: 폼 스키마와 참조 폼 / 미존재 시 404`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`

## 목적
`GET /complete-callbot/task/{task_id}`가 작업 본문, 활동 instruction/checkpoint, `form_schema`, 현재 입력 `current_data`, `inputData`에 명시된 참조 폼만 정확히 반환하는지를 확인하고, 미존재 task_id에 대해서는 404 `Task not found`를 반환하는지를 검증한다.

## 사전 조건
- `public.proc_def` row가 존재하고 `definition.activities`에 두 개 activity가 정의된다:
  - `act_prev` (DONE된 선행 단계, 출력 폼 id `prev_form`).
  - `act_target` (콜봇이 처리할 단계, `inputData=["prev_form.field_a"]`, `instruction`, `checkpoints` 포함).
- `public.form_def` row가 `act_target` activity의 `fields_json`을 제공한다.
- `public.todolist`:
  - `cbe30001-...` status=`DONE`, activity_id=`act_prev`, output=`{"prev_form": {"field_a": "이전값", "field_b": "필터링대상"}}`, proc_inst_id 공유.
  - `cbe30002-...` status=`TODO`, activity_id=`act_target`, proc_inst_id 공유, output=`{}`, tool=`formHandler:target_form`.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 참조 폼/대상 폼 시드 | seed | `proc_def`, `form_def`, `todolist` (2 row) | `form_schema`/`reference_forms` 분기 검증 |

## 절차
1. `GET /complete-callbot/task/cbe30002-...`을 호출한다 (성공 케이스).
2. `GET /complete-callbot/task/00000000-0000-0000-0000-000000000000`을 호출한다 (미존재).

## 기대 결과
- 1번: HTTP 200, `success=true`. `task.id=cbe30002-...`, `task.activity_name`, `task.instruction`/`task.checkpoints`가 시드 값과 일치한다. `form_schema`가 시드한 `fields_json`과 동일하다. `current_data`가 `{}`이거나 시드한 값과 일치한다. `reference_forms` 배열이 1개를 포함하며 `activity_id=act_prev`, `data`에 `prev_form` 키가 있고 `field_a` 값이 유지되며 `inputData`에 없는 다른 폼은 포함되지 않는다.
- 2번: HTTP 404, body의 `detail`이 `Task not found`를 포함한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_callbot-task-management` | 작업 상세 조회 | 작업 상세 조회 성공 |
| `completion_callbot-task-management` | 작업 상세 조회 | 작업을 찾을 수 없음 |

## 산출물
- 스크린샷 체크포인트: 비-사용자-facing protocol API이므로 적용하지 않음.
- Trace/video: 실패 시 보존.
- 결과 JSON: `openspec/specs/completion_callbot-task-management/e2e/results/results.json`
