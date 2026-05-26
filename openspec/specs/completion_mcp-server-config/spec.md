# MCP 서버 설정 명세

## Purpose
클라이언트가 시스템에서 사용 가능한 MCP 서버·도구 카탈로그를 조회하는 능력을 보장한다.

## Requirements

### Requirement: MCP 서버 카탈로그 조회
시스템은 `GET /mcp-tools` 요청에 대해 사용 가능한 MCP 서버 항목들로 구성된 카탈로그를 SHALL 반환한다.

#### Scenario: 카탈로그 조회 성공
- **WHEN** 클라이언트가 `GET /mcp-tools`를 호출한다
- **THEN** 시스템은 MCP 서버 이름을 키로 하는 `mcpServers` 객체를 반환한다
- **AND** 각 서버 항목은 stdio 실행 형식(`command`/`args`) 또는 URL 전송 형식(`type`/`url`/`transport`) 중 하나의 구조를 가진다

#### Scenario: MCP 설정을 로드할 수 없음
- **GIVEN** MCP 설정 정의를 찾을 수 없거나 형식이 손상되어 있다
- **WHEN** 클라이언트가 `GET /mcp-tools`를 호출한다
- **THEN** 시스템은 `404` 상태와 `Failed to load MCP config` 메시지를 반환한다
