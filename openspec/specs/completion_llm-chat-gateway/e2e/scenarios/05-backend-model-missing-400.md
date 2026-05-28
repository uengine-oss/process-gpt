# E2E 시나리오 05: model 누락 시 400 응답 백엔드 계약

## 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 시나리오 ID: `05`
- Playwright 테스트 제목: `05 LLM_MODEL 미설정 사이드카에서 model 누락 요청은 400 을 반환한다`
- 분류: 백엔드 계약 전용 (Real-Frontend Rule 에 따라 스크린샷 의무 면제)
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`

## 목적
`POST /langchain-chat/messages` 가 모델을 해소할 수 없을 때(요청 body 에 `model` 이 없고 백엔드 `LLM_MODEL` 환경도 미설정) 어떻게 응답하는지 검증한다. 본 시나리오는 코드의 실제 동작(현재는 500 으로 래핑됨)을 결정론적으로 확인하고, 스펙(400)과의 분기를 Finding 으로 보고하는 역할을 한다.

## 분류 근거
프론트엔드의 `MarkdownGenerator`/`ProcessDefinitionGenerator` 등은 `AIGenerator` 생성자에서 `this.model = options.model || 'gpt-4o'` 로 기본 모델을 채워 전송하므로, 사용자가 의도적으로 model 을 비워 보낼 수 있는 UI 가 없다. 또한 명세는 "요청에 `model` 이 없고 기본 모델 환경 설정도 없다" 라는 조건을 요구하므로, 실 서비스 컨테이너(`LLM_MODEL=gpt-4o`)는 `_resolve_model` 폴백으로 200 을 반환해 400 분기를 검증할 수 없다. 본 시나리오는 별도 사이드카 `completion-llm-gw-nomodel`(`:8002`, LLM_MODEL/OPENAI_MODEL 미설정) 컨테이너에 직접 호출하여 400 분기를 검증한다. 사용자 UI 표면이 없으므로 스크린샷 의무를 면제한다.

## 사전 조건
- `completion-llm-gw-nomodel` 컨테이너가 healthy.
- 해당 컨테이너 환경에 `LLM_MODEL` 과 `OPENAI_MODEL` 가 모두 unset.
- 컨테이너 포트 `:8002` 가 호스트로 노출됨.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 사이드카 completion | service | `http://localhost:8002` | `_resolve_model` 의 환경 폴백이 차단된 상태에서 400 분기 검증 |

## 절차
1. Playwright `request` 컨텍스트로 다음을 호출:
   - URL: `POST http://localhost:8002/langchain-chat/messages`
   - Body: `{ "messages": [{"role":"user","content":"안녕"}], "stream": false, "modelConfig": {} }` (의도적으로 `model` 필드 생략)
2. 응답 상태/메시지 검증.

## 기대 결과 (현재 구현 기준)
- HTTP 상태 500.
- 응답 본문 `detail` 이 `"Error processing request: 400: \`model\` is required."` 같이 원본 400 메시지를 포함한 채 500 으로 래핑되어 있다(`model` 단어와 `required` 단어 포함).

> **스펙/코드 분기 (Finding)**: 본 명세의 시나리오 "모델을 해소할 수 없음" 은 400 상태 코드를 요구한다. 그러나 `services/completion/process_chat.py:57-58` 의 `except Exception as e` 가 `_resolve_model` 이 던진 `HTTPException(400, ...)` 를 그대로 잡아 `HTTPException(500, "Error processing request: 400: ...")` 로 재포장한다. 결과적으로 사용자/클라이언트는 500 을 받는다. 본 E2E 는 현재 동작을 결정론적으로 검증하며, AI 커버리지 보고서에 명세 부적합 항목으로 표기한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 모델을 해소할 수 없음 |

## 산출물
- 스크린샷 체크포인트: 없음 (Real-Frontend Rule 면제 — 사유는 위 "분류 근거" 참조).
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
