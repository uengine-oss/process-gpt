# E2E 시나리오 06: GET /multi-agent/fetch-data 가 외부 에이전트 디스크립터를 반환한다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `06`
- Playwright 테스트 제목: `GET /multi-agent/fetch-data 가 외부 에이전트 디스크립터를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
`fetch_data` 라우트가 `agent_url` 질의 파라미터를 받아 외부 에이전트의 `/.well-known/agent.json` 디스크립터를 프록시하여 반환하는지 보조 프로토콜로 확인합니다. 외부 boundary 는 `mock-external-agent` 가 결정성으로 응답합니다. UI 표면이 없어 스크린샷 매뉴얼 증거를 요구하지 않습니다.

## 사전 조건
- `mock-external-agent` 컨테이너가 `:8090/.well-known/agent.json` 을 200 으로 응답합니다.
- completion 컨테이너에서 `http://mock-external-agent:8090` 가 도달 가능합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| mock-external-agent | stub | `GET http://mock-external-agent:8090/.well-known/agent.json` | 결정성 디스크립터 |

## 절차
1. Playwright `request` 로 `GET /completion/multi-agent/fetch-data?agent_url=http://mock-external-agent:8090` 을 호출합니다.
2. 응답 상태와 JSON 본문의 식별 필드(`name`, `url`) 를 검증합니다.

## 기대 결과
- 응답 상태는 `200` 입니다.
- 응답 본문에는 `name: "e2e-mock-agent"` 및 `url: "http://mock-external-agent:8090"` 가 포함되어 있습니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | 원격 에이전트 정보 조회 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 보조 프로토콜 검증으로 UI 표면이 없어 스크린샷 매뉴얼 증거를 요구하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
