# Agent Task Protocol Specification

## Purpose
ProcessGPT 플랫폼 위에서 동작하는 모든 에이전트 워커가 공통으로 따르는 작업 수명주기 계약을 정의한다. 이 계약은 작업 큐 클레임, 상태 전이, 드래프트/최종 산출 저장, 피드백 재진입, 실행 이벤트의 외부 가시 동작을 보장하여 워커 구현이 교체되어도 외부에서 관찰 가능한 진행과 결과가 안정적으로 유지되도록 한다.

## Requirements

### Requirement: 에이전트별 작업 한정 클레임
The system SHALL provide a way for an agent worker to atomically claim pending work items intended for its own agent identifier without interfering with concurrent workers.

#### Scenario: 단일 워커가 자신의 작업을 클레임한다
- **GIVEN** `todolist` 테이블에 `status='IN_PROGRESS'`, `agent_orch='<my-agent>'`, `draft_status IS NULL` 인 행이 존재한다
- **WHEN** 워커가 `agent_orch`와 자신의 컨슈머 식별자를 인자로 작업 클레임 RPC(`fetch_pending_task` 또는 그 테넌트 변형 `fetch_pending_task_dev`)를 호출한다
- **THEN** RPC는 해당 행을 단일 워커에게만 반환하고, 그 행의 `draft_status`를 `STARTED`로 갱신하며 `consumer`를 호출한 워커의 식별자로 표시한다
- **AND** 동일 행을 다른 컨슈머가 동시에 호출해도 두 번 반환되지 않는다

#### Scenario: 사용자 피드백 이후 재진입
- **GIVEN** 이전에 완료된 작업의 `draft_status`가 사용자 피드백에 의해 `FB_REQUESTED`로 표시되어 있다
- **WHEN** 동일 `agent_orch`의 워커가 클레임 RPC를 호출한다
- **THEN** 시스템은 해당 행을 다시 반환하여 워커가 재실행할 수 있게 하고, `draft_status`를 `STARTED`로 갱신한다

#### Scenario: 멀티테넌트 환경에서 테넌트 한정 폴링
- **GIVEN** 개발/멀티테넌트 환경에서 워커가 특정 테넌트로 한정해 폴링하도록 구성되어 있다
- **WHEN** 워커가 테넌트 변형 클레임 RPC를 호출한다
- **THEN** 반환되는 작업 행은 모두 호출자가 지정한 `tenant_id`와 일치한다

### Requirement: 작업 상태 전이 가시화
The system SHALL expose externally observable state transitions for every work item: claim, intermediate progress, final submission, and feedback re-entry.

#### Scenario: 정상 처리 경로
- **GIVEN** 워커가 작업을 클레임한 직후
- **WHEN** 워커가 처리를 시작하고 진행한다
- **THEN** 외부 관측자에게 `todolist` 행의 `draft_status`는 `STARTED`로 보인다
- **AND** 중간 산출이 발생할 때 `draft` 필드가 갱신될 수 있다
- **AND** 작업이 최종 완료되면 `draft_status`가 `COMPLETED`로, `consumer`가 비워지며, `status`가 `SUBMITTED`(또는 처리 모드에 따라 `DONE`)로 전이된다

#### Scenario: 드래프트와 최종 산출의 구분
- **GIVEN** 워커가 중간 결과를 저장하고자 한다
- **WHEN** 워커가 비최종 저장 RPC 호출(`save_task_result`에 `final=false`로 호출 또는 동등한 효과)을 수행한다
- **THEN** `draft` 필드에 페이로드가 저장되고 `status`와 `draft_status`는 아직 완료로 표시되지 않는다
- **AND** 사용자 또는 다른 시스템이 `draft`를 외부에서 조회할 수 있다

#### Scenario: 최종 산출 저장
- **GIVEN** 워커가 최종 결과를 저장하고자 한다
- **WHEN** 워커가 최종 저장(`save_task_result`에 `final=true`)을 호출한다
- **THEN** `agent_mode='COMPLETE'`인 경우 `output` 필드에 최종 페이로드가 저장되고, 그 외 모드에서는 `draft` 필드에 저장된다
- **AND** `draft_status='COMPLETED'`, `status='SUBMITTED'`, `consumer=NULL`로 전이된다

### Requirement: 완료 산출의 외부 조회
The system SHALL allow external readers to query the final outputs of a completed process instance.

#### Scenario: 프로세스 인스턴스의 완료 산출 회수
- **WHEN** 호출자가 프로세스 인스턴스 식별자(`proc_inst_id`)와 함께 산출 조회 RPC(`fetch_done_data`)를 호출한다
- **THEN** 시스템은 해당 인스턴스에서 `status='DONE'`이고 `output IS NOT NULL`인 행들의 `output` JSON만 반환한다

### Requirement: 실행 이벤트 영속 기록
The system SHALL record observable execution events emitted by workers so that operators and other systems can reconstruct the timeline of any work item.

#### Scenario: 작업 단위 이벤트 기록
- **GIVEN** 워커가 작업 처리 중이다
- **WHEN** 워커가 시작/진행/완료/오류/취소 등의 이벤트를 발행한다
- **THEN** 각 이벤트는 적어도 작업 식별자, 프로세스 인스턴스 식별자, 이벤트 타입, 타임스탬프를 포함하여 `events` 테이블에 영속 기록된다
- **AND** 외부 조회자는 작업 식별자로 이 이벤트들을 시간순으로 조회할 수 있다

### Requirement: 워커 비정상 종료에 대한 폴링 지속
The system SHALL ensure that a worker process failure on one work item does not stop the worker from picking up subsequent items.

#### Scenario: 단일 작업의 실패가 폴링을 중단시키지 않는다
- **GIVEN** 워커가 작업 하나를 처리하다 비정상 종료한다
- **WHEN** 동일 워커 인스턴스가 다음 폴링 주기에 도달한다
- **THEN** 워커는 다른 pending 작업을 다시 클레임 시도하고 정상 처리한다
- **AND** 실패한 작업은 상태가 변경되지 않은 채(또는 명시적 오류 표시와 함께) 추후 재시도 또는 운영 조사 대상으로 남는다

### Requirement: 동시성 안전한 클레임
The system SHALL guarantee that a single pending work item is delivered to at most one worker at a time.

#### Scenario: 다중 워커 동시 폴링
- **GIVEN** 동일 `agent_orch`를 처리하는 여러 워커 인스턴스가 동시에 폴링한다
- **WHEN** pending 행이 하나만 존재한다
- **THEN** 그 행은 정확히 한 워커에게만 반환되고, 나머지 워커는 빈 결과를 받는다
