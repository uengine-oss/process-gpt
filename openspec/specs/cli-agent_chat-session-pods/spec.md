# CLI 에이전트 대화별 파드 채팅 명세

## Purpose
CLI 에이전트(코덱스, cli-agent의 Claude Code · Codex)는 CLI 프로세스와 작업 폴더를 대화마다
따로 두어야 하므로 대화마다 런너 파드를 띄운다. 세션 라우터(process-gpt-session-router)가
대화 id로 파드를 찾거나 만들고, 30분 동안 쓰지 않으면 회수한다(결정 D-1111-10).

새 파드가 준비되기까지 16~40초가 걸린다. 이 명세는 사용자에게 대기 시간을 알리고,
로그인하지 않은 요청이 파드를 띄우지 못하게 하며, 진행 중인 답변에 대한 재접속 · 중지 ·
방향 바꾸기가 그 대화의 파드에 닿게 하는 계약이다. 또 cli-agent가 대화별 파드에서 채팅을
받을 때 CLI를 고르는 규칙과, 파드가 회수된 뒤에도 유지되는 항목을 정한다.

서버형 에이전트(딥 에이전트)는 대화별 파드를 쓰지 않는다(`agent-sdk_chat-owner-forwarding`).

시나리오 ID: `RT-*`는 라우터 저장소의 시험(`go test ./...`), `RT-KIND-*`는 kind 클러스터에서
실제 파드로 확인한 것, `CLI-*`는 cli-agent 저장소의 시험과 로컬 실행, `UI-*`는 화면 시험이다.

## Requirements

### Requirement: 로그인 토큰을 확인하기 전에는 파드를 만들지 않는다
라우터는 채팅 경로 요청의 로그인 토큰(`Authorization: Bearer …`, 없으면 본문 `user_jwt`)을 파드를 찾거나 만들기 전에 SHALL 확인한다. 토큰이 없거나 유효하지 않으면 401로 SHALL 답하고 파드를 만들지 않는다(SHALL NOT). 확인 수단이 전혀 설정되지 않았으면 라우터는 SHALL 시작하지 않는다.

#### Scenario: RT-KIND-01 토큰이 없으면 401이고 파드가 생기지 않는다
- **GIVEN** 런너 파드가 하나도 없다
- **WHEN** 토큰 없이 새 대화의 채팅 요청을 보낸다
- **THEN** 곧바로 401 「인증 토큰이 필요합니다」를 받는다
- **AND** 런너 파드 수는 그대로 0 이다

#### Scenario: RT-KIND-02 틀린 토큰도 401이고 파드가 생기지 않는다
- **WHEN** 서명이 틀린 토큰으로 채팅 요청을 보낸다
- **THEN** 401 「인증 토큰이 유효하지 않습니다」를 받고 런너 파드가 생기지 않는다

### Requirement: 파드가 준비되는 동안 「준비 중」을 알린다
라우터는 대화의 파드가 아직 준비되지 않은 채팅 요청에 곧바로 실시간 스트림을 열고, 준비될 때까지 「준비 중」(경과 시간 포함)을 2초마다 SHALL 보낸다. 준비되면 「준비됨」을 보낸 뒤 에이전트의 답변을 같은 스트림으로 SHALL 이어 보낸다. 파드가 준비되지 못하거나 에이전트가 오류로 답하면 오류 이벤트로 SHALL 알린다. 이미 준비된 파드의 요청에는 「준비 중」을 보내지 않는다(SHALL NOT).

#### Scenario: RT-KIND-03 새 대화는 0초에 「준비 중」을 받고, 준비되면 답변이 이어진다
- **GIVEN** 기동에 약 15초가 걸리는 런너 틀이 있다
- **WHEN** 새 대화의 채팅 요청을 보낸다
- **THEN** 첫 이벤트는 0초에 도착하는 「준비 중」이며 이후 2초마다 이어진다
- **AND** 약 15초 뒤 「준비됨」이 오고, 같은 스트림으로 답변이 끝(done)까지 이어진다

#### Scenario: RT-KIND-04 이미 떠 있는 파드에는 「준비 중」이 없다
- **GIVEN** 대화의 파드가 준비되어 있다
- **WHEN** 같은 대화에 다시 묻는다
- **THEN** 「준비 중」 이벤트 없이 곧바로 답변이 온다

#### Scenario: RT-03 파드가 끝내 준비되지 않으면 오류로 알린다
- **WHEN** 최대 대기 시간 안에 파드가 준비되지 않는다
- **THEN** 스트림은 「에이전트를 준비하지 못했습니다. 잠시 뒤 다시 시도해 주세요.」 오류 이벤트(runner_start_timeout)로 끝난다

#### Scenario: RT-04 기다리던 사용자가 떠나도 파드는 계속 준비된다
- **WHEN** 첫 요청을 보낸 사용자가 준비 중에 연결을 끊는다
- **THEN** 파드는 지워지지 않고 준비를 마친다(다음 요청은 바로 연결된다)

### Requirement: 파드가 없는 대화의 재접속 · 중지 · 방향 바꾸기는 파드를 만들지 않는다
라우터는 파드가 없는 대화의 재접속 · 중지 · 방향 바꾸기 요청에 파드를 만들지 않고(SHALL NOT), 에이전트에 진행 중인 답변이 없을 때와 같은 응답을 SHALL 보낸다(재접속 `{"active":false}`, 중지 `{"stopped":false,"reason":"no_active_turn"}`, 방향 바꾸기 409 `no_active_turn`).

#### Scenario: RT-KIND-05 방을 다시 열어도 파드가 뜨지 않는다
- **GIVEN** 대화 R의 파드가 없다
- **WHEN** 재접속 · 중지 · 방향 바꾸기 요청을 보낸다
- **THEN** 각각 「진행 중인 답변 없음」으로 곧바로 답하고 런너 파드 수는 그대로다

### Requirement: 방향 바꾸기는 그 대화의 파드로 간다
라우터는 방향 바꾸기(`/chat/steer`, 또는 `action: steer`인 채팅 요청)를 그 대화의 파드로 SHALL 보낸다.

#### Scenario: RT-KIND-06 진행 중인 답변에 보낸 방향 바꾸기가 접수된다
- **GIVEN** 대화 R의 파드가 답변을 쓰고 있다
- **WHEN** 대화 R에 방향 바꾸기를 보낸다
- **THEN** 「받았다」(accepted)로 답하고, 답변 스트림에 「받았다」 이벤트가 나온다

### Requirement: cli-agent 채팅은 사용자가 고른 CLI로만 실행된다
cli-agent는 채팅 요청의 `metadata.agent_cli`(`claude-code` | `codex`)로 CLI를 SHALL 고른다. 고르지 않았으면 다른 CLI로 대신 실행하지 않고(SHALL NOT) `cli_not_selected` 오류와 사용 가능한 CLI 목록을 SHALL 보낸다. 고른 CLI가 설치되지 않았으면 `cli_unavailable`로 SHALL 알린다.

#### Scenario: CLI-01 CLI를 고르지 않으면 아무것도 실행하지 않는다
- **WHEN** `metadata.agent_cli` 없이 채팅을 보낸다
- **THEN** 오류 이벤트 `cli_not_selected`와 사용 가능한 CLI 목록을 받고, CLI는 실행되지 않는다

#### Scenario: CLI-02 Claude Code로 한 턴, 다음 턴은 같은 CLI 세션을 잇는다
- **WHEN** `agent_cli=claude-code`로 묻고, 같은 대화에 다시 묻는다
- **THEN** 첫 답변은 사용자 메시지에 응답하고
- **AND** 두 번째 턴은 첫 턴의 CLI 세션을 이어서(--resume) 실행된다

### Requirement: 런너 파드는 업무를 가져오지 않고, 회수된 뒤에도 대화가 이어진다
cli-agent 런너 파드는 업무(todolist)를 가져오지 않는다(SHALL NOT)(`CLIAGENTS_PROCESS_POLLING=false`). 턴 실행 전후에 작업 폴더와 CLI 세션 기록을 세션 보관소에서 SHALL 복원 · 저장하고, 산출물은 다운로드 링크로 답변에 SHALL 싣는다. CLI 자격 증명 파일은 보관하지 않는다(SHALL NOT). 상태 확인(`/health`)은 턴이 실행되는 동안 `busy=true`를 SHALL 알린다.

#### Scenario: CLI-03 턴이 실행되는 동안 busy, 끝나면 해제된다
- **WHEN** 채팅 턴이 실행되는 동안과 끝난 뒤 `/health`를 본다
- **THEN** 실행 중에는 `busy=true`, 끝난 뒤에는 `busy=false`다

#### Scenario: CLI-04 계정 사용량 이벤트는 화면으로 가지 않는다
- **WHEN** Claude Code가 사용량 한도 이벤트(rate_limit_event)를 발생시킨다
- **THEN** 채팅 스트림에 그 이벤트가 나오지 않는다

### Requirement: 화면은 「준비 중」을 답변 자리에 표시한다
채팅 화면(포털과 휴대폰 웹)은 「준비 중」 이벤트를 받는 동안 답변이 나올 자리에 「에이전트를 준비하고 있어요 · N초」를 SHALL 표시하고, 「준비됨」 · 첫 글자 · 끝 · 오류 · 중지가 오면 SHALL 지운다. 「준비 중」이 오지 않는 대화(이미 떠 있는 파드, 딥 에이전트)에는 표시하지 않는다(SHALL NOT).

#### Scenario: UI-01 포털 채팅의 준비 중 표시
- **GIVEN** 에이전트 스트림이 「준비 중」 두 번 → 「준비됨」 → 답변 순서로 온다
- **WHEN** 포털 채팅에서 질문한다
- **THEN** 답변 자리에 「에이전트를 준비하고 있어요」가 보이고, 답변 글자가 오면 사라진다

#### Scenario: UI-02 휴대폰 웹의 준비 중 표시
- **GIVEN** 같은 스트림이다
- **WHEN** 휴대폰 웹(/m/) 채팅에서 질문한다
- **THEN** 같은 표시가 보였다가 답변이 오면 사라진다

### Requirement: 채팅에서 CLI 에이전트를 고를 수 있다
채팅 화면은 대화의 에이전트로 「CLI 에이전트」를 고를 수 있게 하고, 그때만 Claude Code / Codex 선택 항목을 SHALL 표시하며, 고른 값을 `metadata.agent_cli`로 SHALL 보낸다.

#### Scenario: UI-03 CLI 에이전트로 묻는다
- **WHEN** 대화의 에이전트를 CLI 에이전트로 바꾸고 Claude Code를 고른 뒤 묻는다
- **THEN** 요청은 `/process-gpt-cli-agent/chat/stream`으로 가고 본문 `metadata.agent_cli`는 `claude-code`다
