# DeepAgents 워크아이템 사람 질문 대기·재개 명세

## Purpose
COMPLETE 모드 워크아이템(`todolist.agent_mode = 'COMPLETE'`)은 에이전트가 제출까지 맡는다.
작업 도중 사람의 판단이나 정보가 필요하면 에이전트는 사람에게 묻고, 답을 받을 때까지
작업을 멈춘 채 기다려야 한다. 질문 문구가 산출물로 제출되어 프로세스가 다음 단계로
넘어가서는 안 된다. 답이 오면 에이전트는 멈춘 지점에서 그 답을 받아 이어서 실행하고,
답을 반영한 결과를 제출한다.

이 계약은 워크아이템 폴링 런타임(process-gpt-agent-sdk)과 DeepAgents 실행기, 워크아이템
화면이 함께 지킨다. 사람 답변 대기 상태는 `draft_status = 'HUMAN_ASKED'`로 표현한다.

## Requirements

### Requirement: 질문을 산출물로 제출하지 않는다
시스템은 워크아이템 실행이 사람에게 질문하고 끝나면 그 실행을 완료로 SHALL NOT 처리한다. 작업은 `status = 'IN_PROGRESS'`, `draft_status = 'HUMAN_ASKED'`로 남아야 하며, 질문 문구를 `output`이나 `draft`에 저장해서는 안 되고, `crew_completed` 이벤트를 기록해서는 안 된다. 질문은 `human_asked` 이벤트로 SHALL 남긴다.

#### Scenario: HITL-01 COMPLETE 워크아이템이 질문하고 멈춘다
- **GIVEN** `agent_mode = 'COMPLETE'`인 워크아이템이 실행된다
- **WHEN** 에이전트가 사람에게 질문하고 실행을 마친다
- **THEN** 작업은 `status = 'IN_PROGRESS'`, `draft_status = 'HUMAN_ASKED'`이다
- **AND** `output`은 비어 있고 프로세스는 다음 단계로 진행하지 않는다
- **AND** events에는 질문 문구를 담은 `human_asked`가 있고 `crew_completed`는 없다

#### Scenario: HITL-02 DRAFT 워크아이템도 질문을 초안으로 저장하지 않는다
- **GIVEN** `agent_mode = 'DRAFT'`인 워크아이템 실행이 사람에게 질문하고 끝난다
- **WHEN** 실행 결과가 저장된다
- **THEN** 작업은 `draft_status = 'HUMAN_ASKED'`이고 `draft`는 비어 있다

#### Scenario: HITL-03 결과 없이 질문만 남기고 끝나도 대기로 둔다
- **GIVEN** 에이전트가 사람 입력 요청 상태만 보내고 결과를 보내지 않은 채 실행을 마친다
- **WHEN** 실행이 끝난다
- **THEN** 작업은 `draft_status = 'HUMAN_ASKED'`이고 `STARTED`로 남지 않는다

#### Scenario: HITL-04 같은 실행 안에서 답을 받아 이어 갔으면 결과로 제출한다
- **GIVEN** 에이전트가 질문한 뒤 같은 실행 안에서 답을 받아 작업을 계속했다
- **WHEN** 마지막 결과를 보낸다
- **THEN** 그 결과는 정상 산출물로 저장되고 `crew_completed`가 기록된다

### Requirement: 대기 중인 작업은 점유를 풀고 다시 집히지 않는다
시스템은 `HUMAN_ASKED` 작업의 점유(`consumer`, `lease_until`)를 SHALL 해제하고, 답이 올 때까지 어떤 워커도 그 작업을 다시 집어서는 안 된다. 기다림은 장애가 아니므로 lease 만료 회수 대상도 아니다.

#### Scenario: HITL-05 답이 오기 전에는 폴링에 걸리지 않는다
- **GIVEN** 작업이 `HUMAN_ASKED`이고 `consumer`와 `lease_until`이 비어 있다
- **WHEN** 같은 `agent_orch`의 워커가 작업을 폴링한다
- **THEN** 그 작업은 반환되지 않는다

#### Scenario: HITL-06 대기 표시 전에 취소됐으면 취소를 유지한다
- **GIVEN** 실행 중인 작업이 사용자 취소로 `draft_status = 'CANCELLED'`가 되었다
- **WHEN** 실행이 질문을 남기고 끝난다
- **THEN** 작업은 `CANCELLED`로 남고 `HUMAN_ASKED`로 바뀌지 않는다

### Requirement: 질문 카드에 답하면 작업이 다시 진행된다
워크아이템 화면은 `human_asked` 질문 문구를 질문 카드에 SHALL 보인다. 사용자가 `HUMAN_ASKED` 작업의 질문 카드에 답하면, 화면은 답을 `human_response` 이벤트로 남기고 `feedback`에 답 원문을 추가한 뒤 `draft_status`를 `FB_REQUESTED`로 SHALL 바꾼다. 실행 안에서 응답을 기다리는 작업(`STARTED`)에는 `draft_status`를 바꾸지 않는다.

#### Scenario: HITL-07 질문 카드에서 답한다
- **GIVEN** `HUMAN_ASKED` 작업의 워크아이템 화면이 열려 있다
- **WHEN** 사용자가 질문 카드에 답을 입력하고 확인한다
- **THEN** events에 `human_response`가 기록된다
- **AND** 작업은 `draft_status = 'FB_REQUESTED'`이고 `feedback` 마지막 항목의 `content`가 입력한 답이다

#### Scenario: HITL-08 대기 상태가 되면 진행 표시를 내린다
- **GIVEN** 워크아이템 화면이 에이전트 진행 중으로 표시되어 있다
- **WHEN** 작업이 `HUMAN_ASKED`로 바뀐다
- **THEN** 진행 표시가 사라지고 사용자는 질문 카드에 답할 수 있다

### Requirement: 멈춘 지점에서 답 원문으로 이어서 실행한다
시스템은 `FB_REQUESTED`로 돌아온 작업에 재개 대기 중인 질문이 있으면, `feedback` 마지막 항목의 답 원문을 그 질문의 응답으로 넘겨 멈춘 지점부터 SHALL 이어서 실행한다. 답은 요약이나 재작성을 거쳐서는 안 된다. 재개 대기 중인 질문이 없으면(예: 실행 상태 유실) 답과 원래 작업 지시로 작업을 다시 수행한다.

#### Scenario: HITL-09 답을 반영해 결과를 제출한다
- **GIVEN** `HUMAN_ASKED` 작업에 사용자가 답해 `FB_REQUESTED`가 되었다
- **WHEN** 워커가 작업을 다시 집어 실행한다
- **THEN** 에이전트는 같은 질문을 다시 하지 않고 이어서 실행한다
- **AND** 작업은 `status = 'SUBMITTED'`, `draft_status = 'COMPLETED'`이고 `output`에 답의 내용이 반영되어 있다
- **AND** `crew_completed`가 한 번 기록된다

### Requirement: 실행 진행 이벤트를 잃지 않는다
시스템은 질문·대기·재개 과정에서 발생한 실행 진행 이벤트를 events에 빠짐없이 SHALL 저장한다. 저장소가 허용하지 않는 이벤트 종류를 보내 같은 묶음의 다른 이벤트까지 저장에 실패해서는 안 된다.

#### Scenario: HITL-10 재개 실행의 이벤트가 모두 저장된다
- **GIVEN** 질문 → 대기 → 답변 → 재개 → 제출이 한 번 진행되었다
- **WHEN** 해당 작업의 events를 조회한다
- **THEN** `task_started`, `human_asked`, `human_response`, `task_completed`, `crew_completed`가 모두 있다
- **AND** 워커 로그에 이벤트 저장 실패가 없다

### Requirement: 사람 질문 수단을 실행 맥락에 맞게 제공한다
시스템은 DeepAgents에 사람에게 질문하는 수단을 채팅과 COMPLETE 워크아이템에서 SHALL 제공하고, DRAFT 워크아이템에서는 제공하지 않는다. DRAFT는 사람이 초안을 검토하는 단계가 이미 있기 때문이다.

#### Scenario: HITL-11 COMPLETE 워크아이템에서 사람에게 묻는다
- **GIVEN** 작업 지시가 진행 전에 사람의 확인을 요구하는 COMPLETE 워크아이템이다
- **WHEN** DeepAgents가 작업을 실행한다
- **THEN** 에이전트는 질문을 평문 결과로 내지 않고 사람 질문 수단으로 묻는다

#### Scenario: HITL-12 DRAFT 워크아이템에는 질문 수단을 주지 않는다
- **GIVEN** DRAFT 워크아이템이다
- **WHEN** DeepAgents가 작업을 실행한다
- **THEN** 사람 질문 수단은 제공되지 않는다
