# 프로세스 정의 피드백 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-definition-feedback`
- 원본 명세 ID: `completion_process-definition-feedback`
- 원본 명세:
  - `openspec/specs/completion_process-definition-feedback/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI 라우트: `POST /get-feedback`, `POST /get-feedback-diff`
  - 영속 계층: Supabase Postgres (`public.todolist`, `public.proc_def`, `public.proc_def_version`, `public.bpm_proc_inst`)
  - LLM 외부 경계: OpenAI 호환 프록시 (E2E에서는 공유 `mock-llm` 컨테이너의 feedback/diff 패턴으로 결정성 확보)
- E2E 루트: `openspec/specs/completion_process-definition-feedback/e2e/`
- Playwright 명세: `openspec/specs/completion_process-definition-feedback/e2e/tests/completion_process-definition-feedback.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-definition-feedback/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-feedback-fetch.md` | `활동 정의 피드백을 요청하면 피드백 목록을 반환한다` | 보조 프로토콜: 게이트웨이 → `/completion/get-feedback` → mock-llm |
| 02 | `02-feedback-diff.md` | `작업 피드백 차이 조회 시 modifications와 summary를 반환한다` | 보조 프로토콜: 게이트웨이 → `/completion/get-feedback-diff` → mock-llm |
| 03 | `03-missing-workitem.md` | `존재하지 않는 작업으로 차이 조회 시 400 No workitem found 를 반환한다` | 보조 프로토콜: 잘못된 taskId 로 400 검증 |

> 본 스펙의 두 라우트는 백엔드 API 계약입니다. 라우트의 단일 프론트엔드 소비자는 `services/frontend/src/components/ui/ProcessFeedback.vue` 이지만, ProcessFeedback 위젯 자체의 사용자 워크플로우(프로세스 인스턴스 채팅 → thumb-down → 위젯 렌더 → 매직 아이콘 → 피드백 적용)는 `ProcessInstanceChat` / `ProcessInstanceTable` 페이지의 메시지/워크아이템 상태 의존성이 크기 때문에 별도 UI 스펙에서 다룹니다. 따라서 본 E2E는 게이트웨이를 경유한 백엔드 프로토콜 검증으로 한정하며, 스크린샷 매뉴얼 증거는 요구되지 않습니다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-feedback` | 활동 정의 피드백 제공 | SHALL | 01 | `/get-feedback` 성공 응답 검증 |
| `completion_process-definition-feedback` | 작업 정의 버전 변경 비교 | SHALL | 02, 03 | 성공 응답 + 워크아이템 미존재 400 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-definition-feedback` | 활동 정의 피드백 제공 | 활동 피드백 조회 성공 | 01 | 보조 프로토콜 (UI 표면은 별도 스펙) |
| `completion_process-definition-feedback` | 작업 정의 버전 변경 비교 | 변경 비교 조회 성공 | 02 | 보조 프로토콜 |
| `completion_process-definition-feedback` | 작업 정의 버전 변경 비교 | 워크아이템 또는 활동을 찾을 수 없음 | 03 | 보조 프로토콜 (400 오류 분기) |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_engine.py` | `handle_get_feedback` (`POST /get-feedback`) | 활동 정의 피드백 제공 | line/function >= 80% | 단일 진입 라우트 |
| `services/completion/process_engine.py` | `handle_get_feedback_diff` (`POST /get-feedback-diff`) | 작업 정의 버전 변경 비교 | line/function >= 80% | 단일 진입 라우트 + 두 가지 400 분기 |
| `services/completion/database.py` | `fetch_workitem_by_id` | 두 요구사항 모두 | function 호출 검증 | 워크아이템 조회 핵심 |
| `services/completion/database.py` | `fetch_process_definition_by_version` | 두 요구사항 모두 | function 호출 검증 | 버전 별 정의 조회 |
| `services/completion/database.py` | `fetch_process_instance` | 두 요구사항 모두 | function 호출 검증 | `arcv_id` 도출 경로 |
| `services/completion/process_definition.py` | `load_process_definition`, `find_activity_by_id`, `find_next_item`, `find_sequences` | 작업 정의 버전 변경 비교 | function 호출 검증 | diff 입력 구성 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/api/ProcessGPTBackend.ts` | `getFeedback`, `getFeedbackDiff` | 두 요구사항 모두 | 참고 (보조 V8) | `/completion/get-feedback*` 단일 호출 지점 (본 스펙에서는 백엔드 프로토콜만 검증) |

> 본 스위트의 Playwright 시나리오는 모두 백엔드 프로토콜 계약 검증이므로 프론트엔드 소스맵 기반 커버리지는 1차 게이트가 아닙니다. 게이트웨이 라우팅의 정상성은 Sanity Check 에서 확인합니다.

## 재사용 산출물
- `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py` — OpenAI 호환 mock 에 본 스위트의 feedback/diff 프롬프트 패턴을 추가하여 공유 사용.
- `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` — `localhost` 테넌트와 로그인 사용자(`e2e@uengine.org`)는 기존 시드를 그대로 활용.
- `openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` — `/completion/` → `completion:8000` 프록시 경로 공유.

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| ProcessFeedback.vue UI 워크플로우 | 위젯 렌더 조건이 ProcessInstanceChat/Table 의 메시지·워크아이템 상태에 의존하여 본 스펙 범위를 초과 | UI 통합은 process-instance-chat 계열 스펙에서 별도 다룸 |
| `No activity found` 분기 | 한 워크아이템의 activity_id 가 proc_def 에 존재하지 않는 의도적 비정합 상태가 필요 | 추후 시드 변형으로 시나리오 04 추가 가능 |
| `handle_get_feedback_diff` 가 `HTTPException(400)` 을 500 으로 재포장 | 핸들러의 `except Exception` 분기가 `HTTPException` 을 먼저 처리하지 않아 명세상 400 이 500 으로 응답됨 | `handle_submit` 패턴(`except HTTPException: raise`) 적용 또는 명세 갱신 — 본 스위트는 실제 동작을 검증 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_process-definition-feedback/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다. (해당 없음 — 본 스위트는 백엔드 프로토콜 계약 검증)
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다. (해당 없음 — 보조 프로토콜 스위트)
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
