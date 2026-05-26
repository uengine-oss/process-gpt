# 스킬 작성·재사용 명세

## Purpose
시스템이 절차형 지식(SKILL)이 필요할 때 기존 스킬을 우선 재사용하여 에이전트에 적재하거나, 필요한 경우에만 새 스킬을 생성·수정·삭제하고, 에이전트와 테넌트의 스킬 목록을 동기화하며 변경 이력을 남기는 능력을 보장한다.

## Requirements

### Requirement: 기존 스킬 재사용 적재
시스템은 기존 스킬로 요구 절차를 충분히 충족할 수 있을 때 새 스킬을 생성하지 않고 기존 스킬을 에이전트에 적재해야 한다. 적재 대상은 쉼표로 구분된 스킬 식별자로 전달되며, 단일 또는 다중 스킬 적재를 SHALL 지원한다.

#### Scenario: 단일/다중 기존 스킬 적재
- **GIVEN** 요구 절차를 충족하는 기존 스킬 식별자가 쉼표로 구분되어 전달된다
- **WHEN** 시스템이 스킬 적재를 수행한다
- **THEN** 시스템은 스킬 내용을 생성·수정하지 않고 해당 스킬을 에이전트에 적재한다
- **AND** 적재 사실을 에이전트 스킬 목록 동기화와 변경 이력으로 기록한다

#### Scenario: 적재할 스킬 식별자 누락
- **GIVEN** 적재 요청에 유효한 스킬 식별자가 하나도 없다
- **WHEN** 시스템이 스킬 적재를 수행한다
- **THEN** 시스템은 적재를 수행하지 않고 실패를 반환한다

### Requirement: 신규 스킬 생성·수정·삭제
시스템은 기존 스킬로 절차를 커버할 수 없을 때만 새 스킬을 생성하고, 동일 범위·절차의 보완일 때만 기존 스킬을 수정해야 한다. `UPDATE`와 `DELETE`에는 기존 스킬 식별자를 SHALL 요구하며, 생성하려는 스킬 이름이 이미 존재하면 생성을 거부한다.

#### Scenario: 신규 스킬 생성
- **GIVEN** 기존 스킬로 커버되지 않는 새 절차가 필요하다
- **WHEN** 시스템이 `CREATE` 작업으로 스킬을 생성한다
- **THEN** 시스템은 스킬 저장소에 새 스킬을 저장하고 변경 이력을 기록한다

#### Scenario: 이미 존재하는 이름으로 생성 거부
- **GIVEN** 생성하려는 스킬 이름과 동일한 스킬이 이미 저장소에 존재한다
- **WHEN** 시스템이 `CREATE` 작업을 수행한다
- **THEN** 시스템은 생성을 거부하고, 수정이 필요하면 `UPDATE` 작업을 사용하도록 처리를 실패로 종료한다

#### Scenario: 식별자 없는 수정/삭제 거부
- **GIVEN** `UPDATE` 또는 `DELETE` 작업에 기존 스킬 식별자가 없다
- **WHEN** 시스템이 스킬 작업을 수행한다
- **THEN** 시스템은 작업을 거부한다

### Requirement: 스킬 문서 형식 보장
시스템은 저장되는 스킬 문서가 `name`·`description` frontmatter 등 형식 규칙을 만족하도록 SHALL 보장한다.

#### Scenario: 형식을 만족하는 스킬 문서 저장
- **GIVEN** 스킬을 생성 또는 수정한다
- **WHEN** 시스템이 스킬 문서를 저장한다
- **THEN** 저장된 스킬 문서는 `name`과 `description`을 포함한 frontmatter 형식을 만족한다

### Requirement: 스킬 생성 경로 선택
시스템은 설정 키 `USE_SKILL_CREATOR_WORKFLOW`와 `COMPUTER_USE_MCP_URL`이 모두 설정된 경우 `CREATE`/`UPDATE`를 skill-creator 경로로 처리하고, 그렇지 않으면 기본 HTTP 경로로 처리해야 한다. `DELETE`는 항상 기본 HTTP 경로로 SHALL 처리한다.

#### Scenario: skill-creator 경로 사용
- **GIVEN** `USE_SKILL_CREATOR_WORKFLOW`가 활성화되고 `COMPUTER_USE_MCP_URL`이 설정되어 있다
- **WHEN** 시스템이 스킬 `CREATE` 또는 `UPDATE`를 수행한다
- **THEN** 시스템은 skill-creator 경로로 스킬 문서와 부가 파일을 생성·검증한다

#### Scenario: 설정 미비 시 기본 경로 사용
- **GIVEN** `USE_SKILL_CREATOR_WORKFLOW`는 활성화되었으나 `COMPUTER_USE_MCP_URL`이 설정되지 않았다
- **WHEN** 시스템이 스킬 `CREATE` 또는 `UPDATE`를 수행한다
- **THEN** 시스템은 기본 HTTP 경로로 스킬을 저장한다

#### Scenario: 삭제 경로
- **GIVEN** 스킬 삭제 요청이 발생한다
- **WHEN** 시스템이 `DELETE` 작업을 수행한다
- **THEN** 시스템은 설정과 무관하게 기본 HTTP 경로로 스킬을 삭제한다

### Requirement: 스킬 목록 동기화
시스템은 스킬 생성·삭제·적재 시 에이전트와 테넌트의 스킬 목록을 동기화해야 한다. `users.skills`는 쉼표로 구분된 문자열, `tenants.skills`는 배열 형태로 SHALL 갱신한다.

#### Scenario: 스킬 생성 후 목록 동기화
- **GIVEN** 새 스킬이 생성되었거나 기존 스킬이 적재되었다
- **WHEN** 시스템이 스킬 목록을 갱신한다
- **THEN** 해당 스킬이 `users.skills`(쉼표 문자열)와 `tenants.skills`(배열)에 반영된다

#### Scenario: 스킬 삭제 후 목록 동기화
- **GIVEN** 기존 스킬이 삭제되었다
- **WHEN** 시스템이 스킬 목록을 갱신한다
- **THEN** 해당 스킬이 `users.skills`와 `tenants.skills`에서 제거된다
