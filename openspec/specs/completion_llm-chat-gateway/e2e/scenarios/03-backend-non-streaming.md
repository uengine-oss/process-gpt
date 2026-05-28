# E2E 시나리오 03: 비스트리밍 채팅 완성 백엔드 계약

## 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `03 stream=false 일 때 POST messages 는 OpenAI 호환 단일 JSON 을 반환한다`
- 분류: 백엔드 계약 전용 (Real-Frontend Rule 에 따라 스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`

## 목적
`POST /langchain-chat/messages` 가 `stream=false` 요청에 대해 OpenAI 호환 단일 JSON (`id`, `choices[0].message.role/content`) 으로 응답하는지를 게이트웨이를 통해 검증한다. `ChatInterface.messages` 의 비스트리밍 분기와 `_format_non_stream_response` 가 실제로 호출된다.

## 분류 근거
`services/frontend/src/components/ai/AIGenerator.js:485` 의 요청 본문은 `stream: this.options.isStream || true` 로 작성되므로 `false || true === true` 이며 **항상 `stream: true`** 를 전송한다. 즉 25+ 개의 AIGenerator 자식 클래스(`MarkdownGenerator`, `ProcessDefinitionGenerator`, `FormDesignGenerator`, `ScriptGenerator`, `WorkItemAgentGenerator` 등) 어디서도 `stream=false` 비스트리밍 채팅 완성 경로를 사용자 동작으로 트리거할 수 없다. Real-Frontend Rule 에 따라 합성 테스터 페이지를 띄우지 않고 백엔드 계약만 직접 검증하며 스크린샷 의무를 면제한다.

## 사전 조건
- `gateway`(`:8088`), `completion`, `mock-llm` healthy.
- `OPENAI_BASE_URL=http://mock-llm:8080/v1`, `LLM_MODEL=gpt-4o`.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| mock-llm 비스트리밍 응답 | stub | `mock-llm:8080/v1/chat/completions` (stream=false) | OpenAI 호환 단일 JSON 반환 |

## 절차
1. Playwright `request` 컨텍스트로 다음을 호출:
   - URL: `POST http://localhost:8088/completion/langchain-chat/messages`
   - Body: `{ "model": "gpt-4o", "messages": [{"role":"user","content":"안녕하세요"}], "stream": false, "modelConfig": {"temperature": 0} }`
2. 응답 상태/Content-Type/JSON 형식을 검증.

## 기대 결과
- HTTP 상태 200.
- `Content-Type` 이 `application/json`.
- 응답 본문에 `id` 가 문자열로 존재하고 `chatcmpl-` 접두사로 시작.
- `choices` 가 비어 있지 않은 배열이며 `choices[0].message.role === "assistant"`.
- `choices[0].message.content` 가 비어 있지 않은 문자열.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 비스트리밍 채팅 완성 |

## 산출물
- 스크린샷 체크포인트: 없음 (Real-Frontend Rule 면제 — 사유는 위 "분류 근거" 참조).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
