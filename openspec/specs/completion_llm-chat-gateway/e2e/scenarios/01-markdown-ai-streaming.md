# E2E 시나리오 01: 마크다운 에디터에서 AI 입력으로 스트리밍 채팅 완성

## 메타데이터
- 스위트 슬러그: `completion_llm-chat-gateway`
- 원본 명세 ID: `completion_llm-chat-gateway`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `01 마크다운 에디터에서 AI 입력을 보내면 스트리밍 응답이 본문에 삽입된다`
- 원본 명세:
  - `openspec/specs/completion_llm-chat-gateway/spec.md`

## 목적
사용자가 실제 프론트엔드(`/markdown-editor`)에서 본문을 선택하고 "Ask AI anything..." 입력으로 프롬프트를 전송하면, 프론트엔드의 `MarkdownGenerator`(AIGenerator 상속, `isStream: true`)가 `POST /completion/langchain-chat/messages` 를 호출하고 게이트웨이를 통해 completion 백엔드 → mock-llm 으로 이어지는 SSE 응답이 누적되어 에디터 본문이 갱신되어야 한다. 이 시나리오는 명세의 "스트리밍 채팅 완성" 시나리오를 실제 사용자 UI 경로로 검증한다.

## 사전 조건
- `docker-compose.e2e.yml` 스택이 기동되어 있고 `frontend`(`process-gpt-e2e-frontend`), `gateway`(`:8088`), `completion`(`:8000`, healthy), `mock-llm`, `db`, `kong`, `auth`, `rest` 모두 healthy.
- nginx 게이트웨이가 `/completion/` 를 strip 하여 `completion:8000` 으로 프록시(`openspec/specs/completion_agent-memory-chat/e2e/docker/nginx.e2e.conf`).
- `completion` 컨테이너 환경: `OPENAI_BASE_URL=http://mock-llm:8080/v1`, `LLM_MODEL=gpt-4o` 로 mock-llm 을 향함.
- `e2e@uengine.org` / `e2epassword` 시드 사용자가 존재(`openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql`).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| mock-llm SSE 응답 | stub (외부 LLM 경계) | `mock-llm:8080/v1/chat/completions` (stream=true) | OpenAI 호환 SSE 청크 + `[DONE]` 결정론적 반환. 본 슈트 프롬프트는 매칭 키워드가 없으므로 mock 기본 텍스트(`"응답"`) 반환 |
| 공유 e2e 사용자 | seed | `e2e@uengine.org` / `e2epassword` | 로그인 후 `/markdown-editor` 진입 권한 확보 |

## 절차
1. 사용자가 브라우저로 `http://localhost:8088/auth/login` 에 진입해 시드 계정으로 로그인한다.
2. 로그인 후 `http://localhost:8088/markdown-editor` 로 이동한다.
3. 에디터 본문에 한국어 문단(예: `테스트 문단입니다.`)을 입력한다.
4. 본문을 키보드 단축키(Ctrl+A)로 전체 선택해 Tiptap BubbleMenu 를 활성화한다.
5. BubbleMenu 의 "Ask AI anything..." 입력란을 클릭하고 프롬프트(예: `짧게 보강해 주세요.`)를 입력한다.
6. Enter 를 눌러 `handleAIOption(null)` → `MarkdownGenerator.generate()` 가 실행되게 한다.
7. 브라우저가 `POST /completion/langchain-chat/messages` (Content-Type `application/json`, body 에 `stream: true`) 요청을 보내고 SSE 스트림을 수신한다.

## 기대 결과
- 응답 HTTP 상태 200, `Content-Type` 이 `text/event-stream` 으로 시작.
- 요청 본문에 `stream: true` 와 `messages` 배열이 포함됨.
- AIGenerator 의 XHR `onprogress` 가 누적한 `data: ...` 프레임 중 최소 한 개에 `choices[0].delta.content` 가 존재하고, 마지막에 `data: [DONE]` 가 포함됨.
- 사용자 화면에서 AI 입력 로딩 상태가 사라진 뒤 에디터 본문에 응답 텍스트가 반영된 흔적이 보임(에디터 본문이 비어 있지 않거나, 입력했던 원본 문단과 다른 내용으로 변경됨).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_llm-chat-gateway` | 채팅 완성 응답 | 스트리밍 채팅 완성 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-editor-initial` | `/markdown-editor` 진입 직후, 빈 에디터 화면 | `process-gpt-completion_llm-chat-gateway-01-editor-initial.png` | 마크다운 에디터 진입 화면. AI 보조 기능을 사용할 본문 영역. |
  | `01-bubble-menu-open` | 본문 선택 후 "Ask AI anything..." 입력란과 옵션 목록이 표시된 BubbleMenu 상태 | `process-gpt-completion_llm-chat-gateway-01-bubble-menu-open.png` | 본문을 선택하면 나타나는 AI 입력 메뉴. |
  | `01-prompt-typed` | AI 입력란에 프롬프트가 입력된 상태(Enter 직전) | `process-gpt-completion_llm-chat-gateway-01-prompt-typed.png` | 사용자가 AI 에게 보낼 보강 요청을 입력한 상태. |
  | `01-response-applied` | 스트리밍 응답이 종료되고 에디터 본문에 결과가 반영된 상태 | `process-gpt-completion_llm-chat-gateway-01-response-applied.png` | 스트리밍 응답을 받아 에디터 본문이 갱신된 상태. |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_llm-chat-gateway/e2e/results/results.json`
