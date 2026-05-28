# 콜봇 할 일 관리 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_callbot-task-management`
- 원본 명세 ID: `completion_callbot-task-management`
- 원본 명세:
  - `openspec/specs/completion_callbot-task-management/spec.md`
- 백엔드/제품 계약:
  - 소유 백엔드: `services/completion/callbot_api.py` (FastAPI `APIRouter(prefix="/complete-callbot")`)
  - 데이터 소스: Supabase `public.users`, `public.todolist`, `public.proc_def`, `public.form_def`
  - 후속 워커: `services/completion/polling_service` (제출된 작업의 자동 처리)
  - 외부 소비자: 음성 콜봇/Twilio 클라이언트 (브라우저 사용자가 직접 접근하지 않는 protocol API)
- E2E 루트: `openspec/specs/completion_callbot-task-management/e2e/`
- Playwright 명세: `openspec/specs/completion_callbot-task-management/e2e/tests/completion_callbot-task-management.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_callbot-task-management/e2e/results/`

## 사용자 검증 표면 메모
콜봇 API는 음성 통화 클라이언트(시스템 간 비-사용자-facing 프로토콜)를 위한 API이며, 저장소 안에는 이 엔드포인트를 호출하는 프론트엔드 UI가 존재하지 않는다. SKILL의 User-Action Rule 예외(`non-user-facing protocol tests`)에 해당하므로 Playwright `request` 픽스처를 통한 HTTP 레벨 시나리오로 검증하며, 스크린샷 체크포인트는 작성하지 않는다. 그 대신 결과 검증을 위해 응답 본문/HTTP 상태/DB row 상태 전이를 명시적으로 단언한다.

## 재사용 산출물
- 공유 Docker Compose: `docker-compose.e2e.yml`의 `db`/`kong`/`completion` 서비스를 그대로 사용한다.
- 인접 스위트 패턴: `openspec/specs/completion_automated-task-execution/e2e/` (Playwright config, coverage 수집 방식, polling 워커 SUBMITTED→DONE 전이 검증 방식).
- 백엔드 coverage 헬퍼: `openspec/e2e/memories/coverage-py-usr2-flush.md`의 USR2 flush 패턴(장기 실행 uvicorn에서 coverage 데이터를 강제 flush).

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-caller-info.md` | `발신자 식별: 등록 사용자와 익명 발신자에 대해 인사말을 반환한다` | `/complete-callbot/caller-info` GET 두 경로 (등록 user_id, client:Anonymous) 검증 |
| 02 | `02-user-tasks.md` | `사용자 할 일 목록 조회와 상태 필터/누락 처리` | `/complete-callbot/user-todolist`, `/complete-callbot/tasks` 상태 필터 및 `user_id` 누락 시 422 |
| 03 | `03-task-detail.md` | `작업 상세 조회: 폼 스키마와 참조 폼 / 미존재 시 404` | `/complete-callbot/task/{task_id}` 성공+`form_schema`/`reference_forms`/404 |
| 04 | `04-task-update.md` | `작업 필드 수정: PATCH로 폼 데이터 병합` | `/complete-callbot/task/{task_id}` PATCH 후 `output` 병합 검증 |
| 05 | `05-task-submit.md` | `작업 제출: 상태 SUBMITTED 전이로 폴링 대상 진입` | `/complete-callbot/task/{task_id}/submit` 호출 후 DB `status='SUBMITTED'` 확인 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_callbot-task-management` | 발신자 식별 | SHALL | 01 | `caller-info` GET |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | SHALL | 02 | `user-todolist` + `tasks` + `status_filter` |
| `completion_callbot-task-management` | 작업 상세 조회 | SHALL | 03 | `task/{task_id}` GET |
| `completion_callbot-task-management` | 작업 필드 수정 | SHALL | 04 | `task/{task_id}` PATCH |
| `completion_callbot-task-management` | 작업 제출 | SHALL | 05 | `task/{task_id}/submit` POST |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_callbot-task-management` | 발신자 식별 | 등록 사용자 발신자 식별 | 01 | API 응답 본문 (`username`/`user_id`/`email`/`tenant_id`/`greeting`) |
| `completion_callbot-task-management` | 발신자 식별 | 식별 실패 시 기본 응답 | 01 | API HTTP 200 + 기본 `greeting` |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 할 일 목록 조회 성공 | 02 | API 응답 (`tasks`/`count`/`overdue_count`) |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 상태 필터 적용 | 02 | `status_filter=in_progress` 응답 (TODO 제외) |
| `completion_callbot-task-management` | 사용자 할 일 목록 조회 | 사용자 식별자 누락 | 02 | HTTP 422 + FastAPI validation error |
| `completion_callbot-task-management` | 작업 상세 조회 | 작업 상세 조회 성공 | 03 | API 응답 (`task`/`form_schema`/`current_data`/`reference_forms`) |
| `completion_callbot-task-management` | 작업 상세 조회 | 작업을 찾을 수 없음 | 03 | HTTP 404 + `Task not found` |
| `completion_callbot-task-management` | 작업 필드 수정 | 작업 필드 수정 성공 | 04 | API 응답 + DB `output` 병합 확인 |
| `completion_callbot-task-management` | 작업 제출 | 작업 제출 성공 | 05 | API 응답 + DB `status='SUBMITTED'`/`end_date`/`consumer=null` |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/callbot_api.py` | `get_caller_info` (GET `/complete-callbot/caller-info`) | 발신자 식별 | line >= 75% | 라우트 본체 직접 구현 |
| `services/completion/callbot_api.py` | `get_user_todolist` (GET `/complete-callbot/user-todolist`) | 사용자 할 일 목록 조회 | line >= 75% | 라우트 본체 직접 구현 |
| `services/completion/callbot_api.py` | `get_user_tasks` (GET `/complete-callbot/tasks`) | 사용자 할 일 목록 조회 | line >= 70% | 상태 필터 및 422 분기 포함 |
| `services/completion/callbot_api.py` | `get_task_detail` (GET `/complete-callbot/task/{task_id}`) | 작업 상세 조회 | line >= 65% | 폼 스키마/참조 폼 분기 포함 |
| `services/completion/callbot_api.py` | `update_task_form` (PATCH `/complete-callbot/task/{task_id}`) | 작업 필드 수정 | line >= 70% | `output` 병합 로직 |
| `services/completion/callbot_api.py` | `submit_task` (POST `/complete-callbot/task/{task_id}/submit`) | 작업 제출 | line >= 75% | 상태 전이 단일 분기 |
| `services/completion/database.py` | `fetch_user_info_by_uid`, `fetch_todolist_by_user_id`, `fetch_ui_definition_by_activity_id` | 발신자 식별/할 일 조회/상세 | 보조 (관련 함수 진입) | callbot_api가 직접 호출하는 어댑터 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| 해당 없음 | - | - | - | 콜봇 API는 외부 음성 클라이언트용 protocol API이며 저장소 내 프론트엔드가 이 엔드포인트를 호출하지 않음 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 프론트엔드 coverage / UI 스크린샷 | 본 스펙은 시스템 간 protocol API로 저장소 내 소비 UI가 없음 | 본 스위트에서는 수집/캡처하지 않으며 실행 요약에 명시한다 |
| `submit` 이후 polling worker가 실제로 다음 activity로 진행시키는 흐름 | 동일 폴링 워커 경로는 `completion_automated-task-execution` 스위트가 이미 검증함 | 본 스펙에서는 `status='SUBMITTED'` 전이까지만 단언, 진행은 인접 스위트의 검증을 인용 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 범위입니다.
- [x] 원본 명세의 서비스 접두어가 구현 레이어가 아닙니다 (`completion`).
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID와 스위트 슬러그가 동일합니다.
- [x] E2E 시나리오, 테스트, seed, 결과는 `openspec/specs/completion_callbot-task-management/e2e/` 아래에 응집됩니다.
- [ ] 사용자-facing 시나리오는 브라우저 UI로 검증합니다. → 본 스펙은 비-사용자-facing protocol API이므로 예외 적용(상단 메모 참조).
- [ ] 시나리오별 스크린샷 체크포인트. → 동일 사유로 비적용.
- [x] 스펙 관련 백엔드 파일/함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
