# 에이전트 SDK 워크아이템 점유 만료·회수 명세

## Purpose
에이전트 서비스의 워커는 대기 중인 워크아이템(`todolist`)을 하나씩 점유해 실행한다. 워커가
작업을 점유한 채 강제 종료되면(OOM, 노드 축출, 오토스케일 축소) 그 작업이 영구히
`draft_status = 'STARTED'`로 남아 아무도 다시 처리하지 않는 일이 없어야 한다. 반대로 살아서
일하는 워커의 작업을 다른 워커가 빼앗아 두 번 실행해서도 안 된다.

이를 위해 점유에는 만료 시한(`lease_until`)이 있고, 살아 있는 워커는 수행 내내 그것을
연장하며, 만료된 점유는 다른 워커가 회수한다. 이 계약은 워크아이템 폴링 런타임
(process-gpt-agent-sdk ≥ 0.10.0)과 작업 점유 RPC(`fetch_pending_task`, `renew_task_lease`,
`release_task_lease`)가 함께 지키며, 이 런타임으로 폴링하는 모든 에이전트 서비스
(deepagents, cli-agent, codex 등)에 서비스 코드 변경 없이 적용된다.

설정 값: `TASK_LEASE_SECONDS`(점유 유지 시간, 기본 120초), `TASK_LEASE_HEARTBEAT_SECONDS`
(연장 주기, 기본 lease 의 1/4), `TASK_MAX_CLAIMS`(한 작업의 점유 횟수 상한, 기본 3).

시나리오 ID 는 검증 위치를 나타낸다. `SVC-LEASE-*`는 실제 서비스 워커로 검증하는 이 폴더의
`e2e/` suite, `LEASE-BENCH-*`는 점유 수명만 떼어 범용 워커로 검증하는 벤치(인프라 저장소의
lease 벤치)에서 검증한다.

## Requirements

### Requirement: 작업을 점유할 때 만료 시한을 건다
시스템은 워커가 대기 작업을 점유할 때 그 점유에 지금부터 lease 길이만큼의 만료 시한(`lease_until`)을 SHALL 건다. 점유된 작업은 `draft_status = 'STARTED'`이고 점유자(`consumer`)는 점유한 워커이며, 작업이 점유된 횟수(`claim_count`)가 SHALL 기록된다.

#### Scenario: SVC-LEASE-01 점유할 때 만료 시한을 건다
- **GIVEN** lease 를 아는 워커가 폴링 중이다
- **WHEN** 워커가 대기 작업을 점유한다
- **THEN** 작업은 `draft_status = 'STARTED'`이고 `consumer`는 그 워커다
- **AND** `lease_until`은 지금부터 lease 길이만큼 뒤다
- **AND** `claim_count`는 1 이다

### Requirement: 살아 있는 워커는 수행 내내 점유를 유지한다
시스템은 작업을 수행 중인 워커가 heartbeat 주기마다 만료 시한을 SHALL 연장하게 한다. 연장은 에이전트의 수행이 워커의 이벤트 처리를 붙잡고 있어도 멈춰서는 안 된다. 살아서 연장 중인 점유는 다른 워커가 회수해서는 안 된다.

#### Scenario: SVC-LEASE-02 살아 있는 워커는 점유를 연장하고 빼앗기지 않는다
- **GIVEN** 워커가 작업을 수행 중이다
- **WHEN** 수행이 heartbeat 주기보다 길어진다
- **THEN** `lease_until`이 주기적으로 뒤로 밀린다
- **AND** 수행이 끝날 때까지 `lease_until`이 지나지 않는다
- **AND** `consumer`와 `claim_count`는 바뀌지 않는다

#### Scenario: LEASE-BENCH-2 lease 의 세 배 동안 수행해도 점유가 유지된다
- **GIVEN** 워커가 lease 길이의 세 배 동안 작업을 수행한다
- **WHEN** 그동안 다른 워커들이 폴링한다
- **THEN** 점유자는 바뀌지 않고 작업은 한 번만 실행된다

#### Scenario: LEASE-BENCH-9 수행이 이벤트 처리를 붙잡아도 점유가 유지된다
- **GIVEN** 에이전트의 수행이 lease 길이의 세 배 동안 워커의 이벤트 처리를 붙잡는다
- **WHEN** 그동안 다른 워커가 폴링한다
- **THEN** `consumer`와 `claim_count`는 바뀌지 않고 작업은 한 번만 실행된다

### Requirement: 수행이 끝나면 종결 상태가 되고 점유가 풀린다
시스템은 작업 수행이 성공하거나 실패로 끝나면 작업을 종결 상태(`COMPLETED` 또는 `FAILED`)로 SHALL 전환하고 `lease_until`과 `consumer`를 비운다. 점유만 풀리고 `STARTED`로 남은 작업이 있어서는 안 된다 — 그런 작업은 아무도 다시 처리하지 않는다. 사람의 답을 기다리는 작업(`HUMAN_ASKED`)은 종결이 아니며 이 요구사항의 예외다.

#### Scenario: SVC-LEASE-03 수행이 끝나면 종결 상태가 되고 점유가 풀린다
- **GIVEN** 워커가 작업을 점유해 수행했다
- **WHEN** 수행이 성공하거나 실패로 끝난다
- **THEN** 작업은 `draft_status = 'COMPLETED'` 또는 `'FAILED'`이다
- **AND** `lease_until`과 `consumer`는 비어 있다

#### Scenario: LEASE-BENCH-10 수행이 오류로 끝난다
- **GIVEN** 워커가 작업을 수행 중이다
- **WHEN** 수행이 복구 불가능한 오류로 끝난다
- **THEN** 작업은 `FAILED`이고 `lease_until`은 비어 있다
- **AND** 이후 그 작업은 다시 실행되지 않는다

### Requirement: 점유한 워커가 죽으면 다른 워커가 회수한다
시스템은 `lease_until`이 지난 `STARTED` 점유를 다른 워커가 다시 점유할 수 있게 SHALL 한다. 회수는 만료 시한이 지나기 전에 일어나서는 안 되며, 회수될 때마다 `claim_count`가 SHALL 늘어난다. `claim_count`가 상한에 닿은 만료 점유는 다시 점유되지 않고 `FAILED`로 SHALL 종결된다. 사람의 답을 기다리는 작업(`HUMAN_ASKED`)은 회수 대상이 아니다.

#### Scenario: SVC-LEASE-04 점유한 워커가 죽으면 만료 뒤 다른 워커가 회수한다
- **GIVEN** 워커 A 가 작업을 점유한 채 강제 종료됐다
- **AND** 다른 워커 B 가 폴링 중이다
- **WHEN** A 의 `lease_until`이 지난다
- **THEN** B 가 그 작업을 점유하고 `claim_count`는 2 가 된다
- **AND** `lease_until`이 지나기 전에는 회수되지 않는다
- **AND** 회수는 lease 길이 + 폴링 주기 + 워커 기동 시간 안에 일어난다
- **AND** B 가 작업을 종결 상태까지 수행하고 점유를 푼다

#### Scenario: LEASE-BENCH-3 여러 워커가 동시에 폴링해도 한 작업은 한 워커만 점유한다
- **GIVEN** 워커 여러 개가 같은 작업 묶음을 동시에 폴링한다
- **WHEN** 모든 작업이 처리된다
- **THEN** 각 작업은 한 번만 실행되고 `claim_count`의 최댓값은 1 이다

#### Scenario: LEASE-BENCH-4 회수 상한에 닿은 작업은 실패로 종결된다
- **GIVEN** `claim_count`가 상한에 닿은 작업의 `lease_until`이 지났다
- **WHEN** 워커가 폴링한다
- **THEN** 작업은 `FAILED`로 종결되고 다시 실행되지 않는다

#### Scenario: LEASE-BENCH-5 사람의 답을 기다리는 작업은 회수하지 않는다
- **GIVEN** 작업이 `HUMAN_ASKED`이고 `lease_until`이 지났다
- **WHEN** 워커들이 폴링한다
- **THEN** 작업의 상태와 점유자는 바뀌지 않는다

### Requirement: 회수된 작업은 중복 실행되지 않는다
시스템은 점유를 잃은 워커 — 다른 워커가 이미 회수한 작업을 아직 수행 중인 워커 — 가 다음 연장 시도에서 그 사실을 알고 수행을 SHALL 중단하게 한다. 점유를 잃은 워커는 그 작업을 `FAILED`로 덮어써서는 안 된다. 회수가 작업의 완료를 추가로 만들어서는 안 된다.

#### Scenario: SVC-LEASE-05 회수가 완료를 중복시키지 않는다
- **GIVEN** 작업이 한 번 회수되어 두 워커를 거쳤다
- **WHEN** 작업이 완료된다
- **THEN** 그 작업의 `task_completed` 이벤트 수는 회수 없이 수행한 같은 서비스의 작업과 같다

#### Scenario: LEASE-BENCH-7 멈췄던 워커가 깨어나면 하던 일을 버린다
- **GIVEN** 워커 A 가 멈춘 사이 `lease_until`이 지나 워커 B 가 작업을 회수했다
- **WHEN** A 가 다시 깨어나 점유를 연장하려 한다
- **THEN** 연장은 거절되고 A 는 수행을 중단한다
- **AND** A 는 작업을 `FAILED`로 바꾸지 않으며, 작업을 끝내는 것은 B 하나뿐이다

### Requirement: 만료 시한이 없는 기존 점유는 회수하지 않는다
시스템은 `lease_until`이 비어 있는 `STARTED` 점유 — lease 를 모르는 구버전 워커가 점유했거나 lease 도입 이전에 점유된 작업 — 를 회수해서는 안 된다. 그 작업의 점유자·상태·점유 횟수는 그대로 SHALL 남는다. 구버전 워커는 lease 없이 예전과 같은 방식으로 작업을 SHALL 점유할 수 있다.

#### Scenario: SVC-LEASE-06 만료 시한이 없는 기존 점유는 회수하지 않는다
- **GIVEN** `lease_until`이 비어 있는 `STARTED` 점유가 있다
- **WHEN** lease 를 아는 워커들이 폴링하고 다른 작업을 회수하는 동안
- **THEN** 그 작업의 `consumer`, `draft_status`, `claim_count`는 그대로다

#### Scenario: LEASE-BENCH-6 구버전 워커와 섞여 돈다
- **GIVEN** lease 를 아는 워커와 모르는 워커가 함께 폴링한다
- **WHEN** 새 작업이 들어온다
- **THEN** 어느 쪽이 점유하든 작업은 정상 처리된다
- **AND** 구버전 워커가 점유한 작업은 회수되지 않는다

#### Scenario: LEASE-BENCH-8 워커가 도는 중에 lease 를 도입한다
- **GIVEN** 워커들이 작업을 처리하는 중이다
- **WHEN** 저장소에 lease 마이그레이션을 적용한다
- **THEN** 적용 전·중·후에 들어온 작업이 하나도 유실되지 않는다
- **AND** 적용 전부터 점유 중이던 작업의 점유자와 `lease_until`은 바뀌지 않는다
