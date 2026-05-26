# Code To Spec 계획: crewai-action 마이크로서비스

## 입력 범위
- 소스 폴더:
  - `services/crewai-action` (ProcessGPT Agent SDK 폴링 기반 CrewAI 액션 실행 서버 + 헬스 서버 + 동적 크루/프롬프트 구성)
- 제외 범위:
  - `services/crewai-action/test_executor.py`, `single_run_test.py`, `test_llm_factory.py`: 로컬 테스트/디버깅 전용 실행기이며 외부 클라이언트 계약이 아님. 스펙 대상에서 제외한다.
  - `services/crewai-action/smoke_test.py`: 테스트 스크립트이지만 헬스 계약의 evidence로만 사용한다(별도 스펙 생성 안 함).
  - Deterministic Code 생성/실행 경로(`_generate_deterministic`, `_run_deterministic`): 현재 실행 흐름에서 호출부가 주석 처리되어 비활성 상태이다. 도달 불가능 경로이므로 제품 스펙으로 다루지 않고 열린 질문으로만 기록한다.
  - `Dockerfile`, `pyproject.toml`, `requirements.txt`: 빌드/패키징 산출물로 외부 행위 계약이 아님.

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- Purpose, Requirement 제목, Requirement 본문, Scenario 제목, Scenario 단계는 한국어로 작성한다.
- `### Requirement:`와 `#### Scenario:` 접두어는 유지하되, 그 뒤의 이름은 한국어로 작성한다.
- 공개 엔드포인트 경로, HTTP method, 이벤트명/메타데이터 키, 상태 enum 값, 컨텍스트 필드명, 설정 키, 환경 변수명은 계약인 경우에만 원문을 유지한다.
- main spec은 마이크로서비스 전체가 아니라 하나의 피쳐 단위로 작성한다.
- `services/crewai-action` 입력이므로 모든 스펙 ID는 `crewai-action` 접두어로 시작한다. 이 서비스는 "CrewAI 기반 액션 실행"이라는 단일 업무 도메인에 집중되어 있고 서비스명이 이미 도메인을 충분히 드러내므로 도메인 구분자는 생략하고 `crewai-action_<feature>` 형식을 사용한다.
- 서비스 내부에서 발견한 외부 시스템/도구명(CrewAI, mem0, memento, MCP, DMN, LiteLLM 등)은 `crewai-action` 접두어를 대체하지 않는다.
- `frontend`, `ui`, `react`, `page`, `component`는 서비스 접두어 또는 도메인 구분자로 쓰지 않는다.

## 제안 스펙 분할

### `crewai-action_health-probe`
- Service prefix: `crewai-action` (`services/crewai-action` 마이크로서비스 폴더명)
- Domain discriminator: 없음 (서비스명이 도메인을 충분히 드러내는 단일 도메인 서비스)
- Naming 결정 근거: `services/crewai-action` 마이크로서비스 입력이므로 접두어를 `crewai-action`으로 고정하고, 단일 도메인이므로 도메인 구분자 없이 `_health-probe` 피쳐를 붙인다.
- Feature: `health-probe` (운영자/오케스트레이터용 헬스·라이브니스 점검)
- 목적: 운영자와 컨테이너 오케스트레이터가 서버의 생존/준비 상태를 HTTP로 점검하는 피쳐.
- E2E 단위 판단: 서버 기동 → `/health` 호출 → 정상 응답 확인, 알 수 없는 경로 호출 → 404 확인을 하나의 헬스 점검 suite로 검증할 수 있다(스모크 테스트와 1:1 대응).
- 백엔드/제품 계약 연결:
  - `GET /health`, `HEAD /health`: 응답 `200` + `{"status":"ok"}`, `Content-Type: application/json; charset=utf-8`
  - 그 외 경로: `404` + `{"status":"not_found"}`
  - 헬스 서버는 포트 `8000`에서 작업 폴링과 독립적으로 제공
- 포함 유즈 케이스:
  - 헬스 엔드포인트 정상 조회(`GET`/`HEAD`)
  - 정의되지 않은 경로 요청 시 404 응답
  - Kubernetes readiness/liveness 프로브 대상으로의 사용
- 주요 관측 계약:
  - 정상 응답 본문 `{"status":"ok"}`, 상태 코드 `200`
  - 미정의 경로 응답 본문 `{"status":"not_found"}`, 상태 코드 `404`
  - 헬스 서버는 백그라운드로 기동되어 작업 처리 중에도 응답 가능
- 다른 spec으로 분리할 범위:
  - `crewai-action_task-execution`: 실제 작업 처리 흐름은 별도
- 제외할 구현 세부:
  - HTTP 핸들러 클래스 구성, 스레드 기동 방식
- frontend evidence:
  - 없음(운영자/인프라 관점 계약)
- 근거 유형:
  - 헬스 라우트, README의 프로브 예시, 스모크 테스트 스크립트
- 위험 또는 열린 질문:
  - 없음

### `crewai-action_task-execution`
- Service prefix: `crewai-action`
- Domain discriminator: 없음
- Naming 결정 근거: `services/crewai-action` 입력, CrewAI 액션 실행 도메인의 핵심 작업 처리 피쳐.
- Feature: `task-execution` (작업 폴링·멀티 에이전트 크루 실행·결과 이벤트 전달)
- 목적: 시스템이 `crewai-action` 유형의 작업을 주기적으로 감지하여, 작업 컨텍스트로 멀티 에이전트 크루를 구성·실행하고, 진행 상태와 최종 결과를 이벤트로 전달하는 피쳐.
- E2E 단위 판단: `crewai-action` 작업 투입 → 폴링·크루 실행 → 진행/완료/아티팩트 이벤트 발행 확인을 하나의 작업 처리 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - ProcessGPT Agent SDK 폴링: `agent_type="crewai-action"`, 폴링 주기 5초
  - 작업 컨텍스트 입력: `row`(`id`, `root_proc_inst_id`/`proc_inst_id`, `tenant_id`), `extras`(`agents`, `users`, `form_fields`, `form_html`, `activity_name`, `summarized_feedback`, `tenant_mcp`, `sources`, `form_id`, `notify_user_emails`)
  - 결과 전달: `TaskStatusUpdateEvent`(`working`/`completed`), `TaskArtifactUpdateEvent`(아티팩트 `crewai_action_result`)
  - 이벤트 메타데이터: `crew_type`, `event_type`(`task_started`/`task_completed`), `job_id`
- 포함 유즈 케이스:
  - 신규 `crewai-action` 작업 폴링·수신 및 실행 컨텍스트 추출
  - 작업 컨텍스트 기반 멀티 에이전트 크루 구성 및 실행
  - 에이전트 정보 미제공 시 기본 에이전트로 실행
  - 최종 폼 결과의 working/completed 이벤트 쌍 및 아티팩트 이벤트 발행
  - 에이전트 출력의 견고한 해석 및 `폼_데이터` 정규화
  - 도구 로딩 실패 시에도 작업 계속(도구 없이 진행)
  - 작업 취소 요청 수용
- 주요 관측 계약:
  - `proc_inst_id`는 `root_proc_inst_id` 우선, 없으면 `proc_inst_id`로 해소
  - 최종 결과 이벤트는 `working`(`task_started`) + `completed`(`task_completed`) 쌍으로 발행되고 `contextId`/`taskId`를 포함
  - `폼_데이터`가 비어 있으면 결과 이벤트 쌍을 발행하지 않고 아티팩트만 발행
  - 코드펜스/백틱 값/다중 JSON 객체/`result` 래핑 등 비정상 형식의 출력도 가능한 범위에서 복구하여 폼 데이터로 정규화
  - 실행 종료 시 결과 성패와 무관하게 MCP 어댑터 자원 정리 시도
  - 복구 불가능한 오류는 SDK로 전파
- 다른 spec으로 분리할 범위:
  - `crewai-action_agent-tool-prioritization`: 도구·스킬 우선순위 정책은 별도
  - `crewai-action_report-slide-delivery`: 리포트/슬라이드 타입 필드의 분리 이벤트는 별도
  - `crewai-action_health-probe`: 헬스 점검은 별도
- 제외할 구현 세부:
  - 동적 프롬프트 생성 내부 구조, CrewAI 크루 객체 구성, LLM 클라이언트 조립
  - 비활성(주석 처리)된 Deterministic Code 경로
- frontend evidence:
  - 작업 진행 타임라인, 최종 결과 표시 화면(에이전트 진행 카드)
- 근거 유형:
  - 폴링 설정, 작업 컨텍스트 필드, 발행 이벤트 구조, README 실행 흐름
- 위험 또는 열린 질문:
  - `cancel` 요청은 수용되지만 실제 실행 중단 동작이 없음(취소 보장 수준이 계약인지 확인 필요)
  - Deterministic Code 사전 처리 경로가 주석 처리되어 비활성 상태(향후 계약 편입 여부 불명확)

### `crewai-action_agent-tool-prioritization`
- Service prefix: `crewai-action`
- Domain discriminator: 없음
- Naming 결정 근거: `services/crewai-action` 입력, 크루 구성 시 에이전트의 도구·스킬 우선순위를 제어하는 설정 피쳐.
- Feature: `agent-tool-prioritization` (에이전트 도구·스킬 사용 우선순위 정책)
- 목적: 설정자가 에이전트가 작업 계획·실행 시 도구와 스킬을 고려하는 우선순위를 제어하고, 미지정 시 일관된 기본 우선순위가 적용되도록 보장하는 피쳐.
- E2E 단위 판단: 우선순위 미지정 작업 → 기본 순서 확인, `tool_priority_order` 지정 작업 → 지정 순서 반영 확인을 하나의 설정 검증 suite로 다룰 수 있다.
- 백엔드/제품 계약 연결:
  - 에이전트 설정 키 `tool_priority_order`(별칭 `tool_priority`): 문자열 리스트, 앞일수록 높은 우선순위
  - 우선순위 항목: 스킬명, 스킬 MCP 서버명(`claude-skills`, `computer-use`), 도구명(`dmn_rule`, `mem0`, `memento` 등), 와일드카드 `*`
  - 우선순위 결과가 에이전트 도구 노출 순서와 생성 작업 지시문의 도구 우선순위 안내에 반영
- 포함 유즈 케이스:
  - `tool_priority_order`로 지정한 사용자 우선순위 적용
  - `*` 와일드카드로 미기재 도구의 묶음 위치 지정(생략 시 맨 뒤)
  - 스킬 보유 시 스킬 MCP 도구를 최우선으로 두는 기본 우선순위 적용
  - 스킬 미보유 시 기본 우선순위(`dmn_rule`, `mem0`, 기타) 적용
- 주요 관측 계약:
  - 사용자 지정 우선순위가 있으면 그 순서가 기본값보다 우선
  - 동일 우선순위 항목 간에는 원래 노출 순서가 보존(안정 정렬)
  - 기본 우선순위(스킬 있음): `claude-skills`, `computer-use`, `dmn_rule`, `mem0`, 기타
  - 기본 우선순위(스킬 없음): `dmn_rule`, `mem0`, 기타
  - 매니저 에이전트 우선순위는 호출 인자 > 첫 에이전트 설정 > 기본값 순으로 해소
- 다른 spec으로 분리할 범위:
  - `crewai-action_task-execution`: 크루 실행과 이벤트 전달은 별도
- 제외할 구현 세부:
  - 정렬 키 계산, idx_map 구성, MCP 서버 태깅 방식
- frontend evidence:
  - 에이전트 설정 화면의 도구/스킬 우선순위 지정 UI
- 근거 유형:
  - 에이전트 설정 키, 기본 우선순위 정책 주석, 생성 작업 지시문의 우선순위 안내 문구
- 위험 또는 열린 질문:
  - 스킬명별 개별 우선순위는 아직 MCP 단위로만 구분되며 스킬 간 세부 우선순위는 미지원

### `crewai-action_report-slide-delivery`
- Service prefix: `crewai-action`
- Domain discriminator: 없음
- Naming 결정 근거: `services/crewai-action` 입력, 리포트/슬라이드 타입 산출물을 별도 이벤트로 전달하는 피쳐.
- Feature: `report-slide-delivery` (리포트·슬라이드 타입 필드의 분리 이벤트 전달)
- 목적: 작업의 폼 정의에 리포트(문서) 또는 슬라이드(프레젠테이션) 타입 필드가 포함될 때, 해당 산출물을 일반 폼 데이터와 분리하여 전용 이벤트로 전달하는 피쳐.
- E2E 단위 판단: 리포트 타입 필드 포함 작업 → 리포트 이벤트 확인, 슬라이드 타입 필드 포함 작업 → 슬라이드 이벤트 확인을 하나의 산출물 전달 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - 폼 필드 타입 `report`/`document`(리포트), `slide`/`presentation`(슬라이드)
  - 리포트 필드: `TaskStatusUpdateEvent` working/completed 쌍, 메타데이터 `crew_type: report`
  - 슬라이드 필드: `TaskStatusUpdateEvent` working/completed 쌍, 메타데이터 `crew_type: slide`
  - 완료 이벤트 본문은 `{필드키: 마크다운 값}` 형식
- 포함 유즈 케이스:
  - 리포트 타입 필드의 분리 이벤트 발행
  - 슬라이드 타입 필드의 분리 이벤트 발행
  - 리포트/슬라이드 필드를 일반 `폼_데이터`와 결과 이벤트에서 제외
- 주요 관측 계약:
  - 리포트/슬라이드 필드는 일반 폼 결과 이벤트의 `폼_데이터`에 포함되지 않음
  - 값이 비어 있는 리포트/슬라이드 필드는 이벤트를 발행하지 않음
  - 각 필드는 `crew_type`이 `report` 또는 `slide`인 working(`task_started`) + completed(`task_completed`) 이벤트 쌍으로 발행
  - 완료 이벤트 본문은 해당 폼 필드의 `key`를 키로 사용
- 다른 spec으로 분리할 범위:
  - `crewai-action_task-execution`: 일반 폼 결과 이벤트와 전체 실행 흐름은 별도
- 제외할 구현 세부:
  - 출력 JSON 파싱·필드 분리 알고리즘, 프롬프트 생성 내부 구조
- frontend evidence:
  - 리포트 문서 미리보기, 슬라이드 프레젠테이션 표시 화면
- 근거 유형:
  - 폼 필드 타입 분류, 발행 이벤트 메타데이터, expected_output 프롬프트의 리포트/슬라이드 처리 지침
- 위험 또는 열린 질문:
  - 리포트 필드 `job_id`는 `final_report_merge_<키>` 형식으로 고정되고 슬라이드 필드는 무작위 식별자를 사용하여 식별자 규칙이 비대칭(계약 의도 확인 필요)

## 추적표

| 소스 범위 | 관측된 외부 행위 | 백엔드/제품 계약 | Service prefix | Domain discriminator | Feature | 제안 스펙 폴더 | E2E 단위 | 처리 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 헬스 서버 (`/health`) | 생존/준비 상태 점검 | `GET`/`HEAD /health` + JSON 응답 | `crewai-action` | 없음 | `health-probe` | `crewai-action_health-probe` | 적절 | 포함 |
| 폴링 서버 + 액션 실행기 | 작업 폴링·크루 실행·결과 이벤트 전달 | SDK 폴링 + `TaskStatusUpdateEvent`/`TaskArtifactUpdateEvent` | `crewai-action` | 없음 | `task-execution` | `crewai-action_task-execution` | 적절 | 포함 |
| 크루 팩토리 (도구 우선순위) | 도구·스킬 우선순위 제어 | `tool_priority_order` 설정 + 기본 우선순위 정책 | `crewai-action` | 없음 | `agent-tool-prioritization` | `crewai-action_agent-tool-prioritization` | 적절 | 포함 |
| 액션 실행기 (리포트/슬라이드 분기) + 결과 변환 | 리포트/슬라이드 산출물 분리 전달 | `crew_type: report`/`slide` 이벤트 | `crewai-action` | 없음 | `report-slide-delivery` | `crewai-action_report-slide-delivery` | 적절 | 포함 |
| `test_executor.py`, `single_run_test.py`, `test_llm_factory.py` | 로컬 테스트/디버깅 실행기 | - | - | - | - | - | - | 제외 |
| `smoke_test.py` | 헬스 점검 스크립트 | - | - | - | - | - | - | 제외(evidence로만 사용) |
| Deterministic Code 경로 | 비활성(주석 처리)된 사전 처리 | - | - | - | - | - | - | 제외(열린 질문) |

## 진행 체크리스트
- [x] 모든 입력 폴더가 확인되었다.
- [x] 각 스펙 폴더가 `<microservice>_<feature>` 형식을 따른다.
- [x] 마이크로서비스/서비스 폴더 입력에서 생성된 모든 스펙 ID가 `crewai-action` 폴더명으로 시작한다.
- [x] 단일 도메인 서비스이므로 도메인 구분자를 중복하지 않고 `crewai-action_` 접두어를 유지했다.
- [x] 서비스 접두어가 백엔드/제품 기능 경계이며 `frontend`,`ui`,`react`,`page`,`component`가 아니다.
- [x] 스펙 폴더가 구현 구조가 아니라 피쳐 기준으로 나뉘었다.
- [x] 프론트엔드 입력은 evidence로만 사용했고 프론트엔드 단독 스펙은 생성하지 않았다.
- [x] 어떤 스펙도 마이크로서비스 전체, route inventory, controller/service/repository 계층을 요약하지 않는다.
- [x] 각 스펙 폴더의 유즈 케이스가 하나의 E2E suite로 자연스럽게 검증 가능한 범위다.
- [x] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [x] `openspec/specs` 작성 전에 이 계획이 저장되었다.
