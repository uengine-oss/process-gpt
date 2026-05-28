# E2E 시나리오 02: 사용자 할 일 목록 조회

## 메타데이터
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `사용자 할 일 목록 조회와 상태 필터/누락 처리`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`

## 목적
콜봇이 `GET /complete-callbot/user-todolist` 및 `GET /complete-callbot/tasks`로 사용자의 할 일 목록을 조회할 때 정상 목록·필드 시리얼라이즈가 동작하는지, `status_filter`가 TODO/IN_PROGRESS 등을 정확히 필터링하는지, 그리고 `user_id` 누락 시 FastAPI가 422 응답을 반환하는지 확인한다.

## 사전 조건
- 시나리오 01의 사용자가 `public.users`에 존재한다.
- `public.todolist`에 다음 row가 존재한다:
  - `cbe20001-...` status=`TODO`, activity_name=`첫 번째 할 일`, due_date=NULL.
  - `cbe20002-...` status=`IN_PROGRESS`, activity_name=`진행 중 할 일`, due_date=NULL.
  - `cbe20003-...` status=`DONE`, activity_name=`완료된 할 일` (active 필터에서 제외 확인용).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 콜봇 사용자 할 일 시드 | seed | `public.todolist` 3 row | 상태 필터 및 시리얼라이저 검증 |

## 절차
1. `GET /complete-callbot/user-todolist?user_id=c5c11111-1111-1111-1111-111111111111`을 호출한다.
2. `GET /complete-callbot/tasks?user_id=c5c11111-1111-1111-1111-111111111111&status_filter=active`을 호출한다 (기본 동작).
3. `GET /complete-callbot/tasks?user_id=c5c11111-1111-1111-1111-111111111111&status_filter=in_progress`을 호출한다.
4. `GET /complete-callbot/tasks`을 `user_id` 없이 호출한다.

## 기대 결과
- 1번: HTTP 200, `success=true`, `count >= 2` (DONE 포함 가능), `items` 배열의 각 원소가 `id`, `activity_name`, `status`, `due_date`(null 허용) 필드를 가진다.
- 2번: HTTP 200, `success=true`, `tasks`는 TODO + IN_PROGRESS만 포함하고 DONE은 포함하지 않는다. `overdue_count`는 정수다.
- 3번: HTTP 200, `success=true`, `tasks`는 IN_PROGRESS 상태인 row만 포함한다 (`첫 번째 할 일` 미포함).
- 4번: HTTP 422 (FastAPI Query 필수 파라미터 누락).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 할 일 목록 조회 성공 |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 상태 필터 적용 |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 사용자 식별자 누락 |

## 산출물
- 스크린샷 체크포인트: 비-사용자-facing protocol API이므로 적용하지 않음.
- Trace/video: 실패 시 보존.
- 결과 JSON: `openspec/specs/completion_callbot-task-management/e2e/results/results.json`
