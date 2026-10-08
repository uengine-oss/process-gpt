## ADDED Requirements

### Requirement: RE-1 크래시 재점유 때 이어서 지시로 턴을 연다
재개 사유가 `reclaim`이면 codex는 같은 작업 지시를 다시 넣지 않고, "직전 실행이 중단되었다, 완료한 단계는 다시 하지 말고 완료되지 않은 단계부터 이어서 하라"는 지시로 턴을 열어야 한다(SHALL). 원래 작업 지시는 그 뒤에 참고용으로 붙인다(SHALL). 그래야 thread를 찾지 못해 새로 시작하는 경우에도 할 일을 알 수 있다. 이어 갈 thread를 찾는 워크스페이스 키는 재개 여부와 관계없이 같아야 한다(MUST).

#### Scenario: RE-1.6 같은 파드에서 재점유
- **WHEN** codex가 1단계를 끝낸 뒤 2단계 중에 죽고, 같은 파드에서 `reclaim`으로 다시 집힌다
- **THEN** 턴은 이어서 지시로 시작하고 원래 지시가 참고로 붙으며, 1단계는 다시 실행되지 않는다

#### Scenario: RE-1.7 재개라도 워크스페이스 키는 같다
- **WHEN** 같은 작업이 `fresh`와 `reclaim`으로 각각 집힌다
- **THEN** 두 경우 모두 같은 워크스페이스 키(같은 thread)를 쓴다

### Requirement: RE-3 재개 정보가 없으면 이전 동작을 유지한다
실행 문맥에 재개 정보가 없거나 사유가 `fresh`·`revision`이면, codex는 이번 변경 이전과 같은 작업 지시로 턴을 열어야 한다(SHALL).

#### Scenario: RE-3.1 구버전 SDK와 반려
- **WHEN** `resume`이 없거나 `fresh`·`revision`인 작업이 집힌다
- **THEN** 턴의 지시는 이번 변경 이전과 같다
