# E2E 시나리오 04: 되돌릴 작업 이력이 없으면 보상 코드 준비를 생략한다

## 메타데이터
- 스위트 슬러그: `completion_process-activity-rework`
- 원본 명세 ID: `completion_process-activity-rework`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `되돌릴 작업 이력이 없으면 보상 코드 준비를 생략한다`
- 원본 명세:
  - `openspec/specs/completion_process-activity-rework/spec.md`

## 목적
재작업 시 `compensation_handler.generate_compensation`이 호출되더라도, 대상 활동 이전에 되돌릴 수 있는 도구 사용 이력(`events.event_type='tool_usage_finished'` AND `crew_type='action'`)이 없으면 보상 코드 생성을 생략해야 한다는 계약을 검증한다. 본 시드는 events 행을 만들지 않으므로 재작업 후 `mcp_python_code.compensation`이 비어 있어야 한다.

## 사전 조건
- 시나리오 02가 정상 동작하는 환경 (즉 재작업 다이얼로그 제출이 성공)
- `mcp_python_code` 테이블에 해당 `(proc_def_id, activity_id, tenant_id)` 조합의 compensation row가 사전에 존재하지 않음 (시드 단계에서 제거)
- `events` 테이블에 본 인스턴스의 `tool_usage_finished` 이벤트가 없음

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| Supabase REST | api | `GET /rest/v1/mcp_python_code?proc_def_id=eq.rework_demo_proc&activity_id=eq.act_b` | 보상 코드 생성 생략 검증 |

## 절차
1. 시나리오 02 실행 후(또는 동일 시드를 재적용한 직후), `GET /rest/v1/mcp_python_code?proc_def_id=eq.rework_demo_proc&activity_id=eq.act_b&tenant_id=eq.localhost` 호출.
2. 응답 본문 배열에 행이 없거나, 있다면 `compensation` 필드가 `null`임을 확인.

## 기대 결과
- 재작업이 성공했음에도 불구하고 `mcp_python_code.compensation`은 `null` 또는 행 자체가 존재하지 않는다.
- 동시에 시나리오 02의 재작업 응답이 정상이므로, 보상 코드 생략이 재작업 흐름을 막지 않았음을 입증한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-activity-rework` | 보상 코드 생성 | 되돌릴 작업이 없거나 보상 코드가 이미 있을 때 생략 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 백엔드 상태 검증이라 UI 스크린샷은 생성하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-activity-rework/e2e/results/results.json`
