# completion_process-activity-rework E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-activity-rework`
- 원본 명세 ID: `completion_process-activity-rework`
- 원본 명세:
  - `openspec/specs/completion_process-activity-rework/spec.md`
- 백엔드/제품 계약:
  - completion FastAPI 라우터: `POST /get-rework-activities`, `POST /rework-complete` (`services/completion/process_engine.py`)
  - 보상 코드 준비: `services/completion/compensation_handler.py::generate_compensation`
  - 워크아이템/이벤트 영속화: `public.todolist`, `public.events`, `public.mcp_python_code`
  - 프론트엔드 트리거: `services/frontend/src/components/apps/todolist/WorkItem.vue` + `ReworkDialog.vue`
- E2E 루트: `openspec/specs/completion_process-activity-rework/e2e/`
- Playwright 명세: `openspec/specs/completion_process-activity-rework/e2e/tests/completion_process-activity-rework.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-activity-rework/e2e/results/`

## 재사용 산출물
- 공유 인프라: 루트 `docker-compose.e2e.yml` (db, kong, auth, rest, completion, frontend, gateway)
- 공유 mock-llm: `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py` (보상 코드 LLM 호출에 재사용)
- 로그인 사용자 시드: `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` (db-seed 컨테이너 통해 활성화)
- nginx 게이트웨이 설정: `openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` (브라우저는 `:8088` 단일 진입점 사용)

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-get-rework-activities-ui.md` | `재작업 다이얼로그에서 후보 활동 목록을 확인한다` | 완료된 워크아이템에서 재작업 버튼을 눌러 reference/all 활동 목록을 확인 |
| 02 | `02-rework-complete-ui.md` | `재작업 다이얼로그에서 전체 활동 재작업을 시작한다` | 다이얼로그에서 "이후 모든 단계 재작업" 선택 후 제출, 인스턴스 화면으로 이동 및 IN_PROGRESS/TODO 전이 검증 |
| 03 | `03-workitem-not-found.md` | `존재하지 않는 인스턴스로 후보 조회시 400을 반환한다` | 백엔드 보호 검증: 존재하지 않는 `instanceId`로 `POST /get-rework-activities` 호출시 400 + "No workitem found" |
| 04 | `04-compensation-skip-no-events.md` | `되돌릴 작업 이력이 없으면 보상 코드 준비를 생략한다` | 이벤트 이력이 없는 활동에 대해 재작업 시 보상 코드 생성이 생략되고 `mcp_python_code`에 compensation row가 만들어지지 않음을 검증 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-activity-rework` | 재작업 가능 활동 조회 | SHALL | 01, 03 | UI + 오류 경로 |
| `completion_process-activity-rework` | 활동 재작업 시작 | SHALL | 02, 04 | UI 제출 + DB 전이 검증 |
| `completion_process-activity-rework` | 보상 코드 생성 | SHALL | 04 | 생략 경로 검증 (이벤트 없는 활동) |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-activity-rework` | 재작업 가능 활동 조회 | 재작업 후보 조회 성공 | 01 | 재작업 버튼 클릭 → 다이얼로그 라디오/칩 표시 |
| `completion_process-activity-rework` | 재작업 가능 활동 조회 | 워크아이템을 찾을 수 없음 | 03 | 백엔드 보호 (비-UI) — 게이트웨이 통한 HTTP 응답 |
| `completion_process-activity-rework` | 활동 재작업 시작 | 재작업 시작 성공 | 02 | 다이얼로그 라디오 선택 + 제출 버튼 → 인스턴스 화면 이동 |
| `completion_process-activity-rework` | 보상 코드 생성 | 되돌릴 작업이 있을 때 보상 코드 생성 | 보류 (별도 스위트 추가시 도입) | mock-llm + events 시드가 필요해 후속 보강으로 분리 |
| `completion_process-activity-rework` | 보상 코드 생성 | 되돌릴 작업이 없거나 보상 코드가 이미 있을 때 생략 | 02, 04 | 이벤트가 없는 시드 상태에서 재작업 진행 → `mcp_python_code.compensation` 미작성 검증 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_engine.py` | `handle_get_rework_activities` | 재작업 가능 활동 조회 | line/function >= 80% | `POST /get-rework-activities` 핸들러 본체 |
| `services/completion/process_engine.py` | `get_reference_workitems` | 재작업 가능 활동 조회 | line/function >= 70% | reference 목록 산출 |
| `services/completion/process_engine.py` | `get_all_next_workitems` | 재작업 가능 활동 조회 | line/function >= 70% | all 목록 산출 |
| `services/completion/process_engine.py` | `handle_rework_complete` | 활동 재작업 시작 | line/function >= 80% | `POST /rework-complete` 핸들러 본체 |
| `services/completion/process_engine.py` | `create_new_workitem` | 활동 재작업 시작 | line/function >= 80% | 새 워크아이템 dict 생성 (rework_count + 1) |
| `services/completion/compensation_handler.py` | `generate_compensation` | 보상 코드 생성 | line/function >= 60% | 보상 코드 준비/생략 분기 (생략 경로 검증) |
| `services/completion/database.py` | `fetch_workitem_by_proc_inst_and_activity` / `upsert_workitem` | 재작업 가능 활동 조회 / 활동 재작업 시작 | 보조 evidence | 핸들러가 직접 호출하는 영속화 계층 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/apps/todolist/ReworkDialog.vue` | `ReworkDialog`, `submitRework`, `loadActivities` | 재작업 가능 활동 조회 / 활동 재작업 시작 | 참고/line >= 60% | 사용자가 라디오 선택 후 제출하는 다이얼로그 |
| `services/frontend/src/components/apps/todolist/WorkItem.vue` | `handleReworkDialog`, `loadReworkActivities`, `submitRework` | 재작업 가능 활동 조회 / 활동 재작업 시작 | 참고/line >= 50% | 재작업 버튼 트리거 + API 호출 진입점 |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` | `getReworkActivities`, `reWorkItem` | 재작업 가능 활동 조회 / 활동 재작업 시작 | 참고 | `/completion/get-rework-activities`, `/completion/rework-complete` HTTP 호출 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| "되돌릴 작업이 있을 때 보상 코드 생성" 명세 시나리오 | events 테이블에 `tool_usage_finished` + `crew_type='action'` 이력을 시드해야 하고 `compensation_handler.generate_deterministic_compensation_code`가 LLM(mock) 응답을 받아야 함. 본 라운드에서는 LLM 시드 분기를 도입하지 않고 생략 경로만 검증함. | events 시드 + 보상 코드 전용 mock-llm 응답 추가 후 별도 시나리오(예: 05번)로 보강 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_process-activity-rework/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다 (시나리오 01, 02).
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
