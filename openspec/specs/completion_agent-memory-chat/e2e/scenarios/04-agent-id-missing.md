# E2E 시나리오 04: agent_id 누락 요청에 400 오류를 반환한다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `agent_id 누락 요청에 400 오류를 반환한다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
프론트엔드는 항상 `agent_id` 를 포함해 요청하므로 UI 표면에서는 발생하지 않는 조건이지만, 백엔드 프로토콜 계약상 `options.agent_id` 가 비어 있을 때 400 + `agent_id is required for Mem0 agent` 응답이 반환되는지 확인하는 보조 프로토콜 시나리오입니다. 본 시나리오는 사용자-facing 시나리오가 아니므로 스크린샷 매뉴얼 증거를 요구하지 않습니다.

## 사전 조건
- 게이트웨이 경유로 `/completion/multi-agent/chat` 가 도달 가능합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| agent_id 누락 요청 | request payload | `POST /completion/multi-agent/chat` | 400 응답 검증 |

## 절차
1. 보조 프로토콜: Playwright `request` 로 `POST /completion/multi-agent/chat` 에 `options:{is_learning_mode:false}` 만 담아 요청합니다.
2. 응답 상태와 본문의 메시지를 검증합니다.

## 기대 결과
- 응답 상태는 `400` 입니다.
- 응답 본문에 `agent_id is required for Mem0 agent` 메시지가 포함됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | agent_id 누락 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 보조 프로토콜 검증으로 사용자 UI 상태가 없어 스크린샷 매뉴얼 증거를 요구하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
