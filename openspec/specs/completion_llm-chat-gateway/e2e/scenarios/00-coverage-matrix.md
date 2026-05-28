# completion_llm-chat-gateway E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI가 `/langchain-chat/*` 경로로 노출하는 OpenAI 호환 채팅 게이트웨이(`process_chat.py`).
  - 게이트웨이(nginx, `:8088`) → `completion:8000` 라우팅. nginx `location /completion/` 가 prefix를 strip 한 뒤 `completion:8000/langchain-chat/*` 로 프록시한다(`openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf`).
  - 비결정적 외부 경계인 OpenAI 호환 LLM은 `mock-llm` 컨테이너(`openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py`)로 대체.
  - `model 누락 → 400` 분기는 별도 `completion-llm-gw-nomodel` 사이드카(공유 compose, `:8002`)에 LLM_MODEL/OPENAI_MODEL 을 비워 둔 채 배치해 `_resolve_model()` 의 환경 폴백을 차단한 상태에서 검증한다.
- E2E 루트: `openspec/specs/completion_llm-chat-gateway/e2e/`
- Playwright 명세: `openspec/specs/completion_llm-chat-gateway/e2e/tests/completion_llm-chat-gateway.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_llm-chat-gateway/e2e/results/`

## 재사용 산출물
| 항목 | 위치 | 사용 방식 |
| --- | --- | --- |
| 공유 Docker compose | `docker-compose.e2e.yml` | `frontend`, `gateway`, `completion`, `mock-llm`, `db`, `kong`, `auth`, `rest`, `db-seed` 그대로 재사용 |
| OpenAI 호환 mock LLM | `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py` | `/v1/chat/completions` (SSE) 응답 그대로 사용. 매칭되지 않는 프롬프트는 `"응답"` 텍스트 반환 |
| nginx 게이트웨이 conf | `openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf` | `/completion/` → `completion:8000` 프록시 |
| 로그인 헬퍼 패턴 | `openspec/specs/completion_agent-memory-chat/e2e/tests/completion_agent-memory-chat.spec.mjs`, `openspec/specs/completion_process-definition-search/e2e/tests/completion_process-definition-search.spec.mjs` | `.cp-id input` / `.cp-pwd input` / `.cp-login` 로그인 흐름 차용 |
| 공유 e2e 사용자 시드 | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | `e2e@uengine.org` 로그인 가능 |
| V8 프론트엔드 coverage 패턴 | 위 두 시블링 스위트의 `beforeEach/afterEach` | 프리빌트 이미지라 source-map 부재 → bundle V8 coverage 만 보조 지표로 수집 |
| 백엔드 coverage flush 패턴 | `openspec/e2e/memories/coverage-py-usr2-flush.md` | USR2 신호 기반 flush(이 스위트는 공유 `completion` 컨테이너를 재시작하지 않으므로 본 실행에서는 환경적 사유로 백엔드 coverage 수집 비활성) |

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 | 분류 |
| --- | --- | --- | --- | --- |
| 01 | `01-markdown-ai-streaming.md` | `01 마크다운 에디터에서 AI 입력을 보내면 스트리밍 응답이 본문에 삽입된다` | `/markdown-editor` 진입 → 본문 선택 → "Ask AI anything..." 입력 → Enter → MarkdownGenerator → POST `/completion/langchain-chat/messages` (stream=true) → SSE 누적 후 본문 업데이트 | 실제 UI |
| 02 | `02-backend-sanity-check.md` | `02 GET sanity-check 는 is_sanity_check true 를 반환한다` | Playwright `request` 로 게이트웨이를 거쳐 `GET /completion/langchain-chat/sanity-check` 호출 | 백엔드 계약 전용 |
| 03 | `03-backend-non-streaming.md` | `03 stream=false 일 때 POST messages 는 OpenAI 호환 단일 JSON 을 반환한다` | Playwright `request` 로 게이트웨이를 거쳐 `POST /completion/langchain-chat/messages` (stream=false) 호출, `id`/`choices[0].message` 검증 | 백엔드 계약 전용 |
| 04 | `04-backend-count-tokens.md` | `04 POST count-tokens 는 input_tokens 정수를 반환한다` | Playwright `request` 로 게이트웨이를 거쳐 `POST /completion/langchain-chat/count-tokens` 호출 | 백엔드 계약 전용 |
| 05 | `05-backend-model-missing-400.md` | `05 LLM_MODEL 미설정 사이드카에서 model 누락 요청은 400 을 반환한다` | Playwright `request` 로 `completion-llm-gw-nomodel:8002` 에 직접 `POST /langchain-chat/messages` (model 누락) 호출 | 백엔드 계약 전용 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_llm-chat-gateway` | 상태 점검 | SHALL | 02 | 실 사용자 UI 소비자 없음 → 백엔드 계약 전용, 스크린샷 면제 |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | SHALL | 01, 03, 05 | 스트리밍 경로는 실제 UI(MarkdownEditor), 비스트리밍/400은 백엔드 계약 전용 |
| `completion_llm-chat-gateway` | 토큰 수 계산 | SHALL | 04 | 실 사용자 UI 소비자 없음 → 백엔드 계약 전용, 스크린샷 면제 |
| `completion_llm-chat-gateway` | 임베딩 벡터 생성 | SHALL | (면제) | 정상 케이스는 `completion_process-definition-search` 스위트의 `/completion/process-search` 경로가 동일 `mock-llm` `/v1/embeddings` 를 통해 간접 검증함. 본 슈트에서는 중복 시나리오 면제 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_llm-chat-gateway` | 상태 점검 | 상태 점검 응답 | 02 | 백엔드 계약 전용 — 실제 프론트엔드 소비자 없음 (`AIGenerator.checkBackendConnection` 은 내부 호출이며 사용자가 직접 트리거하지 않음) |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 비스트리밍 채팅 완성 | 03 | 백엔드 계약 전용 — `AIGenerator.generate()` 가 항상 `stream: true` 를 보내므로 실제 프론트엔드 소비자 없음 (`services/frontend/src/components/ai/AIGenerator.js:485`) |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 스트리밍 채팅 완성 | 01 | `/markdown-editor` 진입 → 본문 입력/선택 → BubbleMenu 의 "Ask AI anything..." 에 프롬프트 입력 → Enter → 본문에 스트리밍 결과 삽입 |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 모델을 해소할 수 없음 | 05 | 백엔드 계약 전용 — 실제 프론트엔드는 항상 모델을 기본값으로 채워 전송하므로 model 누락 분기를 사용자가 트리거할 수 없음 |
| `completion_llm-chat-gateway` | 토큰 수 계산 | 토큰 수 계산 성공 | 04 | 백엔드 계약 전용 — `count-tokens` 를 호출하는 프론트엔드 컴포넌트가 없음(`grep -R "count-tokens" services/frontend/src` 결과 0 건) |
| `completion_llm-chat-gateway` | 임베딩 벡터 생성 | 임베딩 생성 성공 | (면제) | `completion_process-definition-search` 슈트가 `mock-llm` 의 `/v1/embeddings` 를 통한 임베딩 생성 경로를 이미 검증함 |
| `completion_llm-chat-gateway` | 임베딩 벡터 생성 | 임베딩을 지원하지 않는 모델 구성 | (보류) | 현재 `llm_factory.create_embedding` 은 항상 `OpenAIEmbeddings` 를 생성해 `ValueError`/`NotImplementedError` 를 결정론적으로 유발하기 어려움. 미지원 provider 분기 추가 후 재검토 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/process_chat.py` | `add_routes_to_app`, `sanity_check`, `process_chat_messages`, `count_tokens`, `get_embedding_vector`, `_resolve_model`, `_resolve_embedding_model` | 전체 요구사항 | line/function >= 80% | `/langchain-chat/*` 라우트 등록과 입력 검증/오류 매핑을 직접 구현 |
| `services/completion/features/process_chat/__init__.py` | 모듈 노출 | 채팅 완성 응답 | line/function >= 80% | `BASE_URL`, `ChatRequest`, `TokenCountRequest`, `EmbeddingRequest`, `ChatInterface` 노출 |
| `services/completion/features/process_chat/constants.py` | `BASE_URL = "/langchain-chat"` | 전체 요구사항 | line >= 100% | 모든 라우트의 prefix 결정 |
| `services/completion/features/process_chat/schemas.py` | `ChatRequest`, `TokenCountRequest`, `EmbeddingRequest` | 채팅 완성 응답, 토큰 수 계산, 임베딩 벡터 생성 | line/function >= 80% | 요청 본문 파싱과 필드 검증 |
| `services/completion/features/process_chat/interfaces/chat_interface/chat_interface.py` | `ChatInterface.messages`, `_format_non_stream_response`, `_format_stream_chunk`, `count_tokens`, `embeddings` | 채팅 완성 응답, 토큰 수 계산, 임베딩 벡터 생성 | line/function >= 70% | 비스트리밍/스트리밍 응답 형식 변환과 count_tokens/embeddings 호출 직접 수행 |
| `services/completion/features/process_chat/interfaces/chat_interface/factories/message_factory.py` | `LangchainMessageFactory.create_messages` | 채팅 완성 응답, 토큰 수 계산 | line/function >= 70% | 요청 메시지 → langchain 메시지 변환 |
| `services/completion/llm_factory.py` | `create_llm`, `create_embedding`, `_proxy_base_url`, `_proxy_api_key`, `get_llm_model` | 채팅 완성 응답, 임베딩 벡터 생성 | 보조/함수 >= 60% | 채팅/임베딩 클라이언트 생성 — 공용 인프라성이 강해 보조 증거로 사용 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/views/markdown/MarkdownEditor.vue` | `initEditor`, `handleAIOption`, `generate`, `onReceived`, `onGenerationFinished`, BubbleMenu 입력/옵션 | 채팅 완성 응답(스트리밍) | 참고/bundle V8 coverage 존재 | 실제 사용자 화면. `/markdown-editor` 라우트에서 AI 입력으로 `/completion/langchain-chat/messages` 를 트리거하는 대표 UI |
| `services/frontend/src/components/ai/MarkdownGenerator.js` | `MarkdownGenerator` (AIGenerator 상속, `isStream: true`) | 채팅 완성 응답(스트리밍) | 참고/bundle V8 coverage 존재 | 에디터가 사용하는 AIGenerator 구체 클래스 |
| `services/frontend/src/components/ai/AIGenerator.js` | `generate`, `checkBackendConnection`, `xhr.onprogress`, `xhr.onloadend`, `backendUrl = '/completion/langchain-chat'` | 채팅 완성 응답, 상태 점검 | 참고/bundle V8 coverage 존재 | 25+ 개 생성기의 공통 베이스. 본 슈트에서는 MarkdownGenerator 경유로 사용자 동작이 도달함 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 임베딩 생성 정상 케이스 직접 검증 | 동일 mock-llm 경로가 `completion_process-definition-search` 슈트에서 이미 사용자 검색 흐름으로 검증됨 — 중복 시나리오 면제 | 임베딩 계약이 본 슈트 전용으로 분리되어야 할 변경이 생기면 본 슈트에 시나리오 추가 |
| 임베딩 미지원 모델 → 501 | 현재 `llm_factory.create_embedding` 이 항상 `OpenAIEmbeddings` 를 생성해 `ValueError`/`NotImplementedError` 를 결정론적으로 유발하기 어려움 | 미지원 provider/모델 분기를 추가하거나, mock-llm 이 503을 반환했을 때 `ValueError` 로 매핑하도록 인터페이스 변경 후 재추가 |
| 비스트리밍 채팅 완성, 토큰 수 계산, 상태 점검, model 누락 400 의 실 사용자 UI 검증 | 현재 프론트엔드 코드에 해당 경로를 트리거하는 사용자 화면이 존재하지 않음(Real-Frontend Rule). 무리하게 합성 테스터 페이지를 띄우는 것은 규칙 위반 | 프론트엔드에 해당 기능을 노출하는 화면이 신설되면 해당 시나리오를 실제 UI 시나리오로 승격 |

## 스펙/코드 분기 (Findings)
| ID | 명세 시나리오 | 명세 기대 | 관찰된 동작 | 원인(코드) | 권장 조치 |
| --- | --- | --- | --- | --- | --- |
| F1 | 모델을 해소할 수 없음 | 400 + "model" 메시지 | 500 + `"Error processing request: 400: \`model\` is required..."` | `services/completion/process_chat.py:57-58` 의 `except Exception` 가 `_resolve_model` 의 `HTTPException(400, ...)` 를 잡아 500 으로 재포장 | `except HTTPException: raise` 절을 catch-all 앞에 추가하거나, `_resolve_model` 의 예외를 비-HTTP 예외로 분리해 라우트 본문에서 명시적으로 400 으로 매핑 |
| F2 | 토큰 수 계산 성공 | 200 + `{input_tokens: <정수>}` | 500 + `"Error counting tokens: object int can't be used in 'await' expression"` | `services/completion/process_chat.py:64` 가 동기 메서드 `ChatInterface.count_tokens(...)` 를 `await` | 라우트에서 `await` 제거하거나 `ChatInterface.count_tokens` 를 비동기로 변경 |

## 체크리스트
- [x] 모든 Requirement 가 하나 이상의 E2E 시나리오 또는 면제/보류 항목에 매핑됨.
- [x] 중요한 OpenSpec Scenario 가 매핑되거나 보류 항목에 기록됨.
- [x] 사람이 읽는 요구사항명/시나리오명/절차/기대 결과가 한국어로 작성됨.
- [x] API 경로(`/langchain-chat/...`), 필드명(`is_sanity_check`, `input_tokens`, `embedding`, `choices`, `delta.content`), 이벤트(`data:`, `[DONE]`)는 원문 유지.
- [x] 원본 명세는 단일 백엔드 연계 피쳐(OpenAI 호환 LLM 채팅 게이트웨이) 범위임.
- [x] 서비스 접두어(`completion`)와 도메인 구분자(`llm-chat-gateway`) 가 구현 레이어가 아님.
- [x] E2E 가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확함.
- [x] 서비스 접두형 명세 ID 와 슈트 슬러그가 동일하게 유지됨.
- [x] E2E 시나리오·테스트·시드·결과·스크린샷이 `openspec/specs/completion_llm-chat-gateway/e2e/` 아래에 응집됨.
- [x] 실제 사용자 UI 시나리오(01)는 합성 테스터 페이지가 아니라 `/markdown-editor` 라는 실제 프론트엔드 라우트를 통해 구동됨.
- [x] 백엔드 계약 전용 시나리오(02–05)는 Real-Frontend Rule 에 따라 스크린샷 의무를 면제하고 그 근거를 코드 참조와 함께 명시함.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록됨.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의됨.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md` 와 일치함.
