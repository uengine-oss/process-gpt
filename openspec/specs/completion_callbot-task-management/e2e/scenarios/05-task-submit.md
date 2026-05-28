# E2E 시나리오 05: 작업 제출

## 메타데이터
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `작업 제출: 상태 SUBMITTED 전이로 폴링 대상 진입`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`

## 목적
`POST /complete-callbot/task/{task_id}/submit`이 todolist row의 `status`를 `SUBMITTED`로 전이시키고 `end_date`를 기록하며 `consumer`/`retry`를 초기화하는지, 그리고 미존재 task에 대해서는 404를 반환하는지 확인한다. 이 상태 전이가 곧 `services/completion/polling_service`가 다음 activity를 생성할 수 있는 조건이므로, 본 시나리오에서는 상태 전이까지 단언한다.

## 사전 조건
- 시나리오 04의 시드 및 PATCH로 채워진 `cbe30002-...` (status=TODO) row가 존재한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 제출 대상 task | seed (재사용) | `public.todolist` `cbe30002-...` | SUBMITTED 전이 검증 |

## 절차
1. `POST /complete-callbot/task/cbe30002-.../submit`을 호출한다.
2. PostgREST/Kong을 통해 동일 row를 다시 조회하거나 `GET /complete-callbot/task/{task_id}`로 `status`를 확인한다.
3. `POST /complete-callbot/task/00000000-0000-0000-0000-000000000000/submit`을 호출한다 (미존재).

## 기대 결과
- 1번 응답: HTTP 200, `success=true`, `task_id=cbe30002-...`, `status=SUBMITTED`, `message`에 `Polling service` 문구가 포함된다.
- 2번 확인: 동일 row의 `status=SUBMITTED`, `end_date`가 설정되어 있다. `GET /complete-callbot/task/{task_id}` 응답의 `task.status=SUBMITTED`.
- 3번 응답: HTTP 404, `detail`이 `Task not found`를 포함한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_callbot-task-management` | 작업 제출 | 작업 제출 성공 |

## 산출물
- 스크린샷 체크포인트: 비-사용자-facing protocol API이므로 적용하지 않음.
- Trace/video: 실패 시 보존.
- 결과 JSON: `openspec/specs/completion_callbot-task-management/e2e/results/results.json`
