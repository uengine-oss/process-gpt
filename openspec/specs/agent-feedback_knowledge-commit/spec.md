# 지식 저장·병합·변경 이력 명세

## Purpose
시스템이 분석된 지식을 적절한 저장소(MEMORY, DMN_RULE)로 분류하여 저장하면서, 기존 지식과의 관계에 따라 안전하게 병합(보존/확장/대체)하고, DMN 규칙의 버전을 관리하며, 모든 변경을 감사 가능한 이력으로 기록하는 능력을 보장한다.

## Requirements

### Requirement: 지식 저장소 분류 저장
시스템은 새 지식을 그 성격에 따라 MEMORY(지침·선호도·맥락) 또는 DMN_RULE(조건-결과 규칙)로 분류하여 저장해야 하며, 각 저장소의 작업으로 `CREATE`, `UPDATE`, `DELETE`를 SHALL 지원한다.

#### Scenario: MEMORY 신규 저장
- **GIVEN** 저장 대상이 지침·선호도 성격의 지식이다
- **WHEN** 시스템이 `CREATE` 작업으로 MEMORY를 저장한다
- **THEN** 시스템은 해당 에이전트 범위의 메모리 저장소에 지식을 영속화한다
- **AND** 저장 사실을 변경 이력으로 기록한다

#### Scenario: DMN_RULE 신규 저장
- **GIVEN** 저장 대상이 조건-결과 규칙 성격의 지식이다
- **WHEN** 시스템이 `CREATE` 작업으로 DMN_RULE을 저장한다
- **THEN** 시스템은 `type='dmn'`, `owner=agent_id`로 규칙을 영속화하고 초기 버전 `1.0.0`을 부여한다
- **AND** 저장 사실을 변경 이력과 버전 스냅샷으로 기록한다

### Requirement: 기존 식별자 필수 및 보호
시스템은 `UPDATE` 또는 `DELETE` 작업에는 기존 지식 식별자(`memory_id` 또는 `rule_id`)를 SHALL 요구한다. 식별자가 누락되면 작업을 거부하고, `CREATE`로 들어온 요청이라도 기존 식별자가 함께 전달되면 기존 지식을 덮어쓰지 않도록 `UPDATE`로 처리한다.

#### Scenario: 식별자 없는 수정/삭제 거부
- **GIVEN** `UPDATE` 또는 `DELETE` 작업 요청에 기존 지식 식별자가 없다
- **WHEN** 시스템이 저장 작업을 수행한다
- **THEN** 시스템은 작업을 거부하고 처리를 실패로 종료한다

#### Scenario: 식별자가 있는 CREATE의 UPDATE 전환
- **GIVEN** `CREATE` 작업 요청에 기존 규칙 식별자(`rule_id`)가 함께 전달되었다
- **WHEN** 시스템이 DMN_RULE 저장을 수행한다
- **THEN** 시스템은 새 규칙을 만들지 않고 해당 식별자의 기존 규칙을 `UPDATE`로 처리한다

### Requirement: 관계 기반 병합
시스템은 새 지식과 기존 지식의 관계 유형에 따라 병합 방식을 선택해야 하며, `merge_mode`가 `EXTEND`인 DMN_RULE 수정 시 기존 규칙을 보존한 채 새 규칙을 추가해야 한다. `REPLACE`는 완전 대체, `EXTEND`는 보존+추가, `REFINE`은 기존 참조 후 수정 의도를 SHALL 표현한다.

#### Scenario: EXTEND 모드 규칙 확장
- **GIVEN** 에이전트 소유의 기존 DMN 규칙이 있고 새 조건-결과가 기존 규칙을 확장한다
- **WHEN** 시스템이 `merge_mode=EXTEND`로 `UPDATE`를 수행한다
- **THEN** 시스템은 기존 규칙을 모두 보존하고 새 규칙을 추가한 결과를 저장한다

#### Scenario: REPLACE 모드 규칙 대체
- **GIVEN** 기존 DMN 규칙이 새 지식으로 완전히 대체되어야 한다
- **WHEN** 시스템이 `merge_mode=REPLACE`로 `UPDATE`를 수행한다
- **THEN** 시스템은 전달된 내용을 최종 규칙으로 저장한다

### Requirement: DMN 규칙 버전 관리
시스템은 DMN 규칙을 생성·수정할 때마다 시맨틱 버전을 부여하고 버전 스냅샷을 보존해야 한다. `merge_mode`에 따라 `REPLACE`는 major, `EXTEND`는 minor, `REFINE`은 patch 버전을 증가시키며, 각 버전은 이전 버전 대비 변경 요약(diff)과 함께 SHALL 보존된다.

#### Scenario: 수정 시 버전 증가와 스냅샷 보존
- **GIVEN** 버전이 부여된 기존 DMN 규칙이 있다
- **WHEN** 시스템이 해당 규칙을 `UPDATE`한다
- **THEN** 시스템은 `merge_mode`에 따라 다음 버전 번호를 부여한다
- **AND** 이전 버전 대비 변경 요약을 포함한 버전 스냅샷을 보존한다

#### Scenario: 버전 정보가 없는 기존 규칙 처리
- **GIVEN** 기존 DMN 규칙에 버전 정보가 없다
- **WHEN** 시스템이 해당 규칙을 `UPDATE`한다
- **THEN** 시스템은 기존 내용을 초기 버전 `1.0.0` 스냅샷으로 보존한 뒤 다음 버전을 부여한다

### Requirement: 변경 이력 기록
시스템은 모든 지식의 생성·수정·삭제에 대해 변경 전후 내용과 원본 피드백을 포함한 변경 이력을 기록해야 하며, 변경 이력 기록에 실패하면 해당 저장 작업 전체를 실패로 SHALL 간주한다.

#### Scenario: 변경 이력 기록 성공
- **GIVEN** 지식의 생성·수정·삭제가 수행되었다
- **WHEN** 시스템이 변경 이력을 기록한다
- **THEN** 변경 이력에는 `knowledge_type`, `operation`, 변경 전 내용(`previous_content`), 변경 후 내용(`new_content`), 원본 피드백(`feedback_content`)이 포함된다

#### Scenario: 변경 이력 기록 실패
- **GIVEN** 지식 저장 자체는 수행되었으나 변경 이력 기록이 실패한다
- **WHEN** 시스템이 저장 작업을 마무리한다
- **THEN** 시스템은 해당 저장 작업 전체를 실패로 처리한다

### Requirement: 저장 권한 범위와 미커밋 실패
시스템은 DMN 규칙의 수정·삭제를 `owner=agent_id` 범위로 SHALL 제한한다. 또한 처리 주체가 저장·수정·삭제 결론을 냈으나 실제 저장 도구를 호출하지 않으면 미커밋(no_commit) 실패로, 저장 도구가 오류를 반환하면 커밋 실패(commit_failed)로 간주한다.

#### Scenario: 소유 범위 밖 규칙 수정 차단
- **GIVEN** 수정·삭제 대상 DMN 규칙의 소유자가 요청 에이전트가 아니다
- **WHEN** 시스템이 해당 규칙의 수정·삭제를 시도한다
- **THEN** 해당 규칙은 변경되지 않는다

#### Scenario: 결론만 내고 저장하지 않은 경우
- **GIVEN** 처리 주체가 저장/수정/삭제 결론을 보고했다
- **WHEN** 실제 저장 도구가 한 번도 호출되지 않는다
- **THEN** 시스템은 처리를 미커밋(no_commit) 실패로 기록한다

#### Scenario: 저장 도구 오류
- **GIVEN** 처리 주체가 저장 도구를 호출했다
- **WHEN** 저장 도구가 오류를 반환한다
- **THEN** 시스템은 처리를 커밋 실패(commit_failed)로 기록한다
