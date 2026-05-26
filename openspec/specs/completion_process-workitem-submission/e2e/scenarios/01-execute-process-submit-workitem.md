# E2E 시나리오 01: 프로세스 정의를 실행하여 워크아이템을 제출한다

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `프로세스 정의를 실행하여 워크아이템을 제출한다`
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
로그인한 사용자가 프로세스 정의 맵에서 시드된 프로세스를 실행할 때, 실행 다이얼로그가 열리며 프로세스 역할이 사용자 계정으로 자동 바인딩되고(`POST /role-binding`), 폼 값을 입력해 제출하면 워크아이템이 `status` `SUBMITTED`로 생성된다(`POST /complete`). 이 시나리오는 역할 바인딩 → 폼 제출 → 인스턴스 생성으로 이어지는 핵심 사용자 흐름과, 제출 폼 값이 워크아이템 `output`에 반영되는 계약 리스크를 검증한다.

## 사전 조건
- Docker Compose 스택(`docker-compose.e2e.yml`)이 기동되어 있고 `frontend`, `gateway`(nginx `:8088`), `completion`, `db`, `kong`, `auth`, `rest` 컨테이너가 정상이다.
- 공용 로그인 사용자 `e2e@uengine.org` / `e2epassword`가 `localhost` 테넌트에 시드되어 있다(`completion_agent-memory-chat` 스위트 seed).
- 본 스위트 seed(`seed_files/e2e_seed.sql`)로 `localhost` 테넌트에 실행 가능한 프로세스 정의 `e2e_pws_leave`가 등록되어 있다. 정의는 시작 이벤트·초기 활동·폼을 가지며, 역할 `담당자`의 기본값이 로그인 사용자 계정으로 설정되어 있다.
- 외부 LLM 경계는 `mock-llm` 스텁으로 대체된다. 역할 기본값이 시드되어 있어 `/role-binding`은 LLM 없이 기본값으로 해소된다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_process-workitem-submission/e2e/seed_files/e2e_seed.sql` | 실행 가능한 프로세스 정의·폼·테넌트를 결정적으로 준비 |
| 로그인 사용자 | seed | `e2e@uengine.org` (tenant `localhost`) | 브라우저 로그인 및 역할 기본 담당자 |
| `POST /completion/role-binding` | route | 게이트웨이 → `completion:8000/role-binding` | 실행 다이얼로그 진입 시 역할 자동 바인딩 |
| `POST /completion/complete` | route | 게이트웨이 → `completion:8000/complete` | 폼 제출 시 워크아이템 생성 |
| `mock-llm` | stub | `http://mock-llm:8080/v1` | 외부 LLM/임베딩 경계 대체(역할 기본값 시드로 미사용) |

## 절차
1. 사용자가 `/auth/login` 화면에 진입해 이메일·비밀번호를 입력하고 로그인 버튼을 누른다.
2. 사용자가 프로세스 정의 맵(`/definition-map`)으로 이동해 시드된 프로세스 정의 카드를 확인한다.
3. 사용자가 해당 프로세스 정의를 열어 상세 화면(`SubProcessDetail`)으로 진입한다.
4. 사용자가 상세 화면에서 "실행" 버튼을 눌러 실행 다이얼로그를 연다.
5. 실행 다이얼로그가 열리며 역할 매핑 영역에 담당자가 자동으로 채워진다(`/role-binding` 응답 반영).
6. 사용자가 실행 폼에 값을 입력하고 "제출 완료" 버튼을 누른다.
7. 제출이 완료되면 화면이 인스턴스 목록(`/instancelist/...`)으로 전환되고, 생성된 워크아이템이 표시된다.

## 기대 결과
- `POST /completion/role-binding` 응답은 `200`이며 `roleName`/`userId` 쌍의 `roleBindings`를 포함한다. 실행 다이얼로그의 역할 매핑 영역에 담당자가 채워진 상태가 화면에 보인다.
- `POST /completion/complete` 응답은 `200`이며 본문에 `proc_inst_id`, `proc_def_id`, `activity_id`, `status`가 `SUBMITTED`인 워크아이템 정보가 포함된다.
- 응답 본문의 `output`에 사용자가 입력한 폼 값이 반영되어 있다.
- 제출 후 브라우저가 `/instancelist/<proc_inst_id>` 경로로 이동하고, 인스턴스 화면에 제출된 워크아이템이 보인다.
- 요청 본문에 `version_tag`가 포함되고 `version`이 미지정(`null`)이어도 운영 버전 규칙으로 정의가 적용되어 제출이 성공한다(버전 미지정 시 운영 버전 적용).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 워크아이템 제출 | 폼 값을 담은 워크아이템 제출 성공 |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | 역할 매핑 해소 성공 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 버전 미지정 시 운영 버전 적용 |
| `completion_process-workitem-submission` | 테넌트 격리 | 테넌트별 데이터 분리(자사 테넌트 처리) |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-definition-map` | 로그인 후 프로세스 정의 맵에서 실행 대상 정의가 보이는 화면 | `process-gpt-completion_process-workitem-submission-01-definition-map.png` | 프로세스 정의 맵에서 실행할 프로세스를 선택합니다 |
  | `01-execute-dialog-roles` | 실행 다이얼로그가 열리고 역할 담당자가 자동 바인딩된 화면 | `process-gpt-completion_process-workitem-submission-01-execute-dialog-roles.png` | 실행 다이얼로그에서 역할 담당자가 자동으로 지정됩니다 |
  | `01-form-filled` | 실행 폼에 값을 입력하고 제출 직전인 화면 | `process-gpt-completion_process-workitem-submission-01-form-filled.png` | 작업 폼에 값을 입력한 뒤 제출을 준비합니다 |
  | `01-instance-submitted` | 제출 후 인스턴스 목록에 워크아이템이 표시된 화면 | `process-gpt-completion_process-workitem-submission-01-instance-submitted.png` | 제출이 완료되어 인스턴스 목록에 워크아이템이 등록됩니다 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
