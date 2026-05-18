# Code To Spec Templates

Use these templates when running the `code-to-spec` workflow. Write generated content in Korean unless the user explicitly requests another language.

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
- 공개 API 경로, 요청/응답 필드명, 이벤트명, 설정 키는 계약인 경우에만 원문을 유지한다.

## 제안 스펙 분할

### `<capability-folder>`
- 목적: <사용자/클라이언트/운영자 관점의 능력>
- 포함 유즈 케이스:
  - <observable use case>
- 주요 관측 계약:
  - <input/output/state/error/security/performance contract>
- 제외할 구현 세부:
  - <internal detail to avoid>
- 근거 유형:
  - <routes/tests/docs/schemas/ui/jobs/config/etc.>
- 위험 또는 열린 질문:
  - <uncertain behavior or needed user decision>

## 추적표

| 소스 범위 | 관측된 외부 행위 | 제안 스펙 폴더 | 처리 |
| --- | --- | --- | --- |
| `<folder or public boundary>` | <behavior> | `<capability-folder>` | 포함/제외/질문 |

## 진행 체크리스트
- [ ] 모든 입력 폴더가 확인되었다.
- [ ] 스펙 폴더가 구현 구조가 아니라 능력 기준으로 나뉘었다.
- [ ] 각 스펙 폴더의 유즈 케이스가 정의되었다.
- [ ] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [ ] `openspec/specs` 작성 전에 이 계획이 저장되었다.
```

## Main Spec Template

Create or update `openspec/specs/<capability-folder>/spec.md`:

```markdown
# <Capability Name> Specification

## Purpose
<이 스펙이 보장하는 사용자/클라이언트/운영자 관점의 능력을 1-3문장으로 설명한다. 구현 구조나 파일명을 설명하지 않는다.>

## Requirements

### Requirement: <Observable Capability>
The system SHALL <외부에서 검증 가능한 입력, 출력, 상태 변화, 오류 처리, 권한, 제한 또는 품질 속성을 정의한다>.

#### Scenario: <Normal or Important Case>
- **GIVEN** <외부 조건 또는 사전 상태>
- **WHEN** <사용자/클라이언트/운영자가 수행하는 동작 또는 공개 이벤트>
- **THEN** <관측 가능한 결과>
- **AND** <필요한 추가 결과>

#### Scenario: <Validation or Error Case>
- **GIVEN** <외부 조건 또는 사전 상태>
- **WHEN** <잘못되었거나 경계에 있는 입력/동작>
- **THEN** <관측 가능한 거부, 오류, 상태 유지, 안내 또는 복구 결과>
```

## Requirement Quality Checklist

Use this checklist for every requirement:

- [ ] Requirement title names a capability, not a class, function, component, or file.
- [ ] Requirement body uses SHALL or MUST.
- [ ] Behavior is testable from outside the implementation boundary.
- [ ] Scenarios include observable GIVEN/WHEN/THEN facts.
- [ ] Public identifiers are exact only where they are part of the contract.
- [ ] No source path, line number, private helper, class name, or internal call sequence appears.
- [ ] The requirement would still make sense if the implementation were rewritten.

## Anti-Patterns

Avoid:

```markdown
### Requirement: UserService create_user 함수
The system SHALL call `create_user()` after validating `UserCreateRequest`.
```

Prefer:

```markdown
### Requirement: User Registration
The system SHALL accept a valid registration request and create an account that can be retrieved through the public user-facing contract.

#### Scenario: Successful registration
- **GIVEN** a client provides all required registration fields
- **WHEN** the client submits the registration request
- **THEN** the system returns a successful result containing the public account identifier
- **AND** the account is available for subsequent authorized operations
```

Avoid:

```markdown
#### Scenario: Repository save branch
- **WHEN** `UserRepository.save()` is called from `AuthController`
- **THEN** line 42 stores the entity
```

Prefer:

```markdown
#### Scenario: Persisted result after acceptance
- **WHEN** the system accepts a valid request
- **THEN** the resulting state is retained for later authorized reads
```
