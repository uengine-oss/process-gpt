---
name: process-gpt-demo
description: >
  이미 설치된 Process GPT 인스턴스를 전제로 데모 시나리오 중 하나를
  골라 시연하는 도우미. "데모 보여줘", "process gpt 데모", "휴가 신청 데모",
  "협력사 온보딩 데모", "에이전트와 대화", "/process-gpt-demo" 같은 요청이
  있을 때 트리거. 신규 설치가 필요하면 process-gpt-install 스킬로 위임한다 —
  이 스킬은 설치를 하지 않고, 이미 떠 있는 게이트웨이를 전제로만 동작한다.
---

# Process GPT 데모 도우미 (process-gpt-demo)

## 역할

이미 설치·기동된 Process GPT 인스턴스(게이트웨이 `http://localhost:8088`
또는 사용자가 지정한 호스트)를 대상으로, 아래 시나리오 중 사용자가
고른 것을 실제로 시연한다. 설치 자체는 이 스킬의 책임이 아니다 —
`process-gpt-install` 스킬에 위임한다.

## 0. 사전 점검

게이트웨이가 살아있는지 먼저 확인한다:
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088
```
200이 아니면(또는 다른 호스트를 쓴다면 그 주소로) 사용자에게 알리고
`process-gpt-install` 스킬로 먼저 설치/기동할지 물어본다 — 이 스킬은
설치 자체를 대신하지 않는다.

살아있으면 [references/demo-account.md](references/demo-account.md)의
고정 데모 계정(`demo@localhost` / `Demo1234!`, tenant `localhost`)으로
로그인 가능한지 확인한다. 계정이 없으면 그 문서의 idempotent 생성
스크립트로 먼저 만든다.

## 1. 시나리오 선택

AskUserQuestion으로 하나를 고르게 한다:

| 옵션 | 내용 | 상세 가이드 |
|---|---|---|
| **1. 프로세스 데모(간단)** | 휴가 신청 프로세스를 채팅으로 생성하고, 승인/반려 분기가 있는 실제 인스턴스를 끝까지 실행 | [references/scenario-1-basic.md](references/scenario-1-basic.md) |
| **2. 프로세스 데모(복합)** | PDF 업로드로 협력사 온보딩 프로세스 + 스킬 + 실제 deepagents 에이전트를 생성하고, 인스턴스 실행 중 스코어링 활동이 무인으로, 실제로 스킬을 참조하며 처리되는 것까지 확인 | [references/scenario-2-complex.md](references/scenario-2-complex.md) |
| **3. 에이전트와 대화** | 시나리오 2에서 만든 에이전트와 1:1 채팅 — 기본 에이전트 vs 딥 에이전트 모드 비교 | [references/scenario-3-agent-chat.md](references/scenario-3-agent-chat.md) |
| **4. 애드혹-프로세스 데모 설계 문서 보기(실행 안 함)** | 협력사 특성에 따라 동적으로 전문가 활동이 달라지는 AdWorks 패턴 — 설계 문서만, 실행/검증 없음 | [references/scenario-4-adhoc-adworks-design.md](references/scenario-4-adhoc-adworks-design.md) |
| **5. BSC 전략 수립 데모** | 회사 도메인 한 줄만 자연어로 던지면 `bsc-strategy-interview` 스킬이 슬래시 명령 없이 자동 기동돼, 회사 홈페이지를 `fetch_webpage`(WebSurfer 역할)로 실제 조사하고 BSC 전략맵·BMC를 수립 → `bpmn-process-generation-skill`로 이어 관련 프로세스까지 생성·저장 → `/strategy-board` 전용 화면에서 결과 확인 | [references/scenario-5-bsc-strategy.md](references/scenario-5-bsc-strategy.md) |
| **6. 전략 정합성 게이트 데모** | 프로세스/스킬 개선 설명을 전략맵과 비교해 관련 목표·KPI 후보와 기존 연결을 반환하고, 관련 항목 없음·서비스 실패·DMN 제외까지 승인 전 게이트로 확인 | [references/scenario-6-strategy-alignment.md](references/scenario-6-strategy-alignment.md) |
| **7. 실행 경로 고착화 데모** | Supabase MCP(`execute_sql`)로 LLM이 한 번 수행한 활동을 Python 코드로 고착화하고, 다음 실행을 LLM 추론 0회로 결정론적으로 재실행 — 프론트 없이 Supabase만 있으면 됨 | [references/scenario-7-deterministic-replay.md](references/scenario-7-deterministic-replay.md) |
| **8. Undo(실행 취소) 데모** | 시나리오 7에 이어지는 2편(별도 영상·별도 스펙): 이벤트 로그로부터 생성된 역연산 코드로 AI 실행의 부수효과를 원복하고, 정정 값으로 재실행 — 시나리오 7 선행 필수 | [references/scenario-8-deterministic-undo.md](references/scenario-8-deterministic-undo.md) |
| **9. Prompt Chaining 에이전틱 패턴 데모** | "시장조사 인사이트 체인" 프로세스 — 사람이 보고서를 제출하면, 트렌드 식별·이메일 초안 작성 2단계가 사람 개입 없이 딥에이전트(orchestration=deepagents)로 순차 자동 처리되며 각 단계가 이전 단계 출력을 참조(inputData 체이닝)하는 것까지 생성과 실행 양쪽 다 확인 | [references/scenario-9-prompt-chaining.md](references/scenario-9-prompt-chaining.md) |
| **전체 순서대로(1→2→3)** | 위 세 개를 이어서 시연 | 위 세 문서를 순서대로 |

### 튜토리얼 영상 시리즈 (Lv.1~Lv.5)

docs 튜토리얼(`docs/doc-site/content/ko/tutorial/tutorial-lv*.md`)의 현대화판
데모 — deepagents 기본, crewai 비노출. 각 편은 이전 편의 산출물(프로세스
정의·에이전트)을 확장식으로 이어받으므로 **순서대로** 진행하는 것이 원칙이다.
완성 영상은 `demo-recordings/tutorial-lv<N>-*-narrated.mp4`에 있고, 녹화
스크립트는 `scripts/record_tutorial_lv<N>_demo.mjs`(공용 슬라이드 헬퍼
`scripts/lib_tutorial_slides.mjs` 사용)다. Lv.3부터는 BPMN 편집기 직접 편집
과정 자체가 교육 목표다(자연어 생성은 골격까지).

| 편 | 내용 | 상세 가이드 |
|---|---|---|
| **Lv.1 프로세스 생성과 실행** | 채팅으로 영업 제안서 작성 프로세스 생성 → 저장 → 인스턴스 실행 → COMPLETED 기본 사이클 | [references/scenario-tutorial-lv1.md](references/scenario-tutorial-lv1.md) |
| **Lv.2 AI 에이전트 제안서 작성** | 조직도 에이전트 생성·학습(mem0) + 규칙성 지식 DMN 이중화 + deepagents 무인 초안 | [references/scenario-tutorial-lv2.md](references/scenario-tutorial-lv2.md) |
| **Lv.3 조건 분기와 피드백 반영** | 편집기에서 게이트웨이·conditionFunction·체크포인트 편집, 반려→루프백→재작성→승인 실증 | [references/scenario-tutorial-lv3.md](references/scenario-tutorial-lv3.md) |
| **Lv.4 ERP 데이터 연동 재고 관리** | 로컬 Supabase 데이터소스 연동, MRP 에이전트, 재고 충분/부족 분기와 실제 재고 수치 변화 | [references/scenario-tutorial-lv4.md](references/scenario-tutorial-lv4.md) |
| **Lv.5 멀티플 인스턴스 뉴스레터** | 확장 서브프로세스 + determinationCode 자동 추론으로 자식 인스턴스 병렬 생성, 고객별 개인화 | [references/scenario-tutorial-lv5.md](references/scenario-tutorial-lv5.md) |

## 2. 시나리오 3의 전제조건 — 시나리오 2가 먼저 필요

시나리오 3은 시나리오 2에서 생성되는 스킬 연결 에이전트가 있어야 의미가
있다. 사용자가 시나리오 3만 단독으로 골랐다면, 먼저 DB로 확인한다:
```sql
select id, username, skills from users where is_agent=true and coalesce(skills,'') <> '';
```
결과가 없으면(또는 원하는 에이전트가 없으면) 시나리오 2를 먼저 실행할지
사용자에게 물어보고, 동의하면 scenario-2-complex.md부터 진행한 뒤 3으로
넘어간다.

## 3. 데모 녹화 + TTS 내레이션 (기본 적용)

시나리오를 실제로 실행할 때는 [references/recording-and-narration.md](references/recording-and-narration.md)
절차대로 Playwright 영상 녹화를 기본으로 남긴다. `.env`에 실제
`OPENAI_API_KEY`가 있으면 OpenAI TTS로 내레이션을 입힐지 사용자에게
먼저 묻는다(기본값: 예) — 시나리오 실행 전에 한 번만 물으면 된다.
최종 산출물은 `demo-recordings/<scenario-name>-narrated.mp4`(또는
내레이션 없이 무음 mp4).

## 4. 영문 데모 녹화 시 주의사항 (전체 시나리오 공통)

사용자가 "영문으로", "English version" 등 영어 데모를 요청하면 **내레이션만
번역해서 덧씌우는 것으로는 부족하다** — 화면 자체(제품 UI + 채팅에서 생성되는
콘텐츠)가 전부 영어여야 진짜 영문 데모다. 아래 절차를 반드시 순서대로 따른다.

1. **UI 언어를 English로 전환한다.** 계정 설정(`/account-settings`) 우상단의
   언어 드롭다운(기본값 `한국어`)에서 `English`를 선택한다. 이 설정은 계정별
   `localStorage`에 저장되며 **로그인 여부와 무관하게 유지**된다(로그인 페이지
   자체도 영어로 뜬다). Playwright로는 한 번 전환한 뒤
   `context.storageState({ path })`로 저장해두고, 이후 녹화용 브라우저
   컨텍스트를 `newContext({ storageState })`로 재사용하면 매번 전환할 필요가
   없다. 로그인 화면부터 보여주고 싶으면 저장된 state에서 `auth-token`
   키만 지운 "로그아웃+영문" state를 별도로 만들어 재사용한다(언어 설정은
   유지된 채 로그인 폼만 뜬다).
   - 주의: 일부 라벨(`지식 베이스`, `폴더 업로드` 등)은 아직 i18n 미적용이라
     English 모드에서도 한국어로 남아있을 수 있다 — 실제로 확인하고, 남아있는
     한국어 라벨은 스크립트 선택자에서 그대로(한국어로) 참조해야 한다(예:
     탭 이름은 "에이전트에 맡기기"가 아니라 "Agent Delegation"으로 바뀌지만
     "지식 베이스" 버튼은 그대로다 — 매번 실제 스크린샷으로 확인 후 선택자를
     정할 것, 추측 금지).
2. **채팅 프롬프트 자체를 영어로 보낸다.** 그런데 **UI 언어 전환과 프롬프트
   언어만으로는 에이전트의 응답 언어가 보장되지 않는다** — 실측 결과,
   `bpmn-process-generation-skill`의 지침 자체가 한국어로 작성돼 있어 영어로
   질문해도 에이전트가 한국어로 응답하는 경우가 있었다. 최초 응답이 한국어면,
   그 다음 사람 응답 차례(request_human_input 승인 등)에서 **"IMPORTANT:
   from now on, respond only in English for the rest of this conversation —
   all messages, questions, skill names, and generated content must be in
   English." 같은 명시적 지시를 승인 내용과 함께 자유 입력(직접 입력) 칸에
   같이 넣어 제출**한다. 이후 프로세스명·활동명·스킬명·산출물이 전부 영어로
   바뀌는지 반드시 화면으로 확인한 뒤 다음 단계로 진행한다(확인 없이
   진행하면 뒷단계도 계속 한국어로 나온다).
3. **스킬/에이전트/폼도 전부 새로 영어로 만든다.** 이미 한국어로 만들어둔
   프로세스의 SKILL.md/에이전트/폼을 재사용하지 말고, 이번 대화에서 새로
   생성된 영어 스킬 슬러그·프로세스 ID로 스킬 파일(`/app/skills/<tenant>/local/
   <skill>/SKILL.md`)과 에이전트 사용자 행, `tenant_skills`, `form_def`를
   전부 새로 만든다(같은 tenant 안에 한국어 버전과 영어 버전 스킬 파일이
   서로 다른 슬러그로 공존해도 무방).
4. **인스턴스 실행 결과가 실제로 영어인지, 그리고 실제로 체이닝됐는지 반드시
   검증한다.** 실측 결과 다음 두 실패 모드가 실제로 발생했다:
   - 자동 단계의 산출물이 **영어 대신 한국어로** 나오는 경우(에이전트가 응답
     언어 지시를 잊어버림).
   - 산출물이 **직전 단계 출력을 참조하지 않고** 일반적인 내용을 지어내는
     경우(체이닝 조회 도구를 에이전트가 스스로 호출하지 않아 발생 — 재현성
     있는 실제 버그다. 재시도해도 같은 방식으로 계속 실패할 수 있다).
   두 경우 모두 언어/출처를 실제 텍스트로 대조해서 확인하고, 실패했으면
   `todolist` 행을 `status='IN_PROGRESS', draft_status=NULL, draft=NULL,
   consumer=NULL, output={}`로 되돌려 재시도한다. 여러 번 재시도해도 같은
   증상이 반복되면, 해당 활동의 `instruction`/`query`에 **직전 단계의 정확한
   산출물 텍스트를 그대로 인용문으로 박아 넣어** 체이닝 조회 도구 호출에
   의존하지 않도록 만든 뒤 재시도한다(이번 세션에서 이 방법으로 해결됨 —
   근본 수정이 아니라 우회이므로, 정직하게 "이 방식으로 우회했다"고
   보고한다).
5. **최종 보고에 언어 이슈를 정직하게 남긴다.** "영문 데모"라고 보고하려면
   화면 UI·채팅 대화·BPMN 다이어그램·최종 산출물이 전부 실제로 영어인지
   스크린샷으로 확인한 결과를 근거로 들 것 — 내레이션만 영어이고 화면은
   한국어인 채로 "영문 데모"라고 부르지 않는다.

## 5. 공통 원칙

- 각 시나리오 문서는 그 자체로 완결된 절차다 — 순서대로 그대로 따라가면
  된다. DB 조회 SQL, API 호출 예시, 알려진 함정(troubleshooting 상호
  참조)이 전부 포함돼 있다.
- 시연 중 새로운 이슈(문서에 없는 에러)를 만나면 먼저
  `process-gpt-install/references/troubleshooting.md`를 대조하고, 없으면
  해결한 뒤 그 문서와 `INSTALL_MEMORY.md`에 새 항목으로 추가한다(이 스킬이
  아니라 `process-gpt-install` 쪽에 축적 — 트러블슈팅 지식은 설치 스킬에
  모아둔다).
- 각 단계마다 스크린샷/DB 조회 결과를 남기고, 데모가 끝나면 시나리오
  문서의 "데모 후 보고" 항목대로 사용자에게 요약 보고한다.
- 파괴적 조치(기존 인스턴스/워크아이템 삭제, 프로덕션 DB 직접 수정 등)는
  반드시 사용자 승인 후 실행한다. 이 스킬에서 다루는 SQL은 데모용 로컬
  환경 기준 조회/보정 위주다.
