# E2E 시나리오 02: 작업 피드백 차이 조회 시 modifications와 summary를 반환한다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-feedback`
- 원본 명세 ID: `completion_process-definition-feedback`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `작업 피드백 차이 조회 시 modifications와 summary를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-feedback/spec.md`

## 목적
시드된 작업과 활동을 기반으로 `POST /completion/get-feedback-diff` 가 작업 정의 버전 간 변경 항목을 구조화된 JSON(`modifications`, `summary`) 으로 반환하는지 검증합니다. mock-llm 이 결정성 있는 modification 항목을 생성하도록 패턴 매칭됩니다.

## 사전 조건
- 시나리오 01 의 사전 조건과 동일.
- 시드 워크아이템의 `temp_feedback` 이 비어있지 않아야 diff 프롬프트가 의미 있는 입력을 받습니다.
- 시드된 proc_def 의 활동/시퀀스 구조에서 `find_next_item` 이 적어도 한 개의 활동 또는 게이트웨이를 반환해야 diff prompt 가 정상 구성됩니다 (`pdf_demo_proc` 은 `act_one`→`act_two` 직결 시퀀스를 포함).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 시드 데이터 | seed | `seed_files/e2e_seed.sql` | proc_def 활동 두 개 + 시퀀스, 워크아이템 1행 |
| diff prompt 패턴 | mock | `mock-llm` `/v1/chat/completions` | "Please analyze the activity and feedback to provide a detailed comparison" 매칭 시 modifications + summary JSON 반환 |

## 절차
1. Playwright 가 `POST http://localhost:8088/completion/get-feedback-diff` 요청을 보냅니다 (보조 프로토콜).
2. 본문에 `taskId=<시드 워크아이템 UUID>` 만 포함합니다 (`version_tag`, `version` 은 생략하여 arcv_id 경로를 검증).
3. 응답 상태와 본문 구조를 확인합니다.

## 기대 결과
- 응답 상태 코드는 `200` 입니다.
- 응답 본문은 `modifications` 와 `summary` 키를 포함합니다.
- `modifications` 의 각 변경 가능 항목(예: `description`, `instruction`)은 `before`, `after`, `changed` 필드를 포함합니다.
- mock-llm 이 주입한 결정성 문구 "피드백 반영하여 설명을 보강함" 이 `summary` 에 포함되어 있어야 합니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-feedback` | 작업 정의 버전 변경 비교 | 변경 비교 조회 성공 |

## 산출물
- 스크린샷 체크포인트: 해당 없음 (백엔드 프로토콜 검증).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-feedback/e2e/results/results.json`
