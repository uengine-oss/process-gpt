# E2E 시나리오 01: 재작업 다이얼로그에서 후보 활동 목록을 확인한다

## 메타데이터
- 스위트 슬러그: `completion_process-activity-rework`
- 원본 명세 ID: `completion_process-activity-rework`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `재작업 다이얼로그에서 후보 활동 목록을 확인한다`
- 원본 명세:
  - `openspec/specs/completion_process-activity-rework/spec.md`

## 목적
사용자가 자신이 완료한 워크아이템 상세 화면에서 "재작업" 버튼을 클릭했을 때, completion 백엔드가 `POST /get-rework-activities`로 후보 활동(`reference`/`all`)을 반환하고, 다이얼로그에 라디오 선택지와 활동 칩이 표시되는지 검증한다. 이 시나리오는 사용자가 어떤 단계까지 되돌릴지를 시각적으로 선택할 수 있어야 한다는 제품 계약을 보장한다.

## 사전 조건
- 루트 `docker-compose.e2e.yml`이 부팅되어 frontend(:8088), gateway(nginx), completion(:8000), kong/auth/rest/db가 healthy 상태
- `db-seed-process-activity-rework` 시드가 성공적으로 완료되어 다음 데이터가 존재:
  - 테넌트 `localhost`
  - 로그인 사용자 (`reworker-e2e@uengine.org`)
  - 프로세스 정의 `rework_demo_proc` (3개 활동: `act_a`, `act_b`, `act_c` 직선 흐름)
  - 프로세스 인스턴스 `rework_demo_proc.e2e-instance-0001`
  - DONE 상태의 todolist 워크아이템 (`act_a`, `act_b`, `act_c`), 모두 동일 사용자 소유

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-activity-rework/e2e/seed_files/e2e_seed.sql` | 프로세스 정의/인스턴스/완료 워크아이템 시드 |
| reworker-e2e@uengine.org | auth | Supabase GoTrue (`POST /auth/v1/token?grant_type=password`) | 사용자 로그인 토큰 발급 |
| 브라우저 UI | page | `http://localhost:8088/todolist/<taskId>` | WorkItem 상세 진입 |

## 절차
1. 사용자가 브라우저로 `http://localhost:8088`에 접속해 `reworker-e2e@uengine.org` 계정으로 로그인한다.
2. 사용자가 시드된 DONE 워크아이템(`act_b`) 상세 화면(`/todolist/<taskId>`)으로 이동한다.
3. 사용자가 화면 상단의 "재작업" 버튼을 클릭한다.
4. 재작업 다이얼로그가 열리고 "이 단계만 재작업 / 참조 단계 포함 / 이후 모든 단계 포함" 세 가지 라디오와 활동 칩이 표시되는 것을 확인한다.
5. "이후 모든 단계 포함" 라디오를 클릭하면 `act_b`, `act_c` 칩이 강조되는 것을 확인한다.
6. 다이얼로그 우측 상단 X 버튼으로 다이얼로그를 닫는다.

## 기대 결과
- 재작업 버튼 클릭 후 다이얼로그가 열려야 한다.
- 다이얼로그에 "현재 활동만", "참조 활동 포함", "이후 모든 활동 포함" 세 가지 옵션이 모두 표시되어야 한다.
- 백엔드 응답 `all`에는 `act_b`, `act_c`가 포함되어야 한다(`act_a`는 이전 단계라 제외).
- `POST /get-rework-activities`가 200으로 응답하고 `reference`와 `all` 키를 모두 포함해야 한다.
- UI 닫기 동작 시 다이얼로그가 사라져야 한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-activity-rework` | 재작업 가능 활동 조회 | 재작업 후보 조회 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `workitem-detail-done` | 완료된 워크아이템 상세 화면 (재작업 버튼이 보이는 상태) | `process-gpt-completion_process-activity-rework-01-workitem-detail-done.png` | 완료한 작업 상세 화면에서 재작업 버튼이 노출됩니다 |
  | `rework-dialog-open` | 재작업 다이얼로그가 열려 라디오 3종과 활동 칩이 표시된 상태 | `process-gpt-completion_process-activity-rework-01-rework-dialog-open.png` | 어디까지 재작업할지 선택하는 다이얼로그가 표시됩니다 |
  | `rework-dialog-include-all` | "이후 모든 활동 포함" 라디오를 선택해 후속 활동 칩이 강조된 상태 | `process-gpt-completion_process-activity-rework-01-rework-dialog-include-all.png` | 이후 활동까지 모두 재작업 대상으로 선택한 화면입니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-activity-rework/e2e/results/results.json`
