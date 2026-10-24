## ADDED Requirements

### Requirement: 실행의 작업 폴더를 연다
pgpt-pro 는 `/workroom/:kind/:id` 에서 에이전트 실행의 작업 폴더를 SHALL 연다: `todo`(프로세스 단계 — cli-agent 는 `<CLI 작업 루트>/<테넌트>/<todo id>` 와 그 worktree, deepagents 는 인스턴스 폴더), `run`(cli-agent 채팅 실행), `chat`(deepagents 대화 폴더 `/workspace/.bpmn/<room>`). 단계의 "동작 보기" 와 채팅의 작업 공간 파일 카드에서 SHALL 들어갈 수 있다. 경로는 폴더 밖(`..`, 바깥을 가리키는 심볼릭 링크)으로 SHALL NOT 나간다.

#### Scenario: Claude Code 단계의 작업실
- **WHEN** 제품 개선 구현 단계에서 "작업실 열기" 를 누른다
- **THEN** 그 실행의 worktree 파일 트리, 파일 미리보기(마크다운·이미지·영상·PDF), 셸, "Claude Code 이어서" 탭이 보인다

### Requirement: 사람이 코드를 주입
작업실의 편집기는 텍스트 파일을 그 자리에서 SHALL 저장하고, 마지막으로 읽은 뒤 에이전트가 파일을 바꿨으면 덮어쓰지 않고 SHALL 거절한다(409).

#### Scenario: 규칙 주입
- **WHEN** 사람이 결정 테이블에 R2a 규칙 줄을 넣고 저장한다
- **THEN** 파일이 바뀌고 다음에 에이전트가 읽을 때 반영된다

### Requirement: 스티어링
Claude Code 실행은 그 실행의 세션(`cliagents_session_id`)을 같은 작업 폴더에서 `claude --resume` 으로 이어 연 터미널로 SHALL 지시받고, deepagents 실행은 진행 중에 `POST /chat/steer` 로 SHALL 지시받는다. 지시 입력란의 문장은 한 덩어리로 붙여 넣고 Enter 를 따로 보내 제출한다(SHALL). 터미널이 열리지 않았으면 보냈다고 SHALL NOT 알린다.

#### Scenario: 이어서 지시
- **GIVEN** Claude Code 가 구현을 끝낸 단계의 작업실이다
- **WHEN** "R2a 를 triage.py 와 테스트에 반영하고 테스트를 돌려줘" 라고 보낸다
- **THEN** 같은 세션의 Claude Code 가 코드와 테스트를 고치고, 셸에서 테스트가 7개에서 8개로 늘어 통과한다

### Requirement: 터미널과 공개 접속의 보호
터미널(PTY, node-pty + xterm.js, 스크롤백 재생·여러 명 동시 보기)은 로그인에 더해 서버 설정의 터미널 열쇠(`PRO_TERMINAL_KEY`)가 있어야 SHALL 열리며, 열쇠가 설정되지 않으면 터미널을 SHALL NOT 연다. 터미널 환경에는 서버의 비밀 값과 `CLAUDE*` 표지를 SHALL NOT 넘긴다(`GIT_CONFIG_*` 묶음은 함께 빼서 git 이 깨지지 않게 한다). 공개 주소(Cloudflare 임시 터널 등)로 들어오는 요청은 이 컴퓨터가 아닌 한 접근 암호(기본 인증 → 이후 httpOnly 쿠키)를 SHALL 거친다.

#### Scenario: 열쇠 없는 터미널
- **WHEN** 열쇠 없이 터미널 웹소켓을 연다
- **THEN** 연결이 거절된다

### Requirement: SSE 를 막는 프록시 뒤에서도 실시간
실시간 이벤트는 SSE 로 보내되, 연결 직후 `hello` 를 받지 못하면 클라이언트가 같은 이벤트를 롱폴링(`/api/events/poll`, 최근 이벤트 버퍼)으로 SHALL 받는다.

#### Scenario: Cloudflare 임시 터널
- **WHEN** Cloudflare 임시 터널(SSE 미지원)로 접속한다
- **THEN** 5초 안에 롱폴링으로 바뀌고 새 답과 알림이 새로고침 없이 나타난다
