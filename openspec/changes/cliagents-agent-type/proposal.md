## Why

현재 ProcessGPT 에서 "에이전트에게 업무를 맡긴다"를 제대로 수행하는 오케스트레이션은 `deepagents` 하나뿐이고, 이는 LangChain deepagents 런타임에 강하게 묶여 있다. 그래서 Claude Code, Codex 처럼 이미 시장에서 검증된 CLI 코딩 에이전트의 실행 품질·툴체인·스킬 생태계를 ProcessGPT 업무 실행에 그대로 쓸 수 없다.

`cliagents` 라이브러리는 CLI 에이전트별 관례(설치 감지, 지시문 파일, 스킬 배치, MCP 등록)를 하나의 전략 객체로 수렴시켜 두었으므로, 이를 기반으로 "CLI 에이전트" 오케스트레이션을 추가하면 사용자가 업무 단위로 Claude / Codex 를 골라 위임할 수 있게 되고, 새로운 CLI 에이전트가 나와도 provider 하나만 추가하면 ProcessGPT 전체에 노출된다.

## What Changes

- `cliagents` 라이브러리를 `services/cliagents` 서브모듈로 추가하고, ProcessGPT 에이전트 타입 서비스는 별도 저장소(`services/cli-agent`)로 분리해 서브모듈로 등록한다.
- `cliagents` 에 **비대화형(headless) 실행 표면**을 새로 추가한다. 지금은 대화형 PTY 실행만 지원하므로, 업무 위임을 위해 "프롬프트를 주고 구조화된 이벤트 스트림과 최종 결과를 받는" 표면이 provider 계약으로 들어간다.
- 새 오케스트레이션 값 `cliagents` 를 도입한다. 업무/에이전트 설정에서 이 오케스트레이션을 고르면 추가로 실행 CLI(`claude-code` / `codex`)와 모델·권한 옵션을 선택한다. **CLI 값은 별도 필드에 저장되며, 오케스트레이션 목록에 CLI 별 항목을 늘리지 않는다.**
- 워크아이템 폴링 → 컨텍스트/프롬프트 구성 → CLI headless 실행 → 진행 이벤트 스트리밍 → 산출물·결과 저장까지 `deepagents` 와 동일한 업무 실행 계약을 제공한다(초안/완료 모드, 취소, 실패 보고 포함).
- 테넌트 스킬·시스템 스킬·git 스킬을 선택된 CLI 의 관례에 맞는 프로젝트 아티팩트(지시문 파일, 스킬 디렉터리)로 주입한다. 같은 스킬 자산이 두 CLI 모두에서 동작한다.
- ProcessGPT 도구(프로세스·폼·메멘토·오피스 등)를 MCP 서버로 브리지 설치해 CLI 에이전트가 기존 도구를 그대로 쓰게 한다.
- 채팅 스트리밍(`/chat/stream`, 재접속), 사용자 확인(HITL) 후 재개, 워크스페이스 파일 산출물 실시간 전달·다운로드, 결정적 재실행/되돌리기를 `deepagents` 와 동등하게 제공한다.
- CLI 미설치·미인증 상황에서 다른 에이전트로 조용히 대체하지 않고, 설치 안내를 담은 명확한 실패로 보고한다.

## Capabilities

### New Capabilities

- `cliagents_workitem-task-execution`: 워크아이템을 선택된 CLI 에이전트에게 위임해 실행하고, 초안/완료 모드에 맞는 결과와 실패·취소를 보고하는 계약.
- `cliagents_cli-selection-availability`: 오케스트레이션 선택 시 실행 CLI(claude-code/codex)와 모델·권한 옵션을 지정하고, 설치·인증 가용성을 조회·검증하는 계약.
- `cliagents_skill-artifact-provisioning`: 테넌트/시스템/git 스킬과 업무 지시문을 선택된 CLI 관례에 맞는 프로젝트 아티팩트로 주입하고 조회·업로드·삭제하는 계약.
- `cliagents_mcp-tool-bridge`: ProcessGPT 도구를 MCP 서버로 등록해 CLI 에이전트에 노출하고, 등록 범위와 멱등성을 보장하는 계약.
- `cliagents_chat-streaming-session`: 대화형 채팅 실행의 SSE 진행 이벤트, 재접속 이어보기, 대화 연속성(세션 이어가기) 계약.
- `cliagents_human-in-the-loop`: 실행 중 사용자 확인/추가입력 요청을 발행하고, 응답을 받아 중단 지점부터 재개하는 계약.
- `cliagents_workspace-file-artifacts`: 실행 단위 워크스페이스 격리, 생성/수정 파일의 실시간 통지, 산출물 다운로드 계약.
- `cliagents_deterministic-replay-undo`: 실행 중 발생한 외부 변경 작업을 기록해 동일 조건에서 재실행하거나 되돌리는 계약.

### Modified Capabilities

없음. 기존 `deepagents_*` 스펙의 요구사항은 변경하지 않고, 동일한 사용자 가치를 새 오케스트레이션에서 별도 계약으로 제공한다.

## Impact

- **신규 서비스**: 서브모듈 2개가 추가된다. `services/cliagents`(라이브러리, 의존성 없음)와 `services/cli-agent`(에이전트 타입 서비스: 워크아이템 폴링 + HTTP API). 서비스는 라이브러리를 git 의존성으로 참조한다.
- **업스트림 라이브러리 변경**: `cliagents` 에 headless 실행 표면과 이벤트 정규화가 추가된다. 기존 대화형/아티팩트/브리지 표면의 계약은 유지한다.
- **프론트엔드**: 오케스트레이션 선택 목록에 `cliagents` 항목과 CLI 선택 필드, 관련 다국어 문구가 추가된다. 업무 실행·모니터·채팅 화면은 새 오케스트레이션 값을 유효한 값으로 취급해야 한다.
- **데이터**: 워크아이템에 기록되는 오케스트레이션 값에 `cliagents` 가 추가되고, 선택된 CLI·모델·권한 설정을 담는 필드가 필요하다.
- **배포/운영**: 새 서비스 컨테이너 이미지에 CLI 실행 파일과 인증 정보가 있어야 하며, 게이트웨이에 새 서비스 경로 라우팅이 추가된다. CLI 인증 실패·미설치는 운영 관측 대상이다.
- **비용/보안**: CLI 에이전트는 자체 계정·키로 과금되고 파일시스템·셸 접근 권한을 가지므로, 실행 권한 수준과 워크스페이스 격리가 설정 계약에 포함된다.
