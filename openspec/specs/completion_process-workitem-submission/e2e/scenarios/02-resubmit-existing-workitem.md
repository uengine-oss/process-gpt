# E2E 시나리오 02: 할 일 목록의 기존 워크아이템을 제출한다

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `할 일 목록의 기존 워크아이템을 제출한다`
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
사용자가 할 일 목록(`/todolist`)에서 이미 존재하는 `TODO` 워크아이템을 열어 폼 값을 입력하고 제출하면, 새 워크아이템 행이 추가로 만들어지지 않고 동일 워크아이템이 `status` `SUBMITTED`로 갱신된다(`POST /complete` + `task_id`). 이 시나리오는 요청에 기존 워크아이템을 가리키는 `task_id`가 포함될 때 같은 행이 갱신되는지(중복 생성 방지)를 사용자 화면 흐름으로 검증한다.

## 사전 조건
- Docker Compose 스택(`docker-compose.e2e.yml`)이 기동되어 있고 `frontend`, `gateway`, `completion`, `db`, `kong`, `auth`, `rest` 컨테이너가 정상이다.
- 공용 로그인 사용자 `e2e@uengine.org` / `e2epassword`가 `localhost` 테넌트에 시드되어 있다.
- 본 스위트 seed로 `localhost` 테넌트에 프로세스 인스턴스(`bpm_proc_inst`)와 그 인스턴스의 기존 `TODO` 워크아이템(`todolist`)이 등록되어 있다. 워크아이템의 담당자(`user_id`)는 로그인 사용자다.
- 기존 워크아이템은 시드 시점에 고정된 `task_id`(UUID)를 가지며, 제출 후 상태 전이를 결정적으로 비교할 수 있다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-workitem-submission/e2e/seed_files/e2e_seed.sql` | 기존 `TODO` 워크아이템과 인스턴스를 결정적으로 준비 |
| 기존 워크아이템 | seed | `todolist` 행 (`status` `TODO`) | 사용자가 할 일 목록에서 열어 제출할 대상 |
| 프로세스 인스턴스 | seed | `bpm_proc_inst` 행 | 기존 워크아이템이 속한 실행 인스턴스 |
| `POST /completion/complete` | route | 게이트웨이 → `completion:8000/complete` | 기존 워크아이템 갱신 제출 |

## 절차
1. 사용자가 `/auth/login` 화면에서 이메일·비밀번호를 입력하고 로그인한다.
2. 사용자가 할 일 목록(`/todolist`)으로 이동해 시드된 `TODO` 작업 카드를 확인한다.
3. 사용자가 해당 작업을 열어 작업 상세 폼을 표시한다.
4. 사용자가 폼에 값을 입력하고 "제출 완료" 버튼을 누른다.
5. 제출이 완료되면 작업 상태가 갱신되어 화면에 반영된다.

## 기대 결과
- `POST /completion/complete` 요청 본문에 시드된 기존 워크아이템의 `task_id`가 포함된다.
- 응답은 `200`이며 본문의 워크아이템 `id`가 시드된 `task_id`와 동일하고(새 UUID가 아님), `status`가 `SUBMITTED`로 전이된다.
- 응답 본문의 `output`에 사용자가 입력한 폼 값이 반영되어 있다.
- 제출 후 할 일 목록/작업 화면에서 해당 작업이 더 이상 `TODO`로 보이지 않고, 동일 활동에 대한 워크아이템이 중복으로 생성되지 않는다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 워크아이템 제출 | 기존 워크아이템 갱신 제출 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-todolist` | 할 일 목록에 시드된 `TODO` 작업이 보이는 화면 | `process-gpt-completion_process-workitem-submission-02-todolist.png` | 할 일 목록에서 처리할 작업을 선택합니다 |
  | `02-task-form` | 기존 작업을 열어 폼에 값을 입력한 화면 | `process-gpt-completion_process-workitem-submission-02-task-form.png` | 작업 폼에 값을 입력한 뒤 제출을 준비합니다 |
  | `02-task-submitted` | 제출 후 작업이 `SUBMITTED`로 갱신된 화면 | `process-gpt-completion_process-workitem-submission-02-task-submitted.png` | 제출이 완료되어 작업 상태가 갱신됩니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
