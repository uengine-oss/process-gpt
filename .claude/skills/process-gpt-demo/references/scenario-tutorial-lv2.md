# 시나리오 — 튜토리얼 Lv.2: AI 에이전트를 활용한 제안서 작성 (영상 시리즈 2/5)

> **튜토리얼 영상 시리즈 2/5** — `docs/doc-site/content/ko/tutorial/tutorial-lv2.md`
> ("AI 에이전트를 활용한 제안서 작성")의 **현대화판**이다. 원본 튜토리얼은
> 구버전 화면(MCP 수동 등록·연구방식 드롭다운 등) 기준으로 쓰였으나, 현재
> 제품의 기본 오케스트레이션은 **deepagents**이며 crewai 계열은 이 시리즈에서
> 다루지 않는다(연구방식 드롭다운을 열지 말 것).
>
> **1편에서 이어받은 것**: 1편(scenario-tutorial-lv1.md)이 만든 proc_def
> `b2f50721_3a7b_4f83_975e_cc046c8618c6` "영업 제안서 작성"(선형 2단계). 이 편은
> 그 프로세스의 **제안서 작성 단계를 AI 에이전트가 무인 수행**하도록 확장한다.
> **proc_def를 삭제·재생성하지 말 것.**
>
> **3편에 넘길 것**: 여기서 만든 에이전트·조직도·확장된 3단계 proc_def(task3
> "제안서 확인" 사람 단계 포함)를 3편(조건 분기/게이트웨이 + 피드백 반영)이
> 재사용한다. task3는 3편이 승인/반려 게이트웨이를 붙이도록 남긴 사람 결정
> 지점이다. **삭제하지 말 것.**

전제: [demo-account.md](demo-account.md)의 고정 계정(`demo@localhost` /
`Demo1234!`, tenant `localhost`)으로 로그인. 게이트웨이 기본 `http://localhost:8088`.

---

## 0. 실측값 (이번 실행 기준 — 재현 시 매번 갱신)

| 항목 | 값 |
| --- | --- |
| proc_def id (1편에서 이어받음) | `b2f50721_3a7b_4f83_975e_cc046c8618c6` "영업 제안서 작성" |
| 생성 에이전트 id / 이름 | `fa3a2d21-cd7c-4078-931a-91220b4fd9e1` / **제안서 작성 에이전트** |
| 에이전트 role / model | 영업 제안서 초안 작성 자동화 / `gpt-4.1`, `is_agent=true, agent_type='agent'` |
| 에이전트 소속 팀 | **영업팀** (team id `9558cc13-ab91-4b6d-b772-ccce83df23b3`) |
| 조직도 저장 위치 | `configuration` 테이블 key=`organization` (root→영업팀→에이전트 노드) |
| 학습 지식 저장 위치 | **`vecs.memories`** (mem0, `metadata->>'agent_id'`로 키잉) + 조회 RPC `public.get_memories(agent,lim)` |
| 에이전트 persona/goal | 지역별 단가·납기·인증 표를 **프로필에도** 임베드(런타임 반영 보장, §5 참고) |
| 확장된 활동 구성 | task1 요청사항 입력(고객) → **task2 제안서 초안 생성(에이전트, deepagents, agentMode=draft)** → task3 제안서 확인(영업 담당자) |
| task2 agent 바인딩 | `activity.agent = fa3a2d21…`, `orchestration="deepagents"`, `agentMode="draft"` |
| task2 폼 | **report-field** `proposal_draft` (Report형 폼, `..._task2_form`) |
| task3 폼 | report-field `proposal_draft`(읽기전용) + textarea `review_comment` (`..._task3_form`) |
| 쇼케이스 완주 인스턴스 | `b2f50721_3a7b_4f83_975e_cc046c8618c6.5a88c640-dfcb-4674-92bf-c4f993c07c6b` (COMPLETED) |
| 쇼케이스 task2 워크아이템 | `076dcdbe-3207-4816-aefa-e518bdc46f0d` (초안 보유) |
| deepagents 무인 처리 소요 | task1 제출 후 약 **40~60초** 내 초안 생성(첫 폴에서 이미 draft 존재) |
| 데모 계정 auth_uid | `bd0e585b-3828-496c-92aa-3f93f336d3d3` |

DB 검증 (`docker-infra`의 `.env` 사용):
```bash
cd /Users/uengine/process-gpt/docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }
# 확장된 활동 구성
PSQL "select a->>'id', a->>'name', coalesce(a->>'orchestration','-'), coalesce(a->>'agentMode','-'), coalesce(a->>'agent','-') from public.proc_def, jsonb_array_elements(definition->'activities') a where id='b2f50721_3a7b_4f83_975e_cc046c8618c6';"
# 학습 지식(mem0)
PSQL "select count(*) from public.get_memories('fa3a2d21-cd7c-4078-931a-91220b4fd9e1',100);"
# 완주 상태
PSQL "select status from bpm_proc_inst where proc_inst_id='b2f50721_3a7b_4f83_975e_cc046c8618c6.5a88c640-dfcb-4674-92bf-c4f993c07c6b';"
```

---

## 1. 빌드타임 — 조직도 에이전트 생성 (실화면)

`/organization` → 좌측 `조직도 관리`/`에이전트 생성` 탭, 우측 조직도(APEXCHARTS
트리). 조직도 데이터는 `configuration` key=`organization`(`{chart:{...}}`)에 저장된다
(로컬 tenant는 초기 config 행이 없어 root 1개만 뜨는 기본 상태 → 팀·에이전트를
직접 만들어야 함).

1. **팀 생성**: `조직도 관리` 탭 → **"팀 생성"** 버튼 → 다이얼로그의 `팀명` 필드
   ("영업팀") → **"추가"**. team 노드는 `{id, data:{id,name,isTeam:true,img},children:[]}`.
2. **에이전트 생성(AI)**: `에이전트 생성` 탭(하위 탭 `신규 에이전트`) →
   `.user-input-generator-textarea textarea`(라벨 "생성하고싶은 에이전트를
   입력하세요")에 자연어 입력 → **"AI로 에이전트 생성"** 클릭. 이는 LLM(gpt-4o)이
   name/role/goal/persona/tools를 채워주는 `UserInputGenerator`이며 **DB 저장은
   안 함**(폼만 채움). 이름/역할/목표/페르소나, **도구(MCP)** 콤보박스(라벨 "도구"),
   모델을 확인/보강 후 **"저장"** → `users`(is_agent=true, agent_type='agent')에 1행.
   - **함정**: `.user-input-generator-textarea textarea`는 hidden sizer까지 2개가
     잡히므로 `:not([aria-hidden="true"])`의 first를 쓴다.
   - **녹화 요령(중복 방지)**: 최종 인스턴스가 이미 이 에이전트를 쓰고 있으므로
     녹화에서는 생성 다이얼로그 UI(자연어 입력+생성 버튼+프로필/도구 콤보)를
     **시연만** 하고 **저장은 누르지 않는다**(누르면 중복 에이전트 생성). 실제
     저장된 에이전트는 사전 준비된 `fa3a2d21…`이며 조직도에 이미 보인다.

이번 실행에서는 위 절차 대신 **정확한 노드 shape로 DB에 직접** 영업팀+에이전트를
넣었다(조직도 트리 shape가 까다로워 실화면 저장 대신 보정; 화면 시연은 진행):
```sql
-- 에이전트(users) 생성: persona/goal에 지역별 단가·납기·인증 표를 임베드(§5)
-- configuration key='organization' 에 root→영업팀→에이전트 트리 저장
```

## 2. 빌드타임 — 에이전트 교육 (실화면)

`/agent-chat/<agent_id>` → 좌측 패널에 목표/페르소나/도구/스킬/모델 + 모드 탭
(`대화 모드`/`학습 모드`/`질의 모드`/`지식 관리`)과 `비즈니스 규칙 +`.

1. **학습 모드**: "학습 모드" 클릭 → 입력창(placeholder **"메시지 입력"**)에
   지역별 단가/납기/인증 표를 붙여넣고 **`.cp-send`(종이비행기)** 클릭(또는
   Enter). 백엔드 `POST /completion/multi-agent/chat`(auth 불필요, body
   `{text, chat_room_id:"<agent>-learning", options:{agent_id, is_learning_mode:true}}`)이
   **mem0**로 저장한다. 에이전트가 "…잘 학습했습니다"로 응답(검증됨).
2. **지식 관리 탭**: 저장된 지식이 표로 남는다(내용/생성일/삭제). 프론트는
   RPC `get_memories(agent,lim)`로 조회 → **`vecs.memories`**.
   - ⚠️ **함정(#51, 이번에 발견·수정)**: 이 설치의 DB에 `get_memories` 등 mem0
     RPC가 **누락**돼 있어 지식 관리 탭이 항상 "메모리가 없습니다"로 비었었다.
     `vecs.memories`는 mem0가 첫 학습 때 지연 생성하므로 DB 초기화 때 만들어지는
     `docker-infra/volumes/db/vecs.sql`의 함수가 스킵된 것. `vecs.sql` 재적용 +
     grant + `NOTIFY pgrst,'reload schema'`로 해결(troubleshooting #51,
     PRODUCT_CHANGES_REPORT #2). 재현 시 먼저 이 상태를 확인할 것.

## 3. 빌드타임 — DMN 결정 테이블 등록 (규칙성 지식의 이중화)

> **왜 mem0 + DMN 이중화인가**: Lv2에서 학습시키는 지역별 단가/납기/인증 표는
> 서술형 지식이 아니라 **조건(지역)→결과(최소수량·단가·배송료·납기·인증)의
> 규칙성 지식**이다. 벡터 메모리(mem0)는 의미 검색이라 이런 결정 규칙의 회수가
> 불안정할 수 있으므로, 같은 표를 **DMN 결정 테이블**로도 등록해 태스크 수행 시
> 결정 로직으로 쓰이게 하는 것이 제품 권장 사용법이다.

**DMN 결론(코드/실측 확인)**: DMN은 **지원된다**. 에이전트 소속 DMN 결정
테이블은 **`proc_def` 행 하나**로 저장된다 — `type='dmn'`, **DMN 1.3 XML을
`bpmn` 컬럼**에, 소유 에이전트는 **`agent_id`** 컬럼으로 연결. 다중 입력/다중
출력 결정 테이블을 그대로 담을 수 있다.

- **등록(이번 실행)**: 지역(region)→(최소수량·기본단가·배송료·납기·필수인증)
  5-출력 결정 테이블을 DMN 1.3 XML로 작성해 proc_def에 직접 넣었다.
  ```
  id=dmn_region_proposal_policy, name="지역별 단가·납기·인증 규칙",
  type='dmn', agent_id=fa3a2d21…, tenant_id='localhost', bpmn=<DMN 1.3 XML>
  hitPolicy=UNIQUE, 규칙 3행(KR/US/EU)
  ```
- **화면(실화면, 검증됨)**: 라우트 **`/dmn/<dmn_id>`**(`DmnChat.vue`)가 dmn-js
  결정 테이블 에디터로 표를 그대로 렌더한다(When 지역 | Then 최소수량 · 단가 ·
  배송료 · 납기 · 인증). 에이전트 채팅 좌측 **"비즈니스 규칙"** 목록에도
  이 DMN이 나타난다(realtime 구독 `proc_def agent_id=eq.<agent>`).
  - ⚠️ **함정**: type='dmn' proc_def는 좌측 전역 "프로세스" 목록에도 뜨는데,
    거기서 클릭하면 `/definitions/<id>`(BPMN 디자이너)로 가 **빈 캔버스**가 뜬다
    (BPMN 렌더러가 DMN을 못 그림). 결정 테이블을 보려면 **`/dmn/<id>`**로 직접
    가거나 에이전트 채팅의 "비즈니스 규칙" 항목을 클릭할 것.
- **런타임 사용(정확한 실상)**: deepagents 에이전트는 `get_bpm_tools()`로 붙는
  `get_process_list(type='dmn')`·`get_process_detail(id)`로 이 DMN의 **원본 XML을
  읽어** 추론에 쓸 수 있다. **단, 서버측 FEEL 결정엔진은 없고**(예약어
  `dmn_rule` 도구는 아직 미구현), 결정 로직 반영은 LLM 추론이다. 그래서 이번
  런타임의 값 반영은 §5처럼 **persona 임베드로 보장**했고, DMN은 "같은 규칙을
  결정 테이블로도 관리·조회 가능"함을 보여주는 자산이다(내레이션도 이 선에서만
  주장 — "결정론적으로 평가했다"고 하지 않는다).

> **왜 이중화가 정당한가**: mem0(의미검색)는 서술형 교육, DMN(결정 테이블)은
> 규칙성 지식의 구조적 관리·조회. 둘 다 에이전트에 연결돼 제안서 작성 지식의
> 서로 다른 표현을 제공한다.

## 4. 빌드타임 — 프로세스에 에이전트 결합 (실화면 + BPMN 보정)

`/definitions/<proc_def_id>` 디자이너(읽기 모드 "읽기 모드입니다"). BPMN 스윔레인은
proc_def의 **`bpmn` 컬럼(XML)**에서 렌더된다 — `definition.activities`(런타임 엔진이
읽는 곳)와 **별개**다. 따라서 활동을 확장하면 **둘 다** 갱신해야 화면·런타임이 맞는다.

- **task2 더블클릭**: `[data-element-id="task2"]`를 `dblclick({force:true})` →
  패널(설정/**에이전트**/참조 정보/폼 편집/폼 미리보기/단위 테스트/PI Flag).
- **에이전트 탭**: `에이전트 연구 방식` = **딥 에이전트**(값 `"deepagents"`),
  `완료 수준` = **초안**(값 `"draft"`), **미리 설정된 에이전트 사용** 체크 →
  에이전트 선택. 패널 저장 시 `definition.activities[].{agent,orchestration,agentMode}`
  에 기록된다.
- **폼 편집 탭**: task2 폼을 **Report형**(`report-field proposal_draft`)으로 확인/보강.

이번 실행에서는 UI 패널 저장이 까다로워 **DB로 확장을 확정**했다(화면 패널 설정
장면은 실녹화):
- `definition.activities`: task2 rename("제안서 초안 생성") + agent/deepagents/draft,
  task3("제안서 확인", 영업 담당자) 추가, sequences 재배선(task2→task3→end).
- `bpmn` XML도 동일 3단계로 재생성(task2 uengine:json에 agent/orchestration/agentMode
  포함 → 패널이 딥에이전트/초안/미리설정 에이전트를 그대로 표시함, 검증됨).
- task2 폼을 report-field로 교체, task3 폼 신규 생성.

## 5. 런타임 — 무인 수행 → 사람 확인 → COMPLETED (검증됨)

단일 데모 계정 한계상 실행/전이는 `/completion/complete`를 JWT로 직접 호출하되,
화면에는 인스턴스/워크아이템 상태가 보이게 한다(1편과 동일 패턴).

1. **task1 제출(고객 요청)** → 인스턴스 시작:
   ```
   POST {gw}/completion/complete
   { "input": { "process_definition_id":"<pid>", "process_instance_id":"<pid>.<uuid>",
     "activity_id":"task1", "email":"demo@localhost", "user_id":"<auth_uid>", "username":"demo",
     "form_values": { "<pid>_task1_form": { "request_details":"미국(북미) 바이어에게 …50개 견적…" }, "request_details":"…" } } }
   ```
   (⚠️ `email` 필수 — 빼면 500. form_values 키는 폼 id 전체 + 평탄 키 병행.)
2. **task2 무인 처리**: polling-service가 task2를 집어 `agent_mode=DRAFT,
   agent_orch=deepagents`로 deepagents에 디스패치. **바인딩 원리(검증됨)**:
   `activity.agent`가 워크아이템 `user_id` 맨 앞에 prepend되고
   (`database.py` next-workitem 생성부), deepagents는 `workitem.user_id`의 첫
   에이전트로 프로필을 로드한다(`workitem_processor.py:4793`). 약 40~60초 내
   `draft` 필드에 제안서 초안 생성.
   - **DRAFT 동작(중요)**: draft 모드는 초안을 `todolist.draft`에 채우고 워크아이템은
     `IN_PROGRESS`로 **사람 제출을 기다린다**(자동 전이 아님). 화면상
     워크아이템 상세 → **"에이전트에 맡기기"** 탭에 `Agent 작업완료`, 요청 유형
     `deepagents`, 작업 결과(초안)가 보인다.
3. **초안이 학습/정책을 실제 반영(내레이션 근거, 실측)**: 고객 요청이 "미국(북미)
   …50개"였고, 생성된 초안은 **수량 50개 · 단가 USD 320/개(FOB) · 총액 USD
   16,000 · 배송료 약 180,000원 · 납기 7~10일 · FCC 인증 필수 · NDA 가능성**을
   담았다 — 이는 학습·프로필에 넣은 **US(북미) 정책과 정확히 일치**한다(KR/EU가
   아니라 US를 골라 적용). 임의 수치가 아니라 정책 그대로다.
   - **왜 프로필에도 넣나(중요)**: deepagents 서브에이전트 프롬프트는
     role/goal/persona/tools/skills로만 구성되고 **mem0를 읽지 않는다**
     (`services/deepagents/core/agents/subagents.py`). 그래서 런타임 반영을
     보장하려면 지역별 표를 에이전트 **persona/goal에도** 임베드해야 한다.
     학습 채팅(mem0)은 사용자용 교육 UI·지식 관리 근거, 실행 반영은 프로필 경유
     — 두 경로를 함께 채운다(#51 메모 참조).
4. **사람 확인 제출(task2 수락 → task3)**: draft를 사람이 검토·제출하면 task2 DONE →
   task3 생성. task3(사람 확인)도 제출 → **`bpm_proc_inst.status=COMPLETED`**.
   전이 타임라인(검증됨): `task1 DONE → task2(deepagents draft) DONE → task3 DONE → COMPLETED`.

`task_id`+`email`로 후속 활동 제출(activity/proc는 DB 자동 조회). 화면은
`/instance-viewer/<inst>`(전 활동 통과 표시)와 워크아이템 상세로 확인.

---

## 6. 만난 함정 / 버그

- **#51 (신규, 이번에 발견·수정)**: 에이전트 "지식 관리" 탭이 항상 "메모리가
  없습니다" — `get_memories` 등 mem0 RPC가 DB에 누락(vecs.memories 지연 생성 →
  DB init 때 함수 생성 스킵). `vecs.sql` 재적용으로 해결. troubleshooting.md #51,
  PRODUCT_CHANGES_REPORT.md #2, INSTALL_MEMORY.md #34에 기록.
- **BPMN vs definition 이원화(주의, 버그 아님)**: 스윔레인 렌더는 proc_def `bpmn`
  XML, 런타임 엔진은 `definition.activities`. 활동을 DB로 확장하면 **둘 다** 갱신
  필요(안 하면 화면은 옛 구조, 런타임은 새 구조로 어긋남).
- **deepagents는 mem0 미조회**: 학습만으로 런타임 반영이 보장되지 않는다(§5-3).
- **nginx #25 재확인**: 이번 실행 시점 nginx는 이미 `base-agent-langchain-react:8000`로
  정상(1편/PRODUCT_CHANGES_REPORT #1에서 수정됨).

---

## 데모 후 보고 (이번 실행 결과)

- 생성 에이전트: `fa3a2d21-cd7c-4078-931a-91220b4fd9e1` **제안서 작성 에이전트**
  (role 영업 제안서 초안 작성 자동화, model gpt-4.1, 팀 영업팀), 도구=없음(런타임
  MCP 의존 회피). 학습 지식 저장=`vecs.memories`(agent_id 키), 조회 RPC get_memories.
- DMN 결정 테이블: `dmn_region_proposal_policy` "지역별 단가·납기·인증 규칙"
  (proc_def `type='dmn'`, `agent_id=fa3a2d21…`, DMN 1.3 XML in `bpmn`, 5-출력/3-행).
  화면은 `/dmn/<id>`. 런타임은 agent가 get_process_detail로 조회 가능(결정엔진 없음).
- 최종 영상: `demo-recordings/tutorial-lv2-ai-agent-proposal-narrated.mp4`
  **210.48s(3.5분), h264/aac, mean_volume −24.9dB, assemble PASS**, voice marin.
- 녹화가 트리거한 새 인스턴스(`…a213218d…`)는 task2 DRAFT가 사람 제출 대기 상태로
  남아 있음(무해한 데모 산출물). 쇼케이스/결과 화면은 완주 인스턴스 `…5a88c640…` 사용.
- proc_def 확장: task1(요청사항 입력, 고객) → **task2(제안서 초안 생성, 에이전트
  fa3a2d21, orchestration=deepagents, agentMode=draft)** → task3(제안서 확인, 영업
  담당자). task2 폼=Report(report-field proposal_draft).
- 실행 인스턴스 `…5a88c640…`: `task1 DONE → task2(deepagents draft, ~40–60s) DONE
  → task3 DONE → COMPLETED`. 초안이 US 정책(50개·USD320·FOB·7–10일·FCC) 반영 확인.
- 3편이 이어받을 상태: 확장된 3단계 proc_def(task3=사람 확인 결정 지점), 영업팀·
  에이전트. 3편은 task3 이후 승인/반려 게이트웨이 + 피드백 재작업을 붙인다.
