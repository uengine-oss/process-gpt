# CLI 에이전트 회사 API 키 명세

## Purpose
cli-agent는 Claude Code · Codex CLI로 업무와 채팅을 처리한다. 지금까지는 한 사람이 발급한 Claude 구독 토큰 하나로
모든 사람의 업무와 채팅을 실행했다. Anthropic 약관은 구독 자격 증명을 여러 사람이 나눠 쓰거나 사용자 대신 실행하는 것을 금지하고,
회사가 직접 발급한 API 키를 그 회사의 승인된 사용자가 쓰는 것은 허용한다. 그래서 회사(테넌트) 관리자가 자기 회사의
API 키를 설정 화면에 입력하고, cli-agent는 실행할 때마다 그 키로 CLI를 실행한다(결정 D-1111-14).

키는 Supabase Vault에 암호화해 저장하고 화면에는 다시 보여 주지 않는다. 운영 DB에 필요한 테이블과 함수는 사람이 적용한다.

시나리오 ID: `F-CK-*`는 process-gpt-vue3 `playwright/e2e/cli-agent-keys`(튜토리얼 VM), `SEC-CK-*`는 VM DB에서 실제
JWT 역할로 확인한 보안 검사, `CLI-CK-*`는 process-gpt-cli-agent의 테스트다.

## Requirements

### Requirement: 관리자만 회사 API 키를 넣고 지운다
설정 화면은 회사 관리자에게만 「CLI 에이전트 API 키」 칸을 표시해야 한다(SHALL). 관리자는 Claude Code(Anthropic) · Codex(OpenAI) 키를 입력하거나 삭제할 수 있다. 입력한 키는 다시 표시해서는 안 되며(SHALL NOT), 상태(설정됨 · 끝 네 자리 · 변경한 사람 · 시각)만 표시해야 한다(SHALL). 관리자가 아닌 사용자는 그 칸을 볼 수 없고, 서버도 해당 사용자의 저장 요청을 거절해야 한다(SHALL).

#### Scenario: F-CK-02 관리자가 키를 넣는다
- **GIVEN** 회사 관리자가 설정의 「CLI 에이전트 API 키」를 연다
- **WHEN** Anthropic 키를 넣고 저장한다
- **THEN** 상태가 「설정됨 · ••••끝4자리 · 이름 · 시각」으로 바뀌고 입력칸은 비워진다
- **AND** 화면 어디에도 키 전체가 보이지 않는다

#### Scenario: F-CK-05 관리자가 아닌 사용자
- **GIVEN** 관리자가 아닌 사용자다
- **WHEN** 설정을 연다
- **THEN** 「CLI 에이전트 API 키」 칸이 없고, 주소로 열어도 계정 탭으로 돌아간다
- **AND** 서버에 직접 저장 · 조회를 요청해도 거절된다

#### Scenario: F-CK-06 키를 지운다
- **WHEN** 관리자가 지우기를 한 번 확인한다
- **THEN** 상태가 「설정 안 됨」이 된다

### Requirement: 키는 암호화된 저장소에만 있고 cli-agent만 꺼낸다
시스템은 키를 Supabase Vault에만 저장해야 하며(SHALL), 평문은 어느 테이블에도 남겨서는 안 된다(SHALL NOT). 상태 조회 시 같은 회사 사용자에게는 설정 여부만 제공하고, 끝 네 자리 · 변경한 사람 · 시각은 관리자에게만 제공해야 한다(SHALL). 평문 조회는 서비스 롤(cli-agent)만 할 수 있어야 한다(SHALL). 삭제된 회사의 키는 조회해서는 안 된다(SHALL NOT).

#### Scenario: SEC-CK-01 역할별 접근
- **GIVEN** VM DB에서 관리자 · 일반 사용자 · 익명 · 서비스 롤로 각각 요청한다
- **THEN** 저장은 관리자만, 평문 조회는 서비스 롤만 성공하고, 테이블을 직접 읽는 요청은 모두 거절된다
- **AND** Vault에는 암호문만 있고 public 스키마 어디에도 평문이 없다

### Requirement: cli-agent는 실행마다 그 회사 키로 CLI를 돌린다
cli-agent는 업무와 채팅을 실행할 때마다 해당 회사의 키를 조회해야 하며(SHALL), 해당 실행의 CLI 환경에만 넣어야 한다(SHALL). Claude Code는 회사 키가 있으면 해당 실행 환경에서 개인 구독 토큰을 제거해야 한다(SHALL). 키는 로그 · 실행 이벤트 · 실행 기록 · 작업 폴더 · 보관 파일 어디에도 남겨서는 안 된다(SHALL NOT).

#### Scenario: CLI-CK-01 회사 키로 돈다
- **GIVEN** 회사가 Anthropic 키를 넣었다
- **WHEN** 그 회사 사용자가 Claude Code로 업무나 채팅을 돌린다
- **THEN** CLI 환경에는 회사 키가 있고 개인 구독 토큰은 없다
- **AND** 서버 프로세스 전체 환경은 바뀌지 않는다
- **AND** 키 문자열은 로그 · 이벤트 · 작업 폴더 · 보관 파일에 없다

### Requirement: 채팅은 회사 키가 없으면 돌지 않는다
채팅에서 고른 CLI의 회사 키가 없거나 확인할 수 없으면, cli-agent는 공용 자격 증명으로 대신 실행해서는 안 되며(SHALL NOT), 요청을 거절한다. 키가 없으면 관리자에게 설정을 안내하는 오류(`company_key_required`), 확인에 실패하면 잠시 후 다시 시도하라는 오류(`company_key_check_failed`)를 보내야 한다(SHALL). 화면에는 회사 키가 있는 CLI만 채팅 선택지로 표시해야 한다(SHALL). 업무는 회사 키가 없으면 지금처럼 파드 자격 증명으로 실행하고, 실행 기록에 그 사실을 남겨야 한다(SHALL).

#### Scenario: CLI-CK-02 회사 키 없는 채팅은 거절
- **GIVEN** 회사가 OpenAI 키만 넣었다
- **WHEN** Claude Code로 채팅을 보낸다
- **THEN** CLI는 실행되지 않고 오류 `company_key_required` 하나만 온다

#### Scenario: F-CK-07 키가 있는 CLI만 고를 수 있다
- **GIVEN** 회사가 OpenAI 키만 넣었다
- **WHEN** 새 대화에서 「CLI 코딩 에이전트」를 고른다
- **THEN** CLI 선택지에는 Codex만 있다
