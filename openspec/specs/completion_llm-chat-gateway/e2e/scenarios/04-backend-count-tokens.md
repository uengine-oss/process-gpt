# E2E 시나리오 04: 토큰 수 계산 백엔드 계약

## 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `04 POST count-tokens 는 input_tokens 정수를 반환한다`
- 분류: 백엔드 계약 전용 (Real-Frontend Rule 에 따라 스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`

## 목적
`POST /langchain-chat/count-tokens` 가 입력 메시지 목록의 토큰 수를 어떻게 반환하는지 게이트웨이를 통해 검증한다. 본 시나리오는 코드의 실제 동작(현재는 500 으로 실패)을 결정론적으로 확인하고, 스펙(200 + `input_tokens`)과의 분기를 Finding 으로 보고하는 역할을 한다.

## 분류 근거
프론트엔드 코드 어디에서도 `/langchain-chat/count-tokens` 를 호출하지 않는다(`grep -R "count-tokens" services/frontend/src` 결과 0건). 사용자에게 토큰 수를 표시하는 화면이 존재하지 않으므로 합성 페이지 없이 백엔드 계약만 검증하고 스크린샷 의무를 면제한다.

## 사전 조건
- `gateway`(`:8088`), `completion`, `mock-llm` healthy.
- `LLM_MODEL=gpt-4o` 환경에서 `_resolve_model` 이 폴백 가능.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| (없음) | - | - | tiktoken 기반 동기 카운트, mock-llm 미사용 |

## 절차
1. Playwright `request` 컨텍스트로 다음을 호출:
   - URL: `POST http://localhost:8088/completion/langchain-chat/count-tokens`
   - Body: `{ "model": "gpt-4o", "messages": [{"role":"user","content":"안녕하세요"}] }`
2. 응답 상태/본문 검증.

## 기대 결과 (현재 구현 기준)
- HTTP 상태 500.
- 응답 본문 `detail` 이 문자열이며 `"Error counting tokens"` 와 `"await"` 단어를 포함한다.

> **스펙/코드 분기 (Finding)**: 본 명세의 시나리오 "토큰 수 계산 성공" 은 `{input_tokens: <정수>}` 200 응답을 요구한다. 그러나 `services/completion/process_chat.py:64` 는 동기 메서드인 `ChatInterface.count_tokens(...)` 를 `await` 하여 `TypeError: object int can't be used in 'await' expression` 가 발생하고 `except Exception` 분기에서 500 으로 래핑된다. 본 E2E 는 현재 동작을 결정론적으로 검증하며, AI 커버리지 보고서에 명세 부적합 항목으로 표기한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_llm-chat-gateway` | 토큰 수 계산 | 토큰 수 계산 성공 |

## 산출물
- 스크린샷 체크포인트: 없음 (Real-Frontend Rule 면제 — 사유는 위 "분류 근거" 참조).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
