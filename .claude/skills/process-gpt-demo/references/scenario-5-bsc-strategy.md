# 시나리오 5 — BSC 전략 수립: 자연어 트리거 + 웹사이트 조사 + 전략맵 보드

경영자가 회사 도메인 하나만 던지면, `bsc-strategy-interview` 스킬이 슬래시
명령 없이 자연어 트리거만으로 기동되고, 회사 홈페이지를 실제로 조사(WebSurfer
역할의 `fetch_webpage` 도구)한 뒤 그 내용을 바탕으로 BSC 전략맵과 비즈니스
모델 캔버스를 함께 수립하는 과정을 보여준다. 마지막에는 채팅 안의 mermaid
다이어그램뿐 아니라, 전략 서비스에 실제로 저장된 결과를 보여주는 전용 화면
(`StrategyBoard.vue`, `/strategy-board`)까지 확인한다.

전제: [demo-account.md](demo-account.md)의 고정 계정으로 로그인돼 있어야
한다. deepagents가 `STRATEGY_SERVICE_URL`(기본 `http://localhost:8014`)로
`services/strategy`에 접근 가능해야 하고, `fetch_webpage` 도구(웹 조회)가
활성화돼 있어야 한다(둘 다 `core/agents/agent.py`에 항상 등록됨 — 없으면
deepagents 재기동 필요).

## 0. 기본 에이전트를 "딥 에이전트"로

새 대화의 기본 오케스트레이션은 프론트엔드에서 이미 `deepagents`로 맞춰
놓았으므로(2026-07-21 변경, `services/frontend/src/components/ui/Chat.vue` /
`ChatRoomPage.vue`), 별도로 드롭다운을 바꿀 필요가 없다. 혹시 과거 버전이면
채팅 입력창 옆 오케스트레이션 선택에서 "딥 에이전트"를 고른다.

## 1. 자연어 한 줄로 트리거

`/definition-map`에서 슬래시 명령이나 사전 정보 없이 **딱 한 줄만** 보낸다:
```
uengine.org 라는 회사의 전략을 수립하고 싶어
```

- `bsc-strategy-interview` 스킬이 이 문장만으로(설명 트리거 매칭, 슬래시
  명령 불필요) 자동 기동돼야 한다. 기동되지 않으면 스킬 프런트매터
  `description`의 트리거 문구("전략 수립" 등)와 SkillsMiddleware 시딩
  상태(`local-system-skills: 기동 시 N개 스킬 시딩` 로그, N≥1)를 먼저
  확인한다.
- 회사 정보를 이미 한 문장에 담아 줬으므로(도메인만이라도), 스킬은 홈페이지
  URL을 다시 묻지 않고 `fetch_webpage`로 `uengine.org`를 바로 조회해야
  한다(스킬 "0단계: 회사 정보 확보" 참조). 로그에서 `fetch_webpage` 도구
  호출을 확인한다.
- 진입 모드(하향식/전체조망식/혼합형) 선택 칩이 뜨면 아무거나 골라도 되고,
  이후 세부 질문은 "합리적으로 판단해서 진행해줘" 식 자유 입력으로 건너뛰어도
  스킵-어헤드 규칙에 따라 빠르게 진행된다.

## 2. 확인할 세 가지 화면

1. **비즈니스 모델 캔버스** — Markdown 표로 9블록이 실제 렌더링(GFM 표,
   `marked`의 `gfm:true`로 정상 지원).
2. **BSC 전략맵** — ```mermaid 코드블록이 회색 텍스트가 아니라 **실제 SVG
   다이어그램**(도형+화살표)으로 렌더링돼야 한다(2026-07-21 렌더링 버그 수정
   — `Chat.vue`의 최종 렌더 경로는 `renderedMarkdown`/`renderStreamingMarkdown`이
   아니라 `setMessageForUser()`였다는 점에 주의, 향후 마크다운 렌더 관련
   버그 수정 시 이 함수도 반드시 확인할 것).
3. **BPMN 프로세스 생성·저장** — 전략맵 승인 후 `bpmn-process-generation-skill`로
   이어져 프로세스 초안이 뜨면 승인 → "저장" 버튼 클릭 → 실제 DB 저장까지
   확인한다(딥에이전트는 DB에 직접 쓰지 않는 정책이므로 이 버튼 클릭이
   필수임을 데모에서 짚어준다).

## 3. 전략 서비스 저장 검증 (API)

```bash
curl -s "http://localhost:8014/api/map?tenant_id=localhost" | python3 -m json.tool
```
재무/고객/프로세스/성장 4개 objective와 각 leading/lagging KPI, 그리고
BPMN 저장 이후라면 leading KPI의 `proc_def_id`가 방금 저장된 프로세스 id와
일치하는지 확인한다.

```bash
curl -s "http://localhost:8014/api/canvas?tenant_id=localhost" | python3 -m json.tool
```
9블록 모두 채워져 있는지 확인.

## 4. BSC 전략맵 보드 화면 (채팅 밖에서 다시 확인)

`/strategy-board`로 이동하면 채팅과 별개로 전략 서비스 그래프를 직접 읽어
그리는 전용 보드가 뜬다(`StrategyBoard.vue`) — 재무/고객/내부프로세스/학습·성장
4개 레인에 목표 카드가 배치되고, 인과관계는 카드 사이 실제 SVG 화살표로
연결된다. 채팅 안의 mermaid 다이어그램과 이 보드가 같은 데이터(전략
서비스 `/api/map`)를 서로 다른 방식으로 보여준다는 점을 함께 짚어준다.
`/analytics/ontology`(`OntologyExplorer.vue`, cytoscape 기반)는 같은 데이터를
온톨로지 그래프 관점으로 보여주는 별도 화면이니 시간이 되면 함께 보여줘도
좋다.

## 데모 후 보고

- 트리거 문장(자연어, 슬래시 명령 없음)과 스킬이 실제로 자동 기동됐는지
- `fetch_webpage` 호출 여부와 조회된 페이지 제목/요약
- 렌더링된 BMC 표 스크린샷, 렌더링된 BSC mermaid 다이어그램 스크린샷
- 저장된 objective/KPI 목록과 BPMN 프로세스 id, 그리고 KPI-프로세스 연결 여부
- `/strategy-board` 스크린샷
