## Why

에이전트가 워크아이템을 수행하다 죽거나(파드 사망·lease 만료로 다른 워커가 재점유), 사람에게 묻고 멈췄다가 답을 받아 다시 집힐 때, 지금은 세 서비스(deepagents, cli-agent, codex) 모두 **이미 끝낸 단계를 처음부터 반복**한다. 2026-10-06 실측(E1–E4)에서 다음이 확인됐다.

- 재점유 사실을 알려 주는 신호(`claim_count`)가 행에 실려 오지만 아무도 읽지 않는다.
- deepagents는 크래시 재점유 때 완료된 외부 호출을 3/3 다시 호출했다.
- cli-agent는 크래시 재점유 때 완료된 단계를 2/2 다시 실행했고, 사람이 답하면 저장해 둔 세션을 쓰지 않고 답 원문 대신 요약본으로 새로 시작했다.
- codex는 같은 파드에서 재점유해도 같은 지시를 다시 넣어 완료 단계를 1/2 반복했다.
- 사람 답변 재개와 반려 재작업은 행 모양이 같아 실행기가 구분할 수 없다.

세 프레임워크 모두 중단 지점까지의 기록은 남긴다. 빠진 것은 "지금이 재개이고, 왜 재개인지"를 실행기에 알려 주는 표준 신호다. 재개 판단을 서비스마다 따로 만들지 않고 SDK가 표준으로 제공하면, 새 에이전트도 같은 방식으로 재개를 얻는다.

## What Changes

- SDK가 워크아이템 실행기에 **재개 정보**를 넘긴다: 재개 사유(`fresh` / `reclaim` / `human_answer` / `revision`), 점유 회차, 재개 키(todo id), 사람 답 원문.
  - 재점유 판정은 점유 RPC가 이미 돌려주는 `claim_count`를 쓴다.
  - 사람 답변과 반려는 화면이 feedback 항목에 남긴 구분 표시(`kind`)로 가린다. 표시가 없는 과거 항목은 반려로 본다.
  - 재개 정보를 읽지 않는 실행기는 지금과 똑같이 동작한다(하위 호환).
- 화면(process-gpt-vue3)이 답을 저장할 때 feedback 항목에 `kind`를 함께 남긴다: 질문 카드 답은 `human_answer`, 결과에 대한 피드백·반려는 `revision`.
- 각 서비스는 재개 사유에 따라 프레임워크별 재개 방식 하나를 고른다.
  - deepagents: 재점유이고 그래프가 끝나지 않았으면 새 메시지 없이 마지막 체크포인트부터 이어서 실행한다.
  - deepagents: 지속 체크포인터(Postgres)가 설정됐는데 초기화가 실패하면 메모리 저장으로 조용히 넘어가지 않고 기동을 실패시킨다.
  - cli-agent: 실행이 시작되자마자 CLI 세션 ID를 작업 공간에 저장하고, 재점유 때 그 세션으로 이어서 실행한다. 사람 답변이면 멈췄던 세션으로 이어 가고 답 원문을 그대로 넣는다.
  - codex: 재점유 때 같은 지시를 다시 넣지 않고 "중단된 지점부터, 완료된 단계는 다시 하지 말 것" 지시로 이어 간다.

## Capabilities

### New Capabilities
- `agent-sdk_workitem-resume-signal`: SDK가 워크아이템 실행기에 재개 사유·회차·키·사람 답 원문을 표준 형태로 넘기는 계약, 그리고 답을 저장할 때 feedback에 남기는 구분 표시.
- `deepagents_workitem-checkpoint-resume`: deepagents가 크래시 재점유 뒤 마지막 그래프 체크포인트부터 이어 가는 행위와, 지속 체크포인트 저장소 실패를 숨기지 않는 운영 계약.
- `cli-agent_workitem-session-resume`: cli-agent가 실행 시작 직후 CLI 세션을 기록하고, 크래시 재점유·사람 답변 때 그 세션으로 이어 가는 행위.
- `codex_workitem-resume`: codex가 크래시 재점유 때 같은 지시 대신 이어서 지시로 턴을 여는 행위.

### Modified Capabilities
(없음 — 사람 답변 원문으로 interrupt 지점부터 잇는 deepagents 동작은 `deepagents_workitem-human-input`에 이미 정의돼 있고, 이번 변경은 그 요구사항을 바꾸지 않는다)

## Impact

- process-gpt-agent-sdk: 워크아이템 실행 문맥에 재개 정보가 추가된다(추가 필드, 기존 필드 변경 없음). 공개 API에 재개 정보 해석 함수와 표준 "이어서" 지시 문구가 추가된다.
- process-gpt-vue3: 질문 카드 답변·결과 피드백 저장 시 feedback 항목에 `kind` 필드가 추가된다. 기존 소비자는 모르는 필드를 무시한다.
- process-gpt-deepagents, process-gpt-cli-agent, process-gpt-codex: 재개 정보를 읽어 재개 입력을 고른다. 재개 정보가 없는(구버전 SDK) 경우 기존 동작을 유지한다.
- 운영: deepagents는 `DB_*`가 설정됐는데 체크포인터 초기화가 실패하면 기동하지 않는다(이전에는 메모리 저장으로 기동해 HITL이 반복됐다).
- 데이터베이스 스키마 변경 없음.
