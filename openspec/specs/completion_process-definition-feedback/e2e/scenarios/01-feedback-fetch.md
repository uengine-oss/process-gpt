# E2E 시나리오 01: 활동 정의 피드백을 요청하면 피드백 목록을 반환한다

## 메타데이터
- 스위트 슬러그: `completion_process-definition-feedback`
- 원본 명세 ID: `completion_process-definition-feedback`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `활동 정의 피드백을 요청하면 피드백 목록을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_process-definition-feedback/spec.md`

## 목적
설계자가 활동 정의에 대한 개선 피드백을 요청하는 백엔드 계약을 검증합니다. 게이트웨이를 경유한 `POST /completion/get-feedback` 호출이 시드된 작업/활동/정의를 기반으로 LLM(mock-llm) 으로부터 결정성 있는 피드백 문구 배열을 받아 그대로 응답하는지 확인합니다.

## 사전 조건
- 게이트웨이(nginx, `:8088`), `completion` 백엔드, Supabase(`db`/`kong`/`auth`/`rest`), 공유 `mock-llm` 컨테이너가 기동되어 있어야 합니다.
- 시드 SQL(`seed_files/e2e_seed.sql`) 이 `pdf_demo_proc` 프로세스 정의, `proc_def_version`, `bpm_proc_inst`, `todolist` 한 행(`temp_feedback`, `log` 포함)을 적재해야 합니다.
- 공유 `mock-llm` 의 `mock_llm.py` 가 본 스펙용 feedback / diff 프롬프트 패턴을 인식할 수 있어야 합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `pdf_demo_proc` | seed | `seed_files/e2e_seed.sql` | proc_def + proc_def_version (활동 act_one, act_two, 시퀀스 포함) |
| `bpm_proc_inst` | seed | `seed_files/e2e_seed.sql` | proc_def_version 매핑(arcv_id 도출 경로) |
| `pdf-feedback-task-0001` 워크아이템 | seed | `seed_files/e2e_seed.sql` | `temp_feedback`, `log`, activity_id='act_one' |
| feedback prompt 패턴 | mock | `mock-llm` `/v1/chat/completions` | "You are a helpful assistant that can provide feedback" 매칭 시 `{"feedback": ["..."]}` 반환 |

## 절차
1. Playwright 가 게이트웨이(`http://localhost:8088`) 의 `/completion/get-feedback` 라우트로 `POST` 요청을 보냅니다 (보조 프로토콜).
2. 요청 본문에는 `processDefinitionId='pdf_demo_proc'`, `activityId='act_one'`, `taskId=<시드 워크아이템 UUID>` 를 포함합니다.
3. 응답 상태와 본문(피드백 배열)을 확인합니다.

## 기대 결과
- 응답 상태 코드는 `200` 입니다.
- 응답 본문은 한국어 피드백 문자열로 구성된 JSON 배열이며, 최소 한 개 이상의 문항을 포함합니다.
- mock-llm 이 반환한 피드백 항목 중 본 스위트가 주입한 결정성 문구 "설명을 더 구체적으로 보강해 주세요." 가 포함되어 있어야 합니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-definition-feedback` | 활동 정의 피드백 제공 | 활동 피드백 조회 성공 |

## 산출물
- 스크린샷 체크포인트: 해당 없음 (백엔드 프로토콜 검증).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-definition-feedback/e2e/results/results.json`
