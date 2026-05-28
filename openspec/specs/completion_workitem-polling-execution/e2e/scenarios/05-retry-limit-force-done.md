# E2E 시나리오 05: 처리 실패 재시도 제한

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `재시도 횟수가 3회를 초과한 워크아이템은 DONE 으로 강제 종료되고 오류 로그가 기록된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (결정적 3회 실패 주입 또는 `retry=3` 직접 시드 필요)

## 목적
워크아이템 처리가 실패하면 폴링 워커는 `safe_handle_workitem` 의 except 분기(polling_service.py:79–96)에서 `retry` 카운터를 1 증가시키고 `consumer` 를 NULL 로 해제해 재처리 대상으로 되돌린다. `retry >= 3` 이면 `status='DONE'` + `[Error] ...` 로그로 강제 종료한다. 또한 `handle_service_workitem` 의 line 4022 `if workitem['retry'] >= 3: update_instance_status_on_error(...)` 분기로 인스턴스 상태가 영향을 받는다.

## 사전 조건
- 본 스위트 고유 시드:
  - 시나리오 5a (실패 후 재시도): `retry=0` 으로 시드된 워크아이템 + mock 이 매 호출마다 예외를 던지도록 구성. 폴링 주기(5초) × 3회 = 약 15–20초 대기 후 retry=3 도달.
  - 시나리오 5b (재시도 한도 초과 단축 경로): `retry=3` 으로 직접 시드된 워크아이템 + mock 실패 → 첫 처리에서 force DONE 분기 트리거.
- mock-llm-ate 또는 mock-mcp-server 가 결정적으로 예외를 던지도록 구성되어야 합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | retry=0 워크아이템 + retry=3 워크아이템 |
| `mock_mcp_server.py` (확장) | stub | `openspec/specs/completion_automated-task-execution/e2e/scripts/mock_mcp_server.py` | 특정 도구 이름 호출 시 예외 throw |

## 절차
1. 사용자가 로그인 후 `/todolist` 에 진입합니다.
2. 시나리오 5a: SUBMITTED 카드의 로그가 `다시 시도하겠습니다. (시도 1/3)` → `(시도 2/3)` → `(시도 3/3)` 로 갱신되는지 5초 간격으로 새로고침하며 확인합니다.
3. 시나리오 5b: SUBMITTED 카드(retry=3)가 한 번의 처리 후 DONE 컬럼으로 이동하며 로그에 `[Error]` 메시지가 표시되는지 확인합니다.

## 기대 결과
- 5a: 워크아이템의 `retry` 카운터가 1 → 2 → 3 으로 증가하며 매 시도마다 `consumer` 가 NULL 로 해제되어 다음 폴링 사이클에서 재픽업됩니다.
- 5b: 워크아이템 카드가 DONE 컬럼으로 이동하고 로그에 `[Error] Error in safe_handle_workitem for workitem ...` 메시지가 표시됩니다 (DB: `todolist.status = 'DONE'`, `log LIKE '[Error]%'`).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 처리 실패 재시도 제한 | 실패 후 재시도 / 재시도 한도 초과 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `05-retry-1-of-3` | 카드 로그에 `(시도 1/3)` 메시지 노출 | `process-gpt-completion_workitem-polling-execution-05-retry-1-of-3.png` | 첫 실패 후 재시도 안내 |
  | `05-retry-exceeded` | 카드 로그에 `[Error]` 메시지 + DONE 컬럼 이동 | `process-gpt-completion_workitem-polling-execution-05-retry-exceeded.png` | 재시도 한도 초과로 강제 종료된 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.

## 보류 사유
시나리오 5a 는 결정적 예외 주입을 위해 mock-mcp-server (또는 mock-llm-ate) 의 새로운 실패 모드 추가가 필요하며, 폴링 주기 3회를 기다리는 동안 다른 ATE 시나리오와 워크아이템 픽업 우선순위가 충돌하지 않도록 `consumer='hold-test-05'` 직렬화 패턴이 필요하다 ([[polling-mcp-processor-quirks]]). 시나리오 5b 는 비교적 짧은 구현이지만 단독 활성화 시 가치가 제한적이므로 5a 와 함께 활성화하는 것이 권장된다.
