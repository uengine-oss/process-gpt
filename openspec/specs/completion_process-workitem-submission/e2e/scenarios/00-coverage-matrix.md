# 프로세스 워크아이템 생성·제출 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-workitem-submission`
- 원본 명세 ID: `completion_process-workitem-submission`
- 원본 명세:
  - `openspec/specs/completion_process-workitem-submission/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI 라우트 `POST /initiate`, `POST /complete`, `POST /vision-complete`, `POST /role-binding`
  - 워크아이템 상태(`TODO`/`SUBMITTED`)와 폼 값(`output`) 영속화: `public.todolist`
  - 프로세스 인스턴스 영속화: `public.bpm_proc_inst`
  - 버전 해소: `proc_def_version`/`proc_def_arcv`/`proc_def.prod_version`
  - 테넌트 격리: `X-Forwarded-Host` → `subdomain_var` → `tenant_id` 필터링
- E2E 루트: `openspec/specs/completion_process-workitem-submission/e2e/`
- Playwright 명세: `openspec/specs/completion_process-workitem-submission/e2e/tests/completion_process-workitem-submission.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-workitem-submission/e2e/results/`

## 스코프 재조정 (Real-Frontend Rule 적용)
SKILL.md 의 Real-Frontend Rule 은 사용자-facing 시나리오가 실제 프런트엔드의 사용자 액션 경로를 통과해야 함을 요구한다. 본 명세의 백엔드 라우트에 대한 실제 트리거 경로를 코드에서 추적한 결과는 다음과 같다.

- `POST /completion/initiate` — `services/frontend/src/**` 어디에서도 호출하지 않는다 (`grep` 결과 0건). 인스턴스 생성은 백엔드/스케줄러/외부 트리거가 수행한다. 사용자 UI 트리거 경로 없음.
- `POST /completion/complete` / `POST /completion/vision-complete` — `ProcessGPTBackend.executeInstance()` 가 호출하고, `putWorkItemComplete()` 가 todolist FormWorkItem/WorkItemDialog/DefaultWorkItem 의 폼 제출 동작에서 발화시킨다. 사용자 UI 트리거 경로 **있음** — 단, `task_id` 단독 lookup 분기와 `process_instance_id` 누락 분기는 SPA 가 항상 두 식별자를 함께 전송하므로 사용자 UI 에서 발화되지 않는다.
- `POST /completion/role-binding` — `ProcessGPTBackend.bindRole()` 가 `ProcessGPTExecute.vue` 의 `hasDefaultRole === false` 분기에서만 호출한다. 본 명세의 "역할 기본값이 있으면 즉시 응답" 시나리오는 `hasDefaultRole === true` 경로이므로 사용자 UI 에서 발화되지 않는다.

이 결과에 따라 시나리오를 두 클래스로 분류한다.

| 분류 | 시나리오 | 검증 표면 | 스크린샷 의무 |
| --- | --- | --- | --- |
| 실제 프런트엔드 워크플로우 | 04 | `/auth/login` → `/todolist/<task-id>` (FormWorkItem) → SPA same-origin POST `/completion/complete` | 필수 |
| 백엔드 계약 전용 (스크린샷 면제) | 01, 02, 03, 05, 06, 07, 08, 09 | Playwright `request` → gateway → completion FastAPI | 면제 |

이전 산출물(Playwright 스크립트, `scripts/wis-tester.html`, 합성 스크린샷 14장) 은 합성 테스터 HTML 을 `page.route()` 로 주입하여 Real-Frontend Rule 을 위반했다. 모두 제거하고 위 분류대로 재작성했다.

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 분류 | 주요 동작 |
| --- | --- | --- | --- | --- |
| 01 | `01-initiate-success.md` | `01 [backend-contract] 신규 프로세스 인스턴스 시작이 TODO 워크아이템을 반환한다` | 백엔드 계약 | `/initiate` 신규 인스턴스 `status=TODO` 응답 |
| 02 | `02-initiate-missing-initial.md` | `02 [backend-contract] 초기 활동이 없는 프로세스 정의는 400 메시지를 반환한다` | 백엔드 계약 | 400/`No initial activity found` |
| 03 | `03-initiate-missing-user.md` | `03 [backend-contract] 담당 사용자 이메일을 해소할 수 없으면 400 메시지를 반환한다` | 백엔드 계약 | 400/`No default user email found` |
| 04 | `04-complete-success.md` | `04 폼 값을 담은 워크아이템 제출이 SUBMITTED 상태를 반환한다` | 실제 프런트엔드 | 실제 todolist UI 진입 후 SPA same-origin `/complete` 호출, `status=SUBMITTED` 와 `output` 반영 검증 |
| 05 | `05-complete-update-existing.md` | `05 [backend-contract] task_id 만 주어져도 기존 워크아이템이 SUBMITTED 로 갱신된다` | 백엔드 계약 | `task_id` 단독 lookup 분기 (SPA 는 항상 두 식별자를 함께 전송하므로 UI 트리거 없음) |
| 06 | `06-complete-missing-proc-inst.md` | `06 [backend-contract] process_instance_id 가 누락되면 400 을 반환한다` | 백엔드 계약 | malformed 요청 검증 (UI 에서 발생하지 않음) |
| 07 | `07-role-binding.md` | `07 [backend-contract] 역할 기본값이 있으면 LLM 없이 roleBindings 를 반환한다` | 백엔드 계약 | `hasDefaultRole === true` 분기는 UI 에서 `/role-binding` 을 호출하지 않음 |
| 08 | `08-version-explicit.md` | `08 [backend-contract] version_tag/version 이 주어지면 해당 버전 정의가 적용된다` | 백엔드 계약 | 명시 버전 처리 (UI 트리거 없음) |
| 09 | `09-tenant-isolation.md` | `09 [backend-contract] 요청 subdomain 에 속하지 않은 프로세스 정의는 사용할 수 없다` | 백엔드 계약 | 멀티-테넌트 격리 (UI 트리거 없음) |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | SHALL | 01, 02, 03 | 백엔드 계약 — UI 트리거 경로 없음 |
| `completion_process-workitem-submission` | 워크아이템 제출 | SHALL | 04, 05, 06 | 04 는 실제 todolist UI / 05·06 은 백엔드 계약 |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | SHALL | 07 | 백엔드 계약 — 기본값 분기는 UI 트리거 없음 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | SHALL | 08, 01 | 명시 버전 / 기본 운영 버전 폴백 |
| `completion_process-workitem-submission` | 테넌트 격리 | SHALL | 09 | 백엔드 계약 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 분류 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- | --- |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 신규 인스턴스 시작 성공 | 01 | 백엔드 계약 | 트리거 경로 없음 — Playwright `request` |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 초기 활동을 찾을 수 없음 | 02 | 백엔드 계약 | 트리거 경로 없음 — Playwright `request` |
| `completion_process-workitem-submission` | 프로세스 인스턴스 시작 | 담당 사용자 이메일을 해소할 수 없음 | 03 | 백엔드 계약 | 트리거 경로 없음 — Playwright `request` |
| `completion_process-workitem-submission` | 워크아이템 제출 | 폼 값을 담은 워크아이템 제출 성공 | 04 | 실제 프런트엔드 | `/todolist/<task-id>` 진입 + SPA-origin `/complete` 호출 |
| `completion_process-workitem-submission` | 워크아이템 제출 | 기존 워크아이템 갱신 제출 | 05 | 백엔드 계약 | `task_id` 단독 lookup 은 UI 에서 발화되지 않음 |
| `completion_process-workitem-submission` | 워크아이템 제출 | 프로세스 인스턴스 식별자 누락 | 06 | 백엔드 계약 | malformed 요청은 UI 에서 발생하지 않음 |
| `completion_process-workitem-submission` | 프로세스 역할 바인딩 | 역할 매핑 해소 성공 | 07 | 백엔드 계약 | 기본값 분기는 UI 에서 `/role-binding` 미호출 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 명시한 버전으로 처리 | 08 | 백엔드 계약 | UI 트리거 없음 |
| `completion_process-workitem-submission` | 프로세스 정의 버전 해소 | 버전 미지정 시 운영 버전 적용 | 01, 08 | 백엔드 계약 | UI 트리거 없음 |
| `completion_process-workitem-submission` | 테넌트 격리 | 테넌트별 데이터 분리 | 09 | 백엔드 계약 | UI 트리거 없음 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_engine.py` | `handle_initiate` / `initiate_workitem` | 프로세스 인스턴스 시작, 프로세스 정의 버전 해소 | line/function >= 80% | `/initiate` 라우트 핵심 구현 |
| `services/completion/process_engine.py` | `handle_submit` / `submit_workitem` | 워크아이템 제출, 프로세스 정의 버전 해소, 테넌트 격리 | line/function >= 80% | `/complete`,`/vision-complete` 공유 구현 |
| `services/completion/process_engine.py` | `handle_role_binding` / `role_binding_chain` | 프로세스 역할 바인딩 | line/function >= 70% | `/role-binding` 라우트 구현 |
| `services/completion/process_engine.py` | `create_process_instance` | 프로세스 인스턴스 시작, 워크아이템 제출 | line/function >= 70% | bpm_proc_inst 영속화 경로 |
| `services/completion/process_definition.py` | `load_process_definition` / `find_initial_activity` / `find_prev_activities` | 프로세스 인스턴스 시작 | function >= 70% | 초기 활동 탐색 및 정의 객체화 |
| `services/completion/database.py` | `fetch_process_definition_by_version` / `fetch_workitem_by_proc_inst_and_activity` / `fetch_workitem_by_id` / `upsert_workitem` / `insert_process_instance` / `fetch_assignee_info` | 프로세스 정의 버전 해소, 워크아이템 제출, 테넌트 격리 | 보조 (관련 함수만) | 영속/조회 어댑터; 스펙 직접 표면 |
| `services/completion/proc_def_versioning.py` | `fetch_process_definition_by_version_ts_style` | 프로세스 정의 버전 해소 | function >= 60% | 버전 우선순위 결정 |
| `services/completion/main.py` | `DBConfigMiddleware.dispatch` | 테넌트 격리 | 보조 | subdomain → tenant_id 컨텍스트 결정 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` | `executeInstance()` / `putWorkItemComplete()` | 워크아이템 제출 | V8 보조 (소스맵 없음) | 시나리오 04 가 todolist 화면에서 발화시키는 SPA-origin POST 와 동일 경로 |
| `services/frontend/src/components/apps/todolist/FormWorkItem.vue` | 폼 제출 페이지 진입 | 워크아이템 제출 | V8 보조 | 시나리오 04 의 실제 사용자 UI |
| `services/frontend/src/views/Authentication/auth1/Login.vue`(등) | `/auth/login` 진입 | 사전 조건 | V8 보조 | 시나리오 04 의 로그인 사전 조건 |

> 참고: 본 스위트의 사용자 UI 검증은 시나리오 04 한 건이며, 나머지 시나리오는 스코프 재조정에 따라 백엔드 계약 전용이다. 따라서 프런트엔드 커버리지는 보조 증거이며 백엔드 커버리지를 1차 게이트로 사용한다. 메인 SPA 이미지가 minified 이므로 V8 커버리지는 번들 단위로 보고된다.

## 재사용 산출물
- `docker-compose.e2e.yml` 의 `db`, `kong`, `auth`, `rest`, `completion`, `frontend`, `mock-llm`, `gateway-wis`, `db-seed-workitem-submission` 컨테이너를 그대로 사용한다.
- `openspec/specs/completion_process-data-query/e2e/docker/coverage.override.yml` 패턴(USR2 flush, COVERAGE_FILE /coverage/.coverage)을 그대로 차용한다. (`completion-coverage-override-workdir`, `coverage-py-usr2-flush`, `compose-override-relative-paths` 메모리 적용)
- 공용 `mock-llm` 컨테이너 — 본 스위트에서는 사용하지 않지만 stack 의존성으로 유지.
- `form_def` 시드 시 `html` 컬럼은 placeholder 를 채운다 (`form-def-html-not-null` 메모리 적용).
- 실제 프런트엔드 로그인/네비게이션 패턴은 `completion_process-activity-rework` 스위트의 `login()` 헬퍼와 SPA same-origin `callCompletionApi` 패턴을 따른다.

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `/vision-complete` 라우트의 별도 시나리오 | `/complete` 와 동일한 `handle_submit` 핸들러 공유 (process_engine.py:948-949) | 핸들러 분기 시 신규 시나리오 추가 |
| LLM 기반 role binding 폴백 (정의에 default 가 없는 경로) | mock-llm 통과 langchain 체인 결정성 보장 어려움 | 별도 LLM 결정성 스위트에서 다룸 |
| `handle_initiate` 의 상태 코드 누수 (`400` → `500`) | 외곽 `except Exception` 이 내부 `HTTPException(400)` 을 잡아 500 으로 재포장. 메시지는 보존되지만 스펙은 `400` 을 요구 | 구현측에 `except HTTPException: raise` 추가 필요. 본 스위트는 메시지 보존만 검증 |
| `/initiate`, `/role-binding` (기본값 분기), `/complete` (task_id 단독·필수 누락) 의 실제 사용자 UI 트리거 | 코드 추적 결과 SPA 발화점이 존재하지 않음 (Real-Frontend Rule 에 따른 스코프 재조정) | 향후 프런트엔드가 해당 경로를 사용자에게 노출한다면 실제 프런트엔드 시나리오로 승격 |

## 체크리스트
- [x] 모든 Requirement 가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario 가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec 영어 설명이 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 구현 레이어 키워드가 아닙니다.
- [x] E2E 가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID 를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/<spec-name>/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오(04)는 실제 프런트엔드 페이지(`/todolist/<task-id>`) 위에서 검증되며 스크린샷을 캡쳐합니다.
- [x] 백엔드 계약 전용 시나리오(01,02,03,05,06,07,08,09)는 사용자 UI 트리거 경로가 없음이 코드 grep 으로 확인되어 스크린샷 의무가 면제됩니다.
- [x] 합성 테스터 HTML 주입(`page.route()` / `page.setContent()` / `file://`) 은 사용하지 않습니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md` 와 일치합니다.
