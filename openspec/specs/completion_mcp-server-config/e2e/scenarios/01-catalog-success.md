# E2E 시나리오 01: MCP 서버 카탈로그 조회 성공

## 메타데이터
- 스위트 슬러그: `completion_mcp-server-config`
- 원본 명세 ID: `completion_mcp-server-config`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `GET /mcp-tools 응답이 mcpServers 카탈로그를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_mcp-server-config/spec.md`

## 목적
gateway(nginx)를 통해 외부 클라이언트가 `GET /completion/mcp-tools`를 호출했을 때 completion 서비스가 `services/completion/mcp.json`에 정의된 MCP 서버 카탈로그를 그대로 노출하는지 검증한다. 응답이 단순한 배열이 아닌 `mcpServers` 키 구조의 객체이며, 각 항목이 stdio 실행 형식(`command`/`args`) 또는 URL 전송 형식(`type`/`url`/`transport`) 중 하나의 형태를 갖는지 확인하여 다른 서비스(에이전트 실행기 등)가 카탈로그 계약에 의존할 수 있도록 한다. 본 명세는 비-사용자 대상 백엔드 프로토콜 계약이므로 브라우저 UI 동작 대신 Playwright `request` API를 사용해 게이트웨이 경유 요청을 수행한다(User-Action Rule 단서 조항).

## 사전 조건
- `docker-compose.e2e.yml` 스택이 기동되어 있고, 다음 컨테이너가 healthy 상태이다: `process-gpt-e2e-db`, `process-gpt-e2e-kong`, `process-gpt-e2e-completion`, `process-gpt-e2e-gateway`.
- `services/completion/mcp.json`이 정상적인 JSON 형식으로 존재한다(기본 저장소 상태).
- gateway가 `http://localhost:8088/completion/` 접두어를 `http://completion:8000/`로 프록시한다(`openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` 재사용).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `mcp.json` | seed/fixture | `services/completion/mcp.json` | 컨테이너 빌드 시점에 이미지에 포함되는 카탈로그 원본. 별도 seed 작업 불필요 |
| gateway 라우트 | route | `GET http://localhost:8088/completion/mcp-tools` | 브라우저와 동일한 프록시 경로로 백엔드를 호출 |

## 절차
1. Playwright `request` 컨텍스트로 `GET http://localhost:8088/completion/mcp-tools`를 호출한다.
2. 응답 상태 코드가 `200`이며 `Content-Type`이 `application/json` 계열인지 확인한다.
3. 응답 JSON이 객체이고 최소 1개 이상의 서버 키를 포함하는지 확인한다.
4. 응답에 stdio 형식(`command`+`args` 필드)을 가진 항목이 적어도 하나 존재하는지 확인한다(`mcp.json`에는 `ableton`, `git`, `memory` 등 다수 존재).
5. 응답에 URL 전송 형식(`type`/`url`/`transport` 필드)을 가진 항목이 적어도 하나 존재하는지 확인한다(`mcp.json`의 `gitmcp` 항목).
6. 추가 검증으로 임의 항목 `git`의 `command` 값이 `uvx`인지 등 spec 식별자 보존을 확인한다.

## 기대 결과
- HTTP 200 응답을 받는다.
- 응답 본문은 `mcpServers` 객체(JSON object)이며, 각 키가 MCP 서버 이름이다.
- 모든 항목은 다음 두 형식 중 하나에 부합한다:
  - stdio: `command`(string) + `args`(array) 필드를 포함
  - URL: `type`(예: `url`) + `url`(string) + `transport`(예: `sse`) 필드를 포함
- 게이트웨이 경유 경로가 손상되지 않았음을 확인한다(`/completion/` 프록시 + `completion:8000` 라우팅).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_mcp-server-config` | MCP 서버 카탈로그 조회 | 카탈로그 조회 성공 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 비-사용자 대상 프로토콜 검증이므로 의도적으로 스크린샷 체크포인트를 두지 않는다. DOCX 사용자 매뉴얼에는 본 시나리오의 응답 본문을 코드 블록으로 인용하는 형태로 활용한다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_mcp-server-config/e2e/results/results.json`
