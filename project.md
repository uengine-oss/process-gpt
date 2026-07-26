가능한 새로운 기능은 새로운 마이크로 서비스의 기능 구현을 한다. 전체적으로 서비스 폴더 이하의 마이크로 서비스들이 들어 있다 기존의 응집도에 따라서 기능이 기존 마이크로 서비스에 들어가는 것에 부합된다면 그쪽에 응집도 높게 추가하고 그런 것이 아니라 새롭게 추가되어야 되거나 기존의 서비스와는 너무 커플링이 심하게 보이는 새로운 유형의 기능이라면 신규 마이크로 서비스로 신설한다 

사용자에게 알림이나 이런 것들을 보낼 때는 가능한 BPM 자체에 가지고 있는 워크 아이템을 발행하는 방식으로 해당 담당자에게 알림을 보낸다. WorkItem을 발행하는 방법은 DB 테이블에 직접 입력하면 안 되고 그 Work Item API를 통해서 보내야만 관련 노티도 같이 보내지기 때문에 그 경로를 이용한다. 

## 프론트엔드 채팅 UI 구조 (services/frontend)

채팅으로 뭔가를 편집/생성하는 기능(예: 전략맵 채팅 편집)을 새로 만들 때는, 완전히 새로운 방식을 발명하지 말고 아래 두 기존 구조 중 목적에 맞는 것을 재사용한다. 저장소에는 목적이 다른 두 계열이 공존한다 — 뭘 새로 만들지 결정하기 전에 반드시 이 둘을 구분해서 고를 것.

### A. `ChatModule` 상속 구조 — "고정 스키마 JSON을 생성/수정하는 채팅"에 재사용할 기반

이 구조는 **Vue mixin 상속**(`ChatModule.vue`, `GeneratorAgent.vue`)과 **JS 클래스 상속**(`AIGenerator` 및 그 서브클래스들)이 조합된 형태다. BSCard.vue(구 전략맵 채팅 편집기)를 포함해 20개에 가까운 View가 이 구조를 그대로 재사용하고 있다.

- **`src/components/GeneratorAgent.vue`** — 최하위 mixin. `ws(s)://<host>/autonomous` WebSocket에 붙어 `Agent: <name>|Tool: <tool>|Input: <input>` 형식의 레거시 프로토콜을 파싱한다. 지금은 `ChatModule`이 이 mixin을 얹고 쓰지 않는 경우가 대부분이라 사실상 하위 호환용에 가깝다.
- **`src/components/ChatModule.vue`** (`mixins: [GeneratorAgent]`) — 실제로 재사용해야 하는 레이어. `messages`(화면에 그릴 메시지 배열)와 `generator`(아래 `AIGenerator` 서브클래스 인스턴스) 상태를 소유하고, `sendMessage(message)` → `this.generator.generate()` 호출, 그리고 `onModelCreated(response)`(스트리밍 중 매 청크마다 호출됨 — 마지막 system 메시지 버블을 갱신하고, 펜스드 \`\`\`json 블록을 `partial-json-parser`/`JSON5`로 부분 파싱)까지 메시지 스트리밍·렌더링 로직을 전부 구현해 둔 상태다.
- **`src/components/ai/AIGenerator.js`** — LLM 호출 자체를 캡슐화하는 베이스 클래스. `generate()`는 **OpenAI를 브라우저에서 직접 부르지 않는다** — `services/completion`의 `/langchain-chat/messages`(dev는 `/langchain-chat`, 배포는 `/completion/langchain-chat` prefix)로 `XMLHttpRequest` + `xhr.onprogress`로 SSE 유사 청크를 스트리밍 수신한다. API 키는 항상 `services/completion` 쪽에만 있다.
- **`src/components/ai/*.js` 서브클래스들**(`BSGenerator`, `WorkAssistantGenerator`, `ChatRoomNameGenerator`, `AgentChatGenerator` 등 30개 가까이) — `AIGenerator`를 상속해 `previousMessages`(시스템 프롬프트 + 고정 JSON 스키마 지시)만 오버라이드한다. 새 기능을 붙일 때 실제로 새로 작성하는 건 이 클래스 하나뿐이다.
- **View가 재사용하는 방법(연결 지점)**: 리프 컴포넌트가 `mixins: [ChatModule]`을 선언하고, `mounted()`에서 `this.generator = new XxxGenerator(this, { isStream: true, preferredLanguage: 'Korean' })`처럼 **자기 자신(`this`)을 `client`로 넘겨** 인스턴스화한다. `AIGenerator`/`ChatModule`이 그 `client.onModelCreated(...)`/`onGenerationFinished(...)`/`onError(...)`를 콜백으로 호출하는 구조라, View 쪽은 `mixins: [ChatModule]` + 서브클래스 인스턴스화 두 줄이면 스트리밍 메시지 UI를 전부 공짜로 얻는다. 실 사용 예: `src/components/ui/BSCard.vue:306` `mixins: [ChatModule]`, `BSCard.vue:413` `this.generator = new ChatGenerator(this, {...})` (`ChatGenerator`는 `BSGenerator.js`를 import alias한 것).
- **적합한 상황**: "고정된 JSON 스키마 하나를 채팅으로 채워나가는" 기능 — 지금 만들고 있는 전략맵 채팅 편집기가 정확히 이 모양이다(과거 BSGenerator가 했던 일과 동일). 멀티스텝 툴콜/파일시스템 접근/서브에이전트 위임이 필요 없다면 이 구조가 제일 가볍다.

### B. deepagents 스트리밍 구조 — "실제 여러 툴을 순차 호출하는 에이전트" 채팅에 재사용할 기반

`ChatRoomPage.vue`(라이브, `/chat` 라우트)가 쓰는 최신 구조. `src/components/ui/Chat.vue`(메시지 리스트/마크다운 렌더 base, `marked` 사용)를 얹고, `src/services/DeepAgentRouterService.js`가 API 게이트웨이 경유로 `services/deepagents`(LangGraph `DeepAgentExecutor`, `/chat/stream` SSE 엔드포인트)를 호출한다. 매 턴마다 전체 히스토리를 다시 보내지 않고 `conversation_id` + 새 메시지만 보내며, 각 메시지는 턴이 끝나는 즉시 Supabase `chats` 테이블에 개별 저장된다(왕복 없음). `tool_start`/`tool_end`/`plan_*` 같은 구조화 SSE 이벤트로 "🔧 OOO 실행 중..." 같은 진행 표시를 실시간으로 그린다.

- **적합한 상황**: 여러 도구를 순차/조건부로 호출해야 하거나, 서브에이전트 위임·파일 작업·HITL(사람 확인)이 필요한 진짜 "에이전트" 기능. 무겁지만 제대로 된 멀티스텝 실행이 필요할 때만 이쪽을 쓴다.
- 이 계열은 Options API 컴포넌트들의 조합일 뿐, `useChat()` 같은 재사용 가능한 Composition API 컴포저블은 존재하지 않는다. SSE 파싱 클라이언트(`DeepAgentRouterService.js`/`AgentRouterService.js`/`WorkAssistantAgentService.js`)도 서로 복붙된 별개 구현이라 공유 베이스가 없다 — 새로 하나 더 만들 땐 이 셋 중 하나를 그대로 복제/수정하는 게 현재 관례다.

### 현재 전략맵 채팅 편집기(`services/strategy/app/chat.py` + `StrategyChatPanel.vue`)는 어느 쪽도 아님

지금 구현은 위 A/B 어느 것도 아닌 4번째 방식이다 — 백엔드(`services/strategy`)에서 OpenAI 네이티브 tool-calling 루프를 직접 돌리고, 한 번의 non-streaming POST/응답으로 끝내며, 히스토리는 프런트가 매 턴 통째로 왕복시킨다(`services/strategy`가 자체 그래프 DB를 갖고 있고 `app/ai.py`/`app/impact_analysis.py`가 이미 같은 네이티브 openai 클라이언트 패턴을 쓰고 있어서, 이 서비스 안에서는 일관성 있는 선택이었다). 다만 A 구조(정확히 이 기능이 하려는 "고정 스키마를 채팅으로 채우기")를 그대로 재사용했다면 `services/completion`의 기존 LLM 프록시·스트리밍·부분 JSON 파싱을 공짜로 얻었을 것이다. 이 기능을 프런트엔드 스트리밍 UX로 다시 맞추게 된다면, 새 프로토콜을 또 만들지 말고 A 구조(`ChatModule` mixin + `AIGenerator` 서브클래스, `services/completion`의 `/langchain-chat` 경유)를 재사용하는 쪽으로 간다.

## deepagents 시스템 프롬프트 과적합 방지 원칙 (`services/deepagents/core/agents/agent.py`)

`agent.py`의 `DEFAULT_SYSTEM_PROMPT`는 **모든 스킬·모든 요청에 항상 적용되는 공용 지시문**이다. 특정 스킬 하나의 상세 절차를 여기에 하드코딩하면, 그 스킬과 무관한 요청에서도 프롬프트가 그 스킬 쪽으로 편향돼(과적합) LLM이 다른 스킬의 존재를 사실상 무시하게 된다 — 실제로 2026-06-20 커밋(`4d2b1a8`, "update process gen")이 BPMN 프로세스 생성 절차 130줄을 이 프롬프트에 통째로 넣은 뒤, 한 달 뒤 추가된 `bsc-strategy-interview` 스킬이 자연어("uengine.org 라는 회사의 전략을 수립하고 싶어")만으로는 전혀 트리거되지 않는 회귀가 발생했다(2026-07-21 발견·수정).

새 스킬을 추가하거나 기존 스킬을 고칠 때, `agent.py`를 건드리기 전에 그 프롬프트 조각이 어디에 속하는지 아래 세 가지로 분류한다:

1. **스킬 내부로 이동해야 할 것** — 특정 스킬 하나를 실행하는 절차·규칙·형식(단계 순서, 도구 사용법, 산출물 스키마, 금지사항 등)은 그 스킬의 `SKILL.md`/`references/*.md`에 있어야 한다. deepagents는 Claude Agent Skills와 동일한 progressive disclosure를 지원하므로(`SkillsMiddleware`), 스킬 설명이 요청과 일치하면 모델이 필요할 때만 `read_file`로 그 스킬을 읽는다 — agent.py에 매번 다 실어둘 필요가 없다. 스킬이 Claude Code CLI와 deepagents 양쪽에서 쓰인다면(예: `bpmn-process-generation-skill`), 스킬 파일 안에서 실행 환경별로 분기하고(`bsc-strategy-interview`가 이미 쓰는 패턴 — "Claude Code CLI에서는 X, deepagents에서는 Y"), deepagents 전용 세부사항은 별도 reference 파일(예: `references/12-deepagents-execution.md`)로 분리해 응집도를 지킨다.
2. **스킬로 분리할 수 없고 ProcessGPT/deepagents 인프라 특성상 꼭 필요한 것** — 대화별로 런타임에만 계산되는 값(예: 이번 대화 전용 산출물 경로, 대화 id 기반 워크스페이스 경로) 주입, 스킬 선택 자체를 위한 범용 규칙("요청과 스킬 description을 대조해 적절한 스킬을 골라 읽어라" + 스킬마다 트리거 예시 한 줄씩), 스킬 생성 vs 프로세스 생성처럼 아직 어떤 스킬을 쓸지 정하기 *전에* 필요한 메타 판별 로직만 agent.py에 남긴다.
3. **스킬과 MCP 도구 설명이 중복되는 것** — 도구(`@tool` 데코레이터가 붙은 함수)의 사용법은 이미 그 도구의 docstring(= LLM에게 노출되는 tool schema)에 있다. 같은 내용을 시스템 프롬프트에 다시 길게 설명하지 않는다. 정말 강조가 필요하면(예: "이 도구는 정보를 다시 묻지 말고 먼저 호출하라") 한두 문장으로 짧게만 보강하고, 상세 사용법은 도구 docstring이나 그 도구를 쓰는 스킬 문서 쪽에 맡긴다.

새 스킬을 추가했는데 자연어로 트리거되지 않는다면, 십중팔구 (1)이 지켜지지 않아 다른 스킬(특히 BPMN 생성처럼 서술이 긴 스킬)에 프롬프트가 쏠려 있다는 뜻이다 — agent.py를 더 길게 만들지 말고, 그 스킬의 트리거 예시 한 줄을 "작업 선택 규칙" 섹션에 추가하는 것으로 먼저 해결을 시도한다.

