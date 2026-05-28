# E2E 시나리오 04: 작업 필드 수정

## 메타데이터
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `작업 필드 수정: PATCH로 폼 데이터 병합`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`

## 목적
`PATCH /complete-callbot/task/{task_id}`가 클라이언트가 보낸 필드 값을 기존 `output`에 병합하고, `tool=formHandler:<form_id>`가 있는 작업의 경우 폼 id 키로 자동 wrap 및 merge되는지를 검증한다.

## 사전 조건
- 시나리오 03의 시드가 적용되어 `cbe30002-...` (status=TODO, tool=`formHandler:target_form`, output=`{}`)이 존재한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| PATCH body | inline | `{"customer_name": "홍길동", "phone": "010-0000-0000"}` | 자동 wrap+merge 경로 |
| 후속 PATCH body | inline | `{"phone": "010-1111-2222"}` | 동일 폼에 대한 추가 merge 검증 |

## 절차
1. `PATCH /complete-callbot/task/cbe30002-...` body=`{"customer_name": "홍길동", "phone": "010-0000-0000"}`을 호출한다.
2. 동일 task에 `PATCH ...` body=`{"phone": "010-1111-2222"}`을 다시 호출한다 (merge 동작 검증).
3. `GET /complete-callbot/task/cbe30002-...`로 최종 `current_data`를 다시 읽는다.

## 기대 결과
- 1번 응답: HTTP 200, `success=true`, `updated_fields`가 입력 필드명 (`customer_name`/`phone`) 또는 wrap 후 폼 키 (`target_form`)를 포함한다. 응답 `output`이 `{"target_form": {"customer_name": "홍길동", "phone": "010-0000-0000"}}` 구조를 만족한다.
- 2번 응답: HTTP 200, `success=true`. 응답 `output.target_form.customer_name`가 `홍길동` (보존)이고 `phone`은 `010-1111-2222`로 갱신되었다.
- 3번 응답: `current_data.target_form.customer_name=홍길동`, `current_data.target_form.phone=010-1111-2222`.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_callbot-task-management` | 작업 필드 수정 | 작업 필드 수정 성공 |

## 산출물
- 스크린샷 체크포인트: 비-사용자-facing protocol API이므로 적용하지 않음.
- Trace/video: 실패 시 보존.
- 결과 JSON: `openspec/specs/completion_callbot-task-management/e2e/results/results.json`
