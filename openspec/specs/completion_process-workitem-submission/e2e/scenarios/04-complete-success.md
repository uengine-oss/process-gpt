# E2E 시나리오 04: 폼 값을 담은 워크아이템 제출 성공 (실제 프런트엔드)

## 메타데이터
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `04 폼 값을 담은 워크아이템 제출이 SUBMITTED 상태를 반환한다`
- 분류: 실제 프런트엔드 워크플로우 (스크린샷 필수)
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`

## 목적
사용자가 todolist 워크아이템 페이지(`/todolist/<task-id>`) 에 진입해 폼을 제출하는 실제 프런트엔드 워크플로우를 검증한다. 폼 제출은 `ProcessGPTBackend.executeInstance()` 의 axios POST 와 동일한 SPA-origin POST 로 `/completion/complete` 를 호출하며, `status=SUBMITTED` 와 폼 값 `output` 반영을 확인한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택과 시드가 완료되어 있다.
- 시드로 생성된 인스턴스 `wis-existing-inst` 와 TODO 워크아이템(`task_id = 11111111-1111-1111-1111-111111111111`) 이 존재한다.
- 인증된 사용자 `e2e-wis@uengine.org` (비밀번호 `e2epassword`) 가 `auth.users` 에 존재한다.
- 게이트웨이 `gateway-wis`(포트 8090) 가 `/` → frontend, `/completion/*` → completion 으로 라우팅한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 시드 사용자 `e2e-wis@uengine.org` | seed | `e2e_seed.sql` (auth.users + public.users) | 로그인 사전 조건 |
| 시드 인스턴스 `wis-existing-inst` + TODO 워크아이템 | seed | `e2e_seed.sql` (bpm_proc_inst + todolist) | `/todolist/<task-id>` 진입 대상 |
| 실제 프런트엔드 SPA | runtime | `gateway-wis:8090` → `frontend:8080` | 로그인/네비게이션/SPA-origin POST 의 발화 컨텍스트 |

## 절차
1. 사용자가 브라우저로 `http://localhost:8090/auth/login` 에 접속한다.
2. 이메일 `e2e-wis@uengine.org` 와 비밀번호를 입력하고 로그인 버튼을 누른다.
3. 사용자가 `/todolist/11111111-1111-1111-1111-111111111111` 페이지로 이동해 워크아이템 폼 화면이 노출되는지 확인한다.
4. 사용자가 폼 값(`leave_days=5`) 을 담아 제출한다. 제출 동작은 ProcessGPTBackend.executeInstance() 가 호출하는 same-origin `POST /completion/complete` 를 SPA 컨텍스트에서 발화시킨다.
5. 응답 JSON 의 `status=SUBMITTED` 와 `output` 에 폼 값이 반영되었는지 확인한다.

## 기대 결과
- `/auth/login` 에서 로그인 후 `/auth/login` 이 아닌 경로로 리다이렉트된다.
- `/todolist/<task-id>` 페이지가 정상 렌더링된다 (스크린샷 `04-todolist-form` 캡처).
- `POST /completion/complete` 응답 상태 코드는 `200`.
- 응답 본문은 `status=SUBMITTED` 이며 응답 직렬화에 폼 값 `5` 가 포함된다 (스크린샷 `04-todolist-submitted` 캡처).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-workitem-submission` | 워크아이템 제출 | 폼 값을 담은 워크아이템 제출 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `04-todolist-form` | `/todolist/<task-id>` 진입 직후의 실제 폼 화면 | `process-gpt-completion_process-workitem-submission-04-todolist-form.png` | 사용자가 todolist 에서 워크아이템 폼을 여는 첫 화면 |
  | `04-todolist-submitted` | `/completion/complete` 가 `SUBMITTED` 로 응답한 직후의 화면 | `process-gpt-completion_process-workitem-submission-04-todolist-submitted.png` | 폼 제출 후 SUBMITTED 상태가 확정된 화면 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-workitem-submission/e2e/results/results.json`
