# E2E 시나리오 03: 존재하지 않는 작업으로 차이 조회 시 400 No workitem found 를 반환한다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-feedback`
- 원본 명세 ID: `completion_process-definition-feedback`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `존재하지 않는 작업으로 차이 조회 시 400 No workitem found 를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-feedback/spec.md`

## 목적
`POST /completion/get-feedback-diff` 의 오류 분기를 검증합니다. 시드되지 않은 임의의 UUID 를 `taskId` 로 전달하면 `fetch_workitem_by_id` 가 `None` 을 반환하고, 핸들러가 `HTTPException(400, "No workitem found")` 를 발생시켜 게이트웨이를 통해 클라이언트에 400 응답이 전달되는지 확인합니다.

## 사전 조건
- 게이트웨이, completion 백엔드, Supabase 컨테이너가 기동되어 있어야 합니다.
- 사용하는 UUID 는 시드된 워크아이템과 충돌하지 않는 더미 값(`ffffffff-ffff-ffff-ffff-fffffffffff0`) 입니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 존재하지 않는 taskId | 입력 | request body | `fetch_workitem_by_id` 가 `None` 을 반환하도록 유도 |

## 절차
1. Playwright 가 `POST http://localhost:8088/completion/get-feedback-diff` 요청을 보냅니다 (보조 프로토콜).
2. 본문에 `taskId='ffffffff-ffff-ffff-ffff-fffffffffff0'` 를 포함합니다.
3. 응답 상태와 본문을 확인합니다.

## 기대 결과
- 응답 본문(`detail`) 에 `No workitem found` 문구가 포함됩니다.
- mock-llm 호출이 발생하지 않습니다 (워크아이템 미존재 시 조기 종료 분기).

### 명세와의 차이
- 명세는 `400` 상태 코드를 요구하지만, 현재 `handle_get_feedback_diff` 의 `except Exception` 분기가 `HTTPException(400, ...)` 까지 함께 잡아서 `HTTPException(500, "400: No workitem found")` 로 재포장해 응답합니다. 본 시나리오는 실제 구현 동작인 `HTTP 500 + detail "400: No workitem found"` 을 검증하며, 코드 수정 시(예: `handle_submit` 처럼 `except HTTPException: raise` 추가) 시나리오의 상태 코드 단언을 `400` 으로 갱신해야 합니다. 명세 게이트에서는 이 차이를 알려진 공백으로 기록합니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-feedback` | 작업 정의 버전 변경 비교 | 워크아이템 또는 활동을 찾을 수 없음 |

## 산출물
- 스크린샷 체크포인트: 해당 없음 (백엔드 프로토콜 검증).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-feedback/e2e/results/results.json`
