# Code To Spec 계획: agent-feedback 마이크로서비스

## 입력 범위
- 소스 폴더:
  - `services/agent-feedback` (FastAPI 기반 멀티테넌트 에이전트 피드백/지식 처리 서비스, 기본 포트 `6789`)
- 제외 범위:
  - `services/agent-feedback/tests/`: 개발용 테스트 스크립트. 외부 클라이언트 계약이 아니므로 제외한다.
  - `services/agent-feedback/scripts/`: 빌드/배포 스크립트(`deploy.ps1`, `deploy.sh`). 운영자용 배포 도구이며 제품 계약이 아니므로 제외한다.
  - `services/agent-feedback/k8s/`: Kubernetes 배포 매니페스트. 제품 행위 계약이 아니므로 제외한다.
  - `services/agent-feedback/utils/`(`logger.py`, `translator.py`): 로깅/번역 내부 유틸리티이며 사용자/클라이언트가 직접 호출하지 않으므로 제외한다.
  - `services/agent-feedback/tools/knowledge_manager.py`: 내부 지식 관리 헬퍼이며 공개 계약이 아니므로 제외한다. 관찰 가능한 결과는 관련 피쳐 스펙에 반영한다.

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- Purpose, Requirement 제목, Requirement 본문, Scenario 제목, Scenario 단계는 한국어로 작성한다.
- `### Requirement:`와 `#### Scenario:` 접두어는 유지하되, 그 뒤의 이름은 한국어로 작성한다.
- 공개 API 경로, HTTP method, 요청/응답 필드명, 이벤트명, 설정 키, enum 값, SQL 키워드, 테이블/함수명은 계약인 경우에만 원문을 유지한다.
- main spec은 마이크로서비스 전체가 아니라 하나의 피쳐 단위로 작성한다.
- `services/agent-feedback` 입력이므로 모든 스펙 ID는 `agent-feedback_` 접두어로 시작한다.
- 이 서비스는 "에이전트 피드백 기반 지식 관리"라는 단일 업무 도메인에 집중되어 있고 서비스명이 이미 도메인을 드러내므로 도메인 구분자는 생략하되, 서비스 접두어 경계를 유지하기 위해 `<microservice>_<feature>` 형식을 사용한다.
- 서비스 내부에서 발견한 외부 시스템명(mem0, Supabase, MCP, claude-skills, computer-use, LiteLLM 등)이나 프로토콜명은 `agent-feedback` 접두어를 대체하지 않는다.
- `frontend`, `ui`, `react`, `page`, `component`는 서비스 접두어 또는 도메인 구분자로 쓰지 않는다.

## 제안 스펙 분할

### `agent-feedback_feedback-processing`
- Service prefix: `agent-feedback` (`services/agent-feedback` 마이크로서비스 폴더명)
- Domain discriminator: 없음 (서비스가 단일 도메인이므로 도메인 구분자 생략, 서비스 접두어 뒤 `_`는 유지)
- Naming 결정 근거: `services/agent-feedback` 마이크로서비스 입력이므로 접두어를 `agent-feedback`로 고정하고, 완료된 워크아이템의 사용자 피드백을 폴링·처리하는 피쳐를 `feedback-processing`으로 둔다.
- Feature: `feedback-processing` (완료된 워크아이템에 누적된 사용자 피드백을 자동 폴링하여 에이전트 학습으로 반영)
- 목적: 사용자가 워크아이템에 남긴 피드백을 시스템이 주기적으로 자동 감지하여, 관련 에이전트별 학습 후보로 변환하고 분석·반영한 뒤 처리 상태를 갱신하는 피쳐.
- E2E 단위 판단: 워크아이템에 피드백 등록 → 폴링 픽업 → 에이전트 매칭 → 처리 → `feedback_status`가 `COMPLETED`/`FAILED`로 갱신을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - 폴링 잡: 약 7초 간격으로 `agent_feedback_task` 함수를 호출해 피드백이 있고 `proc_def_id`가 있으며 `feedback_status`가 비었거나 `REQUESTED`인 워크아이템을 한 건씩 선점(`feedback_status='STARTED'`)
  - 상태 전이: 처리 시작 시 `PROCESSING`, 정상 종료 시 `COMPLETED`, 에이전트 미발견·처리 실패·미커밋 시 `FAILED`
  - 입력 데이터: 워크아이템의 `feedback`(시간순 배열 또는 문자열), `description`(작업 지시사항), `user_id`/`assignees`(대상 에이전트), `events` 테이블의 스킬/도구 사용 이벤트 로그
  - AI 매칭: 시간순 다중 피드백을 최신 우선으로 통합한 에이전트별 학습 후보(`agent_feedbacks[].learning_candidate.content`, `intent_hint`) 생성
- 포함 유즈 케이스:
  - 다중·시간순 피드백을 최신 피드백 우선으로 통합한 단일 학습 가이드 생성
  - `user_id`로 에이전트를 찾지 못하면 `assignees`의 `endpoint`에서 에이전트 탐색
  - 단순 재시도 요청("다시 시도", "재시도", "try again")은 학습 없이 종료
  - 매칭된 학습 후보가 없으면 정상 종료(`COMPLETED`)
  - 에이전트별 처리 중 일부 실패가 있어도 폴링은 중단 없이 계속 진행
- 주요 관측 계약:
  - 한 폴링 주기에 피드백 작업 1건과 초기 지식 셋팅 대상 1건을 각각 처리
  - 대상 에이전트를 찾지 못하면 `FAILED`로 종료
  - 에이전트 처리 중 오류 또는 미커밋이 있으면 작업 전체를 `FAILED`로 기록
  - 처리 결과는 변경 이력으로 보존됨(상세는 `agent-feedback_knowledge-commit`)
- 다른 spec으로 분리할 범위:
  - `agent-feedback_knowledge-setup`: 목표/페르소나 기반 초기 지식 셋팅
  - `agent-feedback_knowledge-commit`: 지식 저장·병합·이력 계약
  - `agent-feedback_skill-authoring`: SKILL 생성·재사용
- 제외할 구현 세부:
  - ReAct 프롬프트 문자열, LangChain 에이전트 구성, 폴링 루프 예외 처리 구조
- frontend evidence:
  - 워크아이템 피드백 입력란, 피드백 처리 상태 배지
- 근거 유형:
  - `agent_feedback_task`/`events` 조회 함수, `todolist.feedback_status` 영속화, 폴링 매니저, AI 매칭 응답 형식
- 위험 또는 열린 질문:
  - `agent_feedback_task` 함수는 `feedback_status`가 NULL/`REQUESTED`인 행을 선점하지만 코드 주석/문서는 `DONE` 상태를 언급하여, 트리거 조건의 정식 계약이 무엇인지 불명확

### `agent-feedback_knowledge-setup`
- Service prefix: `agent-feedback`
- Domain discriminator: 없음
- Naming 결정 근거: `services/agent-feedback` 입력, 에이전트의 목표·페르소나로부터 초기 지식을 생성하는 피쳐.
- Feature: `knowledge-setup` (에이전트 목표/페르소나 분석 기반 초기 지식 자동 생성)
- 목적: 클라이언트가 에이전트를 지정하면 시스템이 그 에이전트의 목표(goal)와 페르소나(persona)를 분석해 규칙(DMN_RULE)·절차(SKILL)·선호도(MEMORY) 초기 지식을 생성하고, 셋팅 상태를 추적하는 피쳐.
- E2E 단위 판단: `POST /setup-agent-knowledge` 호출 → 초기 지식 생성 → 응답(`did_commit`, `commit_successes`) 확인 → `agent_knowledge_setup_log`가 `DONE`을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /setup-agent-knowledge`: 요청 `{agent_id, goal?, persona?}`, 응답 `{output, intermediate_steps, agent_id, used_tools, did_commit, commit_successes}`
  - 폴링 잡: `agent_needing_knowledge_setup` 함수로 `goal`이 있고 셋팅 로그가 없는 에이전트를 한 건씩 자동 셋팅
  - 영속화: `agent_knowledge_setup_log`(`agent_id` PK, `status` `STARTED`/`DONE`/`FAILED`)
- 포함 유즈 케이스:
  - 요청에 `goal`/`persona`가 없으면 에이전트 정보에서 보완
  - API 요청과 폴링 양쪽 경로에서 동일한 초기 지식 셋팅 수행
  - 셋팅 시작 시 `STARTED`, 성공 시 `DONE`, 실패 시 `FAILED`로 로그 갱신
  - 이미 셋팅 로그가 있는 에이전트는 폴링 대상에서 제외(에이전트당 1회)
- 주요 관측 계약:
  - 존재하지 않는 `agent_id`는 `404`
  - `goal`을 끝내 확보하지 못하면 `400`
  - 처리 중 오류 또는 미커밋(no_commit/commit_failed)이면 `500`과 함께 로그가 `FAILED`
  - 셋팅 결과는 변경 이력으로 보존됨(상세는 `agent-feedback_knowledge-commit`)
- 다른 spec으로 분리할 범위:
  - `agent-feedback_feedback-processing`: 사용자 피드백 폴링 처리
  - `agent-feedback_knowledge-commit`: 생성된 지식의 저장·이력 계약
  - `agent-feedback_skill-authoring`: SKILL 생성·재사용
- 제외할 구현 세부:
  - 목표/페르소나 분석 프롬프트 STEP 구조, 도메인별 지식 템플릿 문자열
- frontend evidence:
  - 에이전트 등록/설정 화면, 초기 지식 셋팅 진행 표시
- 근거 유형:
  - routes, README API 예시, `agent_needing_knowledge_setup` 함수, `agent_knowledge_setup_log` 영속화
- 위험 또는 열린 질문:
  - 없음

### `agent-feedback_knowledge-commit`
- Service prefix: `agent-feedback`
- Domain discriminator: 없음
- Naming 결정 근거: `services/agent-feedback` 입력, 분석된 지식을 MEMORY/DMN_RULE 저장소에 저장하면서 기존 지식을 보존·병합하고 변경 이력을 남기는 피쳐.
- Feature: `knowledge-commit` (관계 분석 기반 지식 저장·병합·버전·변경 이력)
- 목적: 시스템이 새 지식을 적절한 저장소로 분류하고, 기존 지식과의 관계에 따라 안전하게 병합(보존/확장/대체)하며, 모든 변경을 감사 가능한 이력으로 기록하는 피쳐.
- E2E 단위 판단: 기존 규칙이 있는 상태에서 `EXTENDS` 관계의 피드백을 처리 → 기존 규칙 보존 + 새 규칙 추가 + 새 버전 + 변경 이력 기록을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - MEMORY 저장: mem0 벡터 저장소에 `CREATE`/`UPDATE`/`DELETE`, 메타데이터 부여
  - DMN_RULE 저장: `proc_def` 테이블(`type='dmn'`, `owner=agent_id`)에 규칙 XML 저장, `proc_def_version`에 버전 스냅샷·diff 기록
  - 변경 이력: `agent_knowledge_history`(`knowledge_type`, `operation`, `previous_content`, `new_content`, `feedback_content`)
  - 지식 레지스트리: `agent_knowledge_registry`(upsert, `content_hash`, `last_accessed_at`)
- 포함 유즈 케이스:
  - 새 지식을 MEMORY(지침/선호도)·DMN_RULE(조건-결과 규칙)로 분류
  - 관계 유형(DUPLICATE/EXTENDS/REFINES/EXCEPTION/CONFLICTS/SUPERSEDES/COMPLEMENTS/UNRELATED)에 따른 처리 결정
  - `merge_mode`(`REPLACE`/`EXTEND`/`REFINE`)에 따른 병합: `EXTEND`는 기존 DMN 규칙을 보존하고 새 규칙 추가
  - DMN 규칙 수정 시 시맨틱 버전 증가(`REPLACE`→major, `EXTEND`→minor, `REFINE`→patch)와 버전 스냅샷 보존
  - 저장/수정/삭제 시 변경 전후 내용과 원본 피드백을 변경 이력으로 기록
- 주요 관측 계약:
  - `UPDATE`/`DELETE`에는 기존 식별자(`memory_id`/`rule_id`) 필수
  - 식별자가 있으면 `CREATE`로 들어와도 실제로는 `UPDATE`로 처리(기존 지식 보호)
  - 변경 이력 기록에 실패하면 해당 저장 작업 전체를 실패로 간주
  - 에이전트가 저장/수정/삭제 결론을 냈으나 실제 저장 도구를 호출하지 않으면 처리 실패(no_commit), 저장 도구가 오류를 반환하면 처리 실패(commit_failed)
  - DMN 규칙은 `owner=agent_id` 범위에서만 수정·삭제 가능
- 다른 spec으로 분리할 범위:
  - `agent-feedback_skill-authoring`: SKILL 저장소의 생성·재사용·검증은 별도 피쳐
  - `agent-feedback_feedback-processing` / `agent-feedback_knowledge-setup`: 저장을 유발하는 진입 경로
- 제외할 구현 세부:
  - DMN XML 생성/확장 LLM 프롬프트, XML 구조 보정 로직, 버전 번호 파싱 알고리즘
- frontend evidence:
  - 에이전트 지식 목록/상세 화면, 규칙 버전 비교, 변경 이력 타임라인
- 근거 유형:
  - `proc_def`/`proc_def_version`/`agent_knowledge_history`/`agent_knowledge_registry` 영속화, 저장 도구 동작, 변경 이력 함수
- 위험 또는 열린 질문:
  - `REFINE` 모드는 현재 `REPLACE`와 동일하게 동작하므로, 세밀한 수정이 별도 계약으로 보장되는지 불명확
  - SKILL 타입의 변경 이력도 동일한 `agent_knowledge_history` 계약을 따르며, SKILL 작성 동작 자체는 `agent-feedback_skill-authoring`에서 다룬다

### `agent-feedback_skill-authoring`
- Service prefix: `agent-feedback`
- Domain discriminator: 없음
- Naming 결정 근거: `services/agent-feedback` 입력, 절차형 지식(SKILL)을 재사용하거나 새로 생성·수정하는 피쳐.
- Feature: `skill-authoring` (기존 스킬 재사용 적재와 신규 스킬 생성·수정·삭제)
- 목적: 시스템이 절차형 지식이 필요할 때 기존 스킬을 우선 재사용하여 에이전트에 적재하거나, 필요한 경우에만 새 스킬을 생성·수정·삭제하고 에이전트/테넌트 스킬 목록을 동기화하는 피쳐.
- E2E 단위 판단: 절차 요구가 담긴 피드백 처리 → 기존 스킬 적재 또는 신규 스킬 생성 → 스킬 목록 동기화 + 변경 이력 기록을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - 기존 스킬 재사용: 쉼표 구분 스킬 식별자를 받아 에이전트에 적재(스킬 내용 생성/수정 없음)
  - 신규/수정: `CREATE`/`UPDATE`/`DELETE` 스킬 작업, 스킬 저장소는 HTTP API + MCP 서버(claude-skills)
  - 스킬 내용 생성 워크플로우: `USE_SKILL_CREATOR_WORKFLOW`와 `COMPUTER_USE_MCP_URL`이 모두 설정되면 skill-creator 경로로 스킬 문서·부가 파일 생성·검증·패키징
  - 동기화: `users.skills`(콤마 문자열), `tenants.skills`(배열), `agent_skills` 테이블
- 포함 유즈 케이스:
  - 유사도가 높고 기존 스킬이 요구 절차를 커버하면 새 스킬 생성 대신 기존 스킬을 적재
  - 단일/다중 스킬 적재(쉼표 구분 식별자)
  - 기존 스킬로 커버 불가일 때만 신규 스킬 생성, 동일 범위·절차 수정 시에만 기존 스킬 수정
  - skill-creator 경로에서 스킬 문서·부가 파일 생성, 형식 검증, 패키징 후 저장소 반영
  - 스킬 생성/삭제 시 에이전트·테넌트 스킬 목록 동기화
- 주요 관측 계약:
  - 생성하려는 스킬 이름이 이미 존재하면 생성 실패(수정은 명시적 `UPDATE` 필요)
  - `UPDATE`/`DELETE`에는 기존 스킬 식별자 필수
  - skill-creator 경로 사용 여부는 설정 키(`USE_SKILL_CREATOR_WORKFLOW`, `COMPUTER_USE_MCP_URL`)로 결정, 미설정 시 기본 HTTP 경로 사용
  - `DELETE`는 항상 기본 HTTP 경로로 처리
  - 스킬 문서는 `name`/`description` frontmatter 등 형식 규칙을 만족해야 하며 검증 실패 시 저장하지 않음
  - 스킬 변경도 변경 이력으로 기록됨(이력 계약은 `agent-feedback_knowledge-commit`)
- 다른 spec으로 분리할 범위:
  - `agent-feedback_knowledge-commit`: MEMORY/DMN_RULE 저장·병합과 공통 변경 이력 계약
  - `agent-feedback_feedback-processing` / `agent-feedback_knowledge-setup`: 스킬 작성을 유발하는 진입 경로
- 제외할 구현 세부:
  - computer-use Pod 세션 명령 시퀀스, base64 디코딩, skill-creator 프롬프트 문자열, MCP 도구 이름 변형 로직
- frontend evidence:
  - 에이전트 스킬 목록 화면, 스킬 추가/적재 표시
- 근거 유형:
  - 스킬 저장 도구, `docs/SKILL_CREATOR_WORKFLOW.md`, `users.skills`/`tenants.skills`/`agent_skills` 영속화, 설정 키
- 위험 또는 열린 질문:
  - skill-creator 경로 실패 시 HTTP 폴백 없이 예외를 전파하는 동작이 의도된 계약인지 명시 필요

## 추적표

| 소스 범위 | 관측된 외부 행위 | 백엔드/제품 계약 | Service prefix | Domain discriminator | Feature | 제안 스펙 폴더 | E2E 단위 | 처리 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 피드백 폴링 잡, `agent_feedback_task`, `events`, `todolist.feedback_status` | 완료 워크아이템 피드백 자동 폴링·매칭·처리·상태 갱신 | 폴링 잡, 피드백 상태 함수, AI 매칭 | `agent-feedback` | 없음 | `feedback-processing` | `agent-feedback_feedback-processing` | 적절 | 포함 |
| `POST /setup-agent-knowledge`, `agent_needing_knowledge_setup`, `agent_knowledge_setup_log` | 목표/페르소나 기반 초기 지식 셋팅 | 셋팅 API, 셋팅 폴링 잡, 셋팅 로그 | `agent-feedback` | 없음 | `knowledge-setup` | `agent-feedback_knowledge-setup` | 적절 | 포함 |
| MEMORY/DMN_RULE 저장, `proc_def`/`proc_def_version`, `agent_knowledge_history`, `agent_knowledge_registry` | 관계 기반 지식 분류·병합·버전·변경 이력 | 저장 도구, 변경 이력/레지스트리, DMN 버전 | `agent-feedback` | 없음 | `knowledge-commit` | `agent-feedback_knowledge-commit` | 적절 | 포함 |
| SKILL 저장/재사용 도구, skill-creator 워크플로우, `users.skills`/`tenants.skills`/`agent_skills` | 기존 스킬 재사용 적재와 신규 스킬 생성·수정·삭제 | 스킬 저장 도구, skill-creator 경로, 스킬 동기화 | `agent-feedback` | 없음 | `skill-authoring` | `agent-feedback_skill-authoring` | 적절 | 포함 |
| `tests/`, `scripts/`, `k8s/`, `utils/`, `tools/` | 테스트·배포·내부 유틸리티 | 없음 | - | - | - | - | - | 제외(공개 계약 아님) |

## 진행 체크리스트
- [x] 모든 입력 폴더가 확인되었다.
- [x] 각 스펙 폴더가 `<microservice>_<domain>-<feature>` 또는 `<microservice>_<feature>` 형식을 따른다.
- [x] 마이크로서비스/서비스 폴더 입력에서 생성된 모든 스펙 ID가 해당 서비스 폴더명(`agent-feedback`)과 `_`로 시작한다.
- [x] 단일 도메인 서비스이므로 도메인 구분자를 중복 추가하지 않았고, 서비스 접두어 뒤 `_`는 유지했다.
- [x] 서비스 접두어가 백엔드/제품 기능 경계이며 `frontend`, `ui`, `react`, `page`, `component`가 아니다.
- [x] 스펙 폴더가 구현 구조가 아니라 피쳐 기준으로 나뉘었다.
- [x] 프론트엔드 입력은 없으며, 프론트엔드 단독 스펙을 생성하지 않았다.
- [x] 어떤 스펙도 마이크로서비스 전체, route inventory, controller/service/repository 계층을 요약하지 않는다.
- [x] 각 스펙 폴더의 유즈 케이스가 하나의 E2E suite로 자연스럽게 검증 가능한 범위다.
- [x] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [x] `openspec/specs` 작성 전에 이 계획이 저장되었다.
