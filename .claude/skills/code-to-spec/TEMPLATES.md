# Code To Spec Templates

Use these templates when running the `code-to-spec` workflow. Write generated content in Korean unless the user explicitly requests another language. In OpenSpec specs, keep the structural prefixes `### Requirement:` and `#### Scenario:` but write the names after those prefixes, requirement prose, and scenario steps in Korean. Preserve only exact contract identifiers such as API paths, HTTP methods, fields, events, enum values, SQL keywords, paths, and IDs.

## Planning Template

Create this before writing any main specs:

```markdown
# Code To Spec 계획: <scope title>

## 입력 범위
- 소스 폴더:
  - `<folder>`
- 제외 범위:
  - `<folder or behavior>`: <reason>

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- Purpose, Requirement 제목, Requirement 본문, Scenario 제목, Scenario 단계는 한국어로 작성한다.
- `### Requirement:`와 `#### Scenario:` 접두어는 유지하되, 그 뒤의 이름은 한국어로 작성한다.
- 공개 API 경로, 요청/응답 필드명, 이벤트명, 설정 키는 계약인 경우에만 원문을 유지한다.
- main spec은 마이크로서비스 전체가 아니라 하나의 피쳐 단위로 작성한다.
- 스펙 폴더는 `<microservice>_<domain>-<feature>` 또는 `<microservice>_<feature>` 형식을 사용한다. 각 segment는 lowercase kebab-case이며, 예시는 `completion_agent-memory-chat`, `billing_invoice-search`이다.
- 마이크로서비스/서비스 폴더를 분석하는 경우 스펙 ID는 해당 서비스 폴더명으로 시작해야 한다. 예를 들어 `services/completion`에서 생성한 스펙은 항상 `completion`으로 시작한다.
- 서비스가 여러 업무 도메인에 걸치면 `<microservice>_<domain>-<feature>`로 도메인 구분자를 추가하고, 하나의 업무 도메인에 집중되어 있거나 서비스명이 도메인을 충분히 드러내면 `<microservice>_<feature>`로 도메인 중복을 피하되 서비스 접두어 뒤의 `_`는 유지한다.
- 서비스 내부에서 발견한 업무 도메인, 외부 시스템, 프로토콜, 리소스명은 서비스 접두어를 대체하지 않는다.
- 서비스 접두어와 도메인 구분자는 백엔드 서비스, 제품 기능 영역, bounded context, 공개 API/데이터 계약처럼 제품 기능을 소유하는 경계여야 한다.
- `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어 이름은 서비스 접두어 또는 도메인 구분자로 쓰지 않는다.
- 프론트엔드 코드는 사용자 조작과 화면 결과의 근거로만 사용하고, 연결된 백엔드/API/제품 기능을 추적해 스펙을 만든다.

## 제안 스펙 분할

### `<spec-id>`
- Service prefix: `<microservice>` (<마이크로서비스/서비스 폴더명, 백엔드 서비스, 제품 기능 소유 경계>)
- Domain discriminator: `<domain or none>` (<여러 업무 도메인에 걸친 서비스일 때만 사용. 서비스명이 이미 도메인을 드러내면 생략하되 spec ID는 `<microservice>_`로 시작)
- Naming 결정 근거: <마이크로서비스/서비스 입력이면 서비스 폴더명과 `_`로 시작함을 명시. 예: services/completion -> completion_*>
- Feature: `<feature>` (<하나의 사용자/클라이언트/운영자 피쳐 또는 workflow>)
- 목적: <사용자/클라이언트/운영자 관점의 피쳐 목적>
- E2E 단위 판단: <이 spec 하나가 하나의 E2E suite로 적절한 이유>
- 백엔드/제품 계약 연결:
  - <API route, stream event, persistence, auth, job, data processing, gateway/backend service contract>
- 포함 유즈 케이스:
  - <observable use case>
- 주요 관측 계약:
  - <input/output/state/error/security/performance contract>
- 다른 spec으로 분리할 범위:
  - `<other-spec-id>`: <분리 이유>
- 제외할 구현 세부:
  - <internal detail to avoid>
- frontend evidence:
  - <UI action, visible label, screen state, screenshot candidate used only as evidence>
- 근거 유형:
  - <routes/tests/docs/schemas/ui/jobs/config/etc.>
- 위험 또는 열린 질문:
  - <uncertain behavior or needed user decision>

## 추적표

| 소스 범위 | 관측된 외부 행위 | 백엔드/제품 계약 | Service prefix | Domain discriminator | Feature | 제안 스펙 폴더 | E2E 단위 | 처리 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `<folder or public boundary>` | <behavior> | <API/service/job/data contract> | `<microservice>` | `<domain or none>` | `<feature>` | `<spec-id>` | 적절/분할 필요 | 포함/제외/질문 |

## 진행 체크리스트
- [ ] 모든 입력 폴더가 확인되었다.
- [ ] 각 스펙 폴더가 `<microservice>_<domain>-<feature>` 또는 `<microservice>_<feature>` 형식을 따른다.
- [ ] 마이크로서비스/서비스 폴더 입력에서 생성된 모든 스펙 ID가 해당 서비스 폴더명으로 시작한다.
- [ ] 여러 업무 도메인에 걸친 서비스는 도메인 구분자를 사용하고, 단일 도메인 또는 도메인 표현 서비스는 도메인을 중복하지 않되 `<microservice>_` 접두어를 유지한다.
- [ ] 서비스 접두어와 도메인 구분자가 백엔드/제품 기능 경계이며 `frontend`, `ui`, `react`, `page`, `component`가 아니다.
- [ ] 스펙 폴더가 구현 구조가 아니라 피쳐 기준으로 나뉘었다.
- [ ] 프론트엔드 입력은 연결된 백엔드/API/제품 기능으로 추적되었고, 프론트엔드 단독 스펙은 생성하지 않았다.
- [ ] 어떤 스펙도 마이크로서비스 전체, route inventory, controller/service/repository 계층을 요약하지 않는다.
- [ ] 각 스펙 폴더의 유즈 케이스가 하나의 E2E suite로 자연스럽게 검증 가능한 범위다.
- [ ] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [ ] `openspec/specs` 작성 전에 이 계획이 저장되었다.
```

## Main Spec Template

Create or update `openspec/specs/<spec-id>/spec.md`:

```markdown
# <피쳐 이름> 명세

## Purpose
<이 스펙이 보장하는 사용자/클라이언트/운영자 관점의 능력을 1-3문장으로 설명한다. 구현 구조나 파일명을 설명하지 않는다.>

## Requirements

### Requirement: <관찰 가능한 능력>
시스템은 <외부에서 검증 가능한 입력, 출력, 상태 변화, 오류 처리, 권한, 제한 또는 품질 속성>을 SHALL 보장한다.

#### Scenario: <정상 또는 중요 사례>
- **GIVEN** <외부 조건 또는 사전 상태>
- **WHEN** <사용자/클라이언트/운영자가 수행하는 동작 또는 공개 이벤트>
- **THEN** <관측 가능한 결과>
- **AND** <필요한 추가 결과>

#### Scenario: <검증 또는 오류 사례>
- **GIVEN** <외부 조건 또는 사전 상태>
- **WHEN** <잘못되었거나 경계에 있는 입력/동작>
- **THEN** <관측 가능한 거부, 오류, 상태 유지, 안내 또는 복구 결과>
```

## Requirement Quality Checklist

Use this checklist for every requirement:

- [ ] Requirement title names a capability, not a class, function, component, or file.
- [ ] Requirement title, requirement body, scenario title, and scenario steps are written in Korean except exact contract identifiers.
- [ ] The requirement belongs to the single feature represented by this service-prefixed spec.
- [ ] The requirement is tied to a backend/product contract, not frontend-only component behavior.
- [ ] Requirement body uses SHALL or MUST.
- [ ] Behavior is testable from outside the implementation boundary.
- [ ] Scenarios include observable GIVEN/WHEN/THEN facts.
- [ ] Public identifiers are exact only where they are part of the contract.
- [ ] No source path, line number, private helper, class name, or internal call sequence appears.
- [ ] The requirement would still make sense if the implementation were rewritten.

## Anti-Patterns

Avoid:

```markdown
### `frontend_text2sql-react`
- Service prefix: `frontend`
- Feature: `text2sql-react`
- 목적: React 화면이 Text2SQL 결과를 표시한다.
```

Prefer:

```markdown
### `text2sql-streaming`
- Service prefix: `text2sql`
- Domain discriminator: 없음
- Feature: `streaming`
- 백엔드/제품 계약 연결:
  - `POST /text2sql/react` NDJSON stream, session resume, execution result contract
- frontend evidence:
  - 질문 입력, 실행 버튼, 진행 타임라인, 결과 테이블 화면
```

Avoid:

```markdown
### `billing`
- 목적: Billing 마이크로서비스 전체 기능 요약
- 포함 유즈 케이스:
  - invoice search
  - payment retry
  - refund processing
```

Prefer:

```markdown
### `billing_invoice-search`
- Service prefix: `billing`
- Domain discriminator: 없음
- Feature: `invoice-search`
- 목적: 청구 도메인에서 사용자가 송장을 검색하고 결과를 확인하는 피쳐
- E2E 단위 판단: 송장 검색 입력, 필터링, 결과 표시, 빈 결과 처리를 하나의 사용자 흐름으로 검증할 수 있다.
```

Avoid:

```markdown
### `agent_memory-chat`
- Service prefix: `agent`
- Feature: `memory-chat`
- 목적: `services/completion` 안의 agent memory 대화 흐름을 별도 업무 도메인으로 분리한다.
```

Prefer:

```markdown
### `completion_agent-memory-chat`
- Service prefix: `completion`
- Domain discriminator: `agent`
- Naming 결정 근거: `services/completion` 마이크로서비스에서 관찰된 피쳐이므로 서비스명을 접두어로 고정하고, 여러 업무 도메인 중 agent 영역을 도메인 구분자로 둔다.
- Feature: `memory-chat`
- 목적: completion 서비스에서 사용자가 메모리 기반 대화 흐름을 이어가는 피쳐
```

Avoid:

```markdown
### Requirement: UserService create_user 함수
시스템은 `UserCreateRequest`를 검증한 뒤 `create_user()`를 호출해야 한다.
```

Prefer:

```markdown
### Requirement: 사용자 등록
시스템은 유효한 등록 요청을 받으면 공개 사용자 계약을 통해 조회 가능한 계정을 생성해야 한다.

#### Scenario: 등록 성공
- **GIVEN** 클라이언트가 모든 필수 등록 필드를 제공한다
- **WHEN** 클라이언트가 등록 요청을 제출한다
- **THEN** 시스템은 공개 계정 식별자가 포함된 성공 결과를 반환한다
- **AND** 생성된 계정은 이후 인가된 작업에서 사용할 수 있다
```

Avoid:

```markdown
#### Scenario: Repository save branch
- **WHEN** `UserRepository.save()` is called from `AuthController`
- **THEN** line 42 stores the entity
```

Prefer:

```markdown
#### Scenario: 승인 후 결과 보존
- **WHEN** 시스템이 유효한 요청을 수락한다
- **THEN** 결과 상태는 이후 인가된 조회를 위해 보존된다
```
