# 에이전트 작업실 명세

## Purpose
에이전트 실행이 남긴 작업 폴더를 브라우저에서 열어 산출물을 보고, 사람이 코드를 주입하고, 실행 중이거나 끝난 에이전트에게 방향을 지시하며(Claude Code 세션 이어서, deepagents steer), 공개 주소로도 안전하게 쓸 수 있도록 보장한다. 터미널 구조는 agent-share 를 본떴다.

## Requirements
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

### Requirement: 작업실 접근 권한
작업실(파일·원본·편집·게시·스티어링·터미널)은 그 실행의 담당자(todolist.user_id), 프로세스 인스턴스 참여자, 대화 작업실이면 그 대화의 주인, 테넌트 관리자에게만 SHALL 열리고, 그 밖의 사람에게는 403 으로 SHALL 거절한다.

#### Scenario: 남의 작업실
- **WHEN** 그 실행과 관계없는 사람이 작업실 주소를 연다
- **THEN** "이 작업실을 볼 권한이 없어요" 가 뜨고 파일·티켓 요청은 403 이다

### Requirement: 터미널 연결
터미널(PTY, node-pty + xterm.js, 스크롤백 재생·여러 명 동시 보기)은 별도 열쇠를 묻지 SHALL NOT 않고, 페이지가 방금 받은 일회용 티켓(`POST /api/workroom/:kind/:id/ticket`: 60초, 한 번 쓰면 없어짐, 사람·작업실·모드에 묶임)으로만 SHALL 열린다. 웹소켓 주소에 로그인 토큰을 SHALL NOT 싣고, 이 앱의 출처(요청 Host·전달된 Host·공개 주소·이 앱의 터널 도메인)가 아닌 페이지의 연결은 SHALL 거부한다. 터미널 환경에는 서버의 비밀 값과 `CLAUDE*` 표지를 SHALL NOT 넘긴다(`GIT_CONFIG_*` 묶음은 함께 뺀다).

#### Scenario: 티켓 없는 연결
- **WHEN** 티켓 없이, 또는 다른 사이트의 페이지에서 터미널 웹소켓을 연다
- **THEN** 각각 401, 403 으로 거절된다

### Requirement: 공개 접속
공개 주소(Cloudflare 임시 터널 등)로 들어오는 요청은 이 컴퓨터가 아닌 한 접근 암호(기본 인증 → 이후 httpOnly 쿠키)를 SHALL 거친다.

#### Scenario: 공개 주소의 작업실
- **WHEN** 담당자가 접근 암호를 넣고 공개 주소로 작업실을 연다
- **THEN** Claude Code 터미널이 "연결됨" 으로 열린다

### Requirement: agent-share 와 같은 화면
작업실은 agent-share 처럼 에이전트의 터미널(Claude Code 실행이면 그 세션을 이어서, 아니면 셸)이 주화면이고 작업 파일 목록은 오른쪽 패널이어야 SHALL 한다. 파일은 터미널 자리에서 열리고(✕ 터미널로 돌아감, 터미널 연결은 유지) Claude Code 작업실에서는 "@ Claude" 로 그 파일을 입력에 SHALL 붙인다. deepagents 실행에는 터미널 아래 스티어링 입력이 SHALL 있다.

#### Scenario: 파일을 보고 터미널로 돌아가기
- **WHEN** 담당자가 작업실 오른쪽 목록에서 `CLAUDE.md` 를 누른다
- **THEN** 터미널 자리에 마크다운 미리보기가 열리고, "✕ 터미널" 을 누르면 연결이 끊기지 않은 Claude Code 화면으로 돌아온다

### Requirement: 공유 폴더와 같은 파일 보기
작업실의 파일은 공유 폴더 미리보기와 같은 보기 부품(`components/files/FileView.vue`)으로 SHALL 보여 준다. 텍스트·코드는 그 자리에서 고쳐 저장하고, 마크다운은 미리보기/편집, 이미지·영상·소리는 바로, 한글·워드·엑셀·파워포인트·PDF 는 이음오피스(읽기 전용), CAD·SVG·PSD 는 ArtCraft 로 연다. 편집기는 저장소에서만 문서를 받으므로 작업실 파일은 내용 해시 이름으로 `files` 버킷에 올린 사본(`POST …/publish`)을 SHALL 쓴다.

#### Scenario: 작업실의 한글 문서
- **WHEN** 담당자가 작업실 목록의 `.hwpx` 파일을 누른다
- **THEN** 사본이 저장소에 올라가고 터미널 자리에 이음오피스 한글 편집기가 읽기 전용으로 열린다

### Requirement: SSE 를 막는 프록시 뒤에서도 실시간
실시간 이벤트는 SSE 로 보내되, 연결 직후 `hello` 를 받지 못하면 클라이언트가 같은 이벤트를 롱폴링(`/api/events/poll`, 최근 이벤트 버퍼)으로 SHALL 받는다.

#### Scenario: Cloudflare 임시 터널
- **WHEN** Cloudflare 임시 터널(SSE 미지원)로 접속한다
- **THEN** 5초 안에 롱폴링으로 바뀌고 새 답과 알림이 새로고침 없이 나타난다
