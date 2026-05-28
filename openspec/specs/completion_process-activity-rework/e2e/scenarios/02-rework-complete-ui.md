# E2E 시나리오 02: 재작업 다이얼로그에서 전체 활동 재작업을 시작한다

## 메타데이터
- 스위트 슬러그: `completion_process-activity-rework`
- 원본 명세 ID: `completion_process-activity-rework`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `재작업 다이얼로그에서 전체 활동 재작업을 시작한다`
- 원본 명세:
  - `openspec/specs/completion_process-activity-rework/spec.md`

## 목적
사용자가 다이얼로그에서 "이후 모든 활동 포함" 옵션을 선택하고 제출하면 completion 백엔드가 `POST /rework-complete`로 새 워크아이템을 생성해 시작 활동을 `IN_PROGRESS`, 나머지를 `TODO`로 전이하는지 검증한다. UI는 인스턴스 목록 화면으로 이동해야 한다.

## 사전 조건
- 시나리오 01의 사전 조건이 모두 충족된 상태(시드 + 로그인)
- 시나리오 01과 동일한 인스턴스 `rework_demo_proc.e2e-instance-0001` 사용 가능

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-activity-rework/e2e/seed_files/e2e_seed.sql` | DONE 워크아이템 시드 |
| Supabase REST | api | `GET /rest/v1/todolist?proc_inst_id=eq.rework_demo_proc.e2e-instance-0001` | DB 전이 검증 (보조 assertion, UI 흐름 이후) |

## 절차
1. 시나리오 01의 절차 1~3을 수행해 다이얼로그를 연다.
2. "이후 모든 활동 포함" 라디오 버튼을 클릭한다.
3. 다이얼로그 하단의 "재작업 시작" 제출 버튼을 클릭한다.
4. URL이 `/instancelist/...`로 이동하고 인스턴스 상세 화면이 표시되는 것을 확인한다.

## 기대 결과
- `POST /completion/rework-complete`가 200으로 응답해야 한다.
- 응답 본문은 새 워크아이템 id를 키로 한 객체이며, 두 개의 새 워크아이템이 존재해야 한다 (`act_b`, `act_c`).
- 새 워크아이템의 `rework_count`는 기존 워크아이템의 `rework_count + 1`이다.
- 시작 활동(`act_b`)의 새 워크아이템 `status`는 `IN_PROGRESS`이고 나머지(`act_c`)는 `TODO`다.
- 라우터가 `/instancelist/<dot-replaced-instance-id>`로 이동해 인스턴스 화면이 로드된다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-activity-rework` | 활동 재작업 시작 | 재작업 시작 성공 |
| `completion_process-activity-rework` | 보상 코드 생성 | 되돌릴 작업이 없을 때 생략 (간접 검증: 본 시드는 events가 비어 있어 보상 코드 생성이 호출되지 않음) |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `rework-dialog-submit-ready` | 라디오 선택 + 제출 버튼이 활성화된 상태 | `process-gpt-completion_process-activity-rework-02-rework-dialog-submit-ready.png` | 재작업 범위를 선택하고 시작 버튼이 활성화된 다이얼로그입니다 |
  | `instance-after-rework` | 제출 후 인스턴스 상세 화면으로 이동한 상태 | `process-gpt-completion_process-activity-rework-02-instance-after-rework.png` | 재작업이 시작되어 인스턴스 화면으로 이동했습니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-activity-rework/e2e/results/results.json`
