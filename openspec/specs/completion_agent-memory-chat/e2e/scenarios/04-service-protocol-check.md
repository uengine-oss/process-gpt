# E2E 시나리오 04: 서비스 상태·원격 에이전트·필수값 누락 점검

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `상태 점검·원격 에이전트 조회·필수값 누락 응답을 확인한다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
이 시나리오는 사용자 화면 조작으로 직접 노출되지 않는 비 UI 프로토콜 동작 세 가지를 점검한다. 첫째, 서비스 상태 점검(`GET /multi-agent/health-check`)이 정상 응답을 반환하는지 확인한다. 둘째, 원격 에이전트 디스크립터 조회(`GET /multi-agent/fetch-data`)가 대상 에이전트의 `/.well-known/agent.json` 내용을 반환하는지 확인한다. 셋째, 학습/질문 탭이 항상 `agent_id`를 자동 포함하기 때문에 사용자 조작으로는 만들 수 없는 `agent_id` 누락 상황에서 `400` 오류 계약이 지켜지는지 확인한다. 사용자 대면 흐름이 아니므로 절차는 브라우저 조작이 아닌 프로토콜 요청으로 작성한다.

## 사전 조건
- 게이트웨이(`http://localhost:8088`)와 completion 서비스가 떠 있어야 한다.
- 원격 에이전트 디스크립터 조회 대상으로 외부 에이전트 스텁(`mock-external-agent`)이 `/.well-known/agent.json`을 제공해야 한다.
- 이 점검은 사용자 화면을 거치지 않으므로 스크린샷 체크포인트가 없다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `mock-external-agent` | route stub | `http://mock-external-agent:8090` | 외부 A2A 에이전트 카드(`/.well-known/agent.json`) 제공 |
| 상태 점검 요청 | protocol | `GET /completion/multi-agent/health-check` | 서비스 정상 동작 확인 |
| 원격 조회 요청 | protocol | `GET /completion/multi-agent/fetch-data?agent_url=...` | 디스크립터 반환 확인 |
| 누락 요청 본문 | fixture | `{text, chat_room_id, options:{}}` | `agent_id` 누락 오류 재현 |

## 절차
1. 상태 점검: `GET /completion/multi-agent/health-check`를 호출한다. (비 UI 프로토콜 점검)
2. 원격 에이전트 조회: `mock-external-agent` URL을 `agent_url` 질의 파라미터로 전달하여 `GET /completion/multi-agent/fetch-data`를 호출한다. (비 UI 프로토콜 점검)
3. 필수값 누락: `options`에 `agent_id`가 없는 본문으로 `POST /completion/multi-agent/chat`을 호출한다. (비 UI 프로토콜 점검)

## 기대 결과
- 상태 점검 응답은 `200` 상태와 `{status: "healthy"}` 본문을 반환한다.
- 원격 조회 응답은 대상 에이전트의 `/.well-known/agent.json` 디스크립터 내용(에이전트 이름 등)을 포함한다.
- 필수값 누락 요청은 `400` 상태와 `agent_id is required for Mem0 agent` 메시지를 반환한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | 상태 점검 응답 |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | 원격 에이전트 정보 조회 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | agent_id 누락 |

## 산출물
- 스크린샷 체크포인트: 해당 없음 (비 UI 프로토콜 점검이므로 사용자 화면 캡처 대상이 없음)
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
