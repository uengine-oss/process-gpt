# 시나리오 2 — 프로세스 데모(복합): 협력사 온보딩 (PDF→BPMN + 스킬/에이전트 + 자율 실행)

PDF 규정 문서를 업로드해 BPMN 프로세스 + 스킬 + 실제 deepagents 에이전트를
함께 생성하고, **실제 인스턴스를 실행해서 특정 활동(스코어링)이 사람 개입
없이 자동으로 처리되며 그 과정에서 실제로 스킬 파일을 참조하는 것**까지
확인한다. "생성만 하고 끝"이 아니라 "생성된 에이전트가 실전에서 스킬을
실제로 쓰는지"를 검증하는 것이 이 시나리오의 핵심이며, 이번 세션에서 이
부분을 검증하다가 **deepagents 쪽의 실제 버그 2건을 발견해 고쳤다** — 그걸
모르고 데모하면 "스킬이 연결됐다"는 화면만 보고 실제로는 전혀 안 쓰이는
것을 못 알아챌 수 있다. 아래 "사전 점검"을 반드시 먼저 할 것.

전제: [demo-account.md](demo-account.md)의 고정 계정으로 로그인돼 있어야
한다.

## 0. 사전 점검 — 스킬이 실제로 로드되는지 먼저 확인

과거(이번 세션 이전)에 생성된 에이전트를 재사용할 계획이라면, 데모 전에
반드시 아래를 확인한다. 안 그러면 "무인 처리는 되는데 사실 스킬은 전혀
안 쓰인" 상태로 데모하게 된다(troubleshooting.md **#47/#48** 참고).

```sql
select id, username, skills from users where is_agent=true;
```
`skills`가 비어 있으면(예: 이전 세션에서 만든 에이전트) 아래로 직접 채운다
(proc_def.definition.activities[].skills 값과 맞춰서):
```sql
update users set skills='<skill-slug>' where id='<agent-uuid>';
```

그리고 실제 인스턴스를 한 번 돌려서 `docker logs deepagents`에
`Cannot load skills from ...: path_not_found` 또는 `Skills load errors`가
찍히는지 확인한다. 찍힌다면 troubleshooting **#48**(샌드박스 마운트/경로
변환 버그, 이번 세션에 3곳 수정 완료)이 아직 반영 안 된 이미지일 수 있다 —
`services/deepagents`를 최신으로 재빌드하고, **반드시**
`docker rm -f deepagent-sandbox-<tenant>`로 사촌 컨테이너를 지운 뒤
(재사용되는 컨테이너라 재빌드만으론 새 마운트가 안 걸림) 다시 시도한다.

## 1. 생성 (PDF 업로드 → BPMN + 스킬 + 에이전트)

이 흐름 자체는 이전 세션들에서 이미 충분히 검증됐다 — 여기서는 절차만
요약한다. 상세 트러블슈팅은 troubleshooting.md #40~#43 참고.

1. `/definition-map`에서 파일 입력(`input[type="file"]`)에
   `assets/vendor-onboarding.pdf` 지정 → "첨부한 협력사 온보딩 및 리스크
   실사 프로세스 규정 문서를 기반으로 프로세스를 만들어줘." 전송.
2. "프로세스 생성 강도를 선택해주세요" → "표준 강도로 진행해줘."
3. `todolist`에서 `draft_status`가 `HUMAN_ASKED`가 될 때까지 폴링(DB로
   확인, 사이드바 텍스트 매칭 금지 — 과거 시도가 섞여 오탐 잦음):
   ```sql
   select status, draft_status from todolist where id='<workitem_id>';
   ```
4. `events`에서 `event_type='waiting_for_user'` 최신 행의
   `data.questions[]` 확인 — 보통 `skills_batch`/`agents_batch`/`dmn_batch`
   3개 질문(단, DMN은 재사용되는 게이트웨이가 있을 때만 — troubleshooting
   #43). `agents_batch`가 안 보이면 샘플 문서 조건이 깨진 것(troubleshooting
   #41 참고).
5. 채팅 UI에서 체크박스로 뜬 항목을 선택하고 "응답 제출". 승인/반려
   2버튼으로 잘못 렌더링되면 troubleshooting #40의 SQL 우회 사용.
6. `draft_status='COMPLETED'`까지 폴링 후 저장 확인:
   ```sql
   select definition::text from proc_def where id='<proc_def_id>';
   ```
   `skills`, 각 activity의 `agentMode`/`orchestration`/`agent`(uuid)가
   채워져 있어야 하고, `saved_skills[].uploaded=true` +
   `volumes/deepagents-skills/<tenant>/local/<skill>/SKILL.md` 파일 실존까지
   확인한다(troubleshooting #42).

이번 세션에서 재사용한 proc_def(참고용, 매번 새로 생성하면 id가 다름):
`857b4817_72b8_4620_a01e_822f7a47d649` — 활동 6개, 스킬
`partner-risk-score-report`, 에이전트 `협력사 리스크 평가 도우미`
(`c9075c88-beef-44df-9fcc-21c423fb00a3`, 역할 "리스크관리팀").

## 2. 인스턴스 실행

`/todolist` 대신 직접 API로 실행(첫 활동 역할="구매팀"은 실제 배정 가능한
사용자가 없어 데모 계정을 명시적으로 바인딩해야 함 — 시나리오 1과 동일한
이유, 아래 3번 참고). Playwright로 로그인 후 JWT 추출([demo-account.md](demo-account.md)
스니펫 참고), 첫 활동("협력사 정보 접수 및 온보딩 신청서 제출") 제출:

```bash
curl -X POST "http://localhost:8088/completion/complete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input": {
    "process_definition_id": "<proc_def_id>",
    "process_instance_id": "<proc_def_id>.<uuid>",
    "activity_id": "<첫 활동 id>",
    "email": "demo@localhost",
    "user_id": "<auth_uid>",
    "username": "demo",
    "form_values": { "<proc_def_id>_<첫활동id>_form": { "business_registration": "...", "financial_statement": "...", "organization_chart": "...", "onboarding_application": "..." } }
  }}'
```
파일 필드는 실제 업로드 없이 파일명 문자열만 넣어도 인스턴스는 정상
시작된다(다만 스코어링 활동이 "자료를 찾을 수 없다"며 값을 비워서 제출할
수 있음 — 이것 자체가 스킬이 실제로 절차를 따른다는 증거이기도 하다, 4번
참고).

## 3. 담당자 배정 — 스코어링 활동은 이미 실제 사용자(에이전트)에 배정됨

시나리오 1과 다른 점: proc_def 생성 시 "리스크관리팀" 역할의 `roles[].endpoint`가
이미 실제 에이전트 uuid로 채워져 있다(에이전트 생성 승인 시점에 연결됨).
즉 `execute_process`/직접 API 호출이 첫 활동만 데모 계정으로 오버라이드하고
나면, 이후 스코어링 활동들은 **역할 해석만으로 이미 실제 에이전트에게
배정**되어 있다 — 별도로 사람이 담당자를 지정할 필요가 없다.

단, "구매담당임원"·(첫 활동을 제외한) "구매팀" 역할은 여전히 `role_구매담당임원`
같은 placeholder 문자열이라 실제 사용자에게 배정되지 않는다 — 이 활동들은
시나리오 1과 동일하게 `task_id`+`email`로 직접 완료 처리해야 한다(아래 6번).

## 4. 핵심 데모 포인트 — 스코어링 활동이 무인으로, 그리고 실제로 스킬을 참조하며 처리됨

첫 활동 제출 직후 수 초~수십 초 안에 두 스코어링 활동이 자동으로
`SUBMITTED→DONE`이 되는 것을 폴링으로 확인한다:
```sql
select activity_id, status, agent_mode, agent_orch from todolist where proc_inst_id='<inst_id>' order by start_date;
```
- `재무 건전성 스코어링`, `제재·위규 이력 스코어링` 모두 `agent_mode=COMPLETE`,
  `agent_orch=deepagents`로 뜨고, 사람 클릭 없이 수 초 간격으로 `DONE`이
  된다 — `/todolist` 화면을 두 번 캡처해 카드가 저절로 움직이는 걸 보여주면
  좋다.

**스킬이 실제로 쓰였는지 확인하는 3가지 방법**:
1. 출력 내용이 스킬 문서의 구체적 절차를 따르는지 확인. 이번 세션 실측
   예시 — 스킬 문서(SKILL.md)에 "최근 3개년 재무제표"를 조회하라고 명시돼
   있는데, 실제로 3개년 재무제표 파일을 (문자열만) 제출했더니 재무
   스코어링 활동이 이렇게 응답했다:
   ```
   "scoring_basis": "필요 자료(재무제표_ACME물류_3개년.pdf)를 조회할 수
   없어 자동 평가를 진행할 수 없습니다. 자료가 업로드 및 임베딩되어
   있는지 확인이 필요합니다."
   ```
   숫자를 지어내지 않고 스킬이 요구하는 정확한 자료 종류를 거론하며
   거부한 것 — 일반 LLM 상식이 아니라 스킬 절차를 따른 정황이다.
2. `docker logs deepagents`에서 다음 두 줄이 있는지 확인:
   ```
   서브에이전트 '<에이전트명>' 스킬 설정: names=['<skill-slug>'] ... sandbox=['/skills/...']
   ```
   (뒤이어 `Cannot load skills`/`Skills load errors`가 **없어야** 정상 —
   있으면 0번 사전점검으로 돌아갈 것.)
3. 샌드박스 컨테이너 안에서 스킬 파일이 실제로 보이는지:
   ```bash
   docker exec deepagent-sandbox-<tenant> ls /skills/<tenant>/local/<skill-slug>/
   ```

## 5. 알려진 함정 — orchestration을 안 정한 활동은 영원히 멈출 수 있음

이번 proc_def의 4번째 활동("통합 리스크 등급 산정 및 요약 리포트 작성")은
`agentMode=none`으로 생성됐지만, 담당 역할이 이미 에이전트로 해석되기 때문에
런타임에 `agent_mode=COMPLETE`가 자동 부여되고 `agent_orch`는 기본값
`crewai-deep-research`로 폴백된다. **이 설치 환경엔 그 서비스 자체가 없어서
이 활동은 `IN_PROGRESS`에서 에러 없이 영원히 멈춘다** (troubleshooting #49).

```bash
docker ps --format '{{.Names}}' | grep -i "crewai\|deep-research"   # 없으면 이 문제
```

**데모 진행 지침**: 이 활동은 직접 API로 완료 처리해서 넘긴다(사람이 사후
검토한 것으로 간주):
```bash
curl -X POST "http://localhost:8088/completion/complete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input": {"task_id": "<todolist.id>", "email": "demo@localhost",
       "form_values": {"<proc_def_id>_<activity_id>_form": {"integrated_risk_grade": "보통(B)", "risk_summary_report": "..."}}}}'
```
이후 "최종 승인"(구매담당임원), "등록 또는 반려 통보"(구매팀) 두 활동도
동일하게 `task_id`+`email`로 직접 완료 처리한다(둘 다 placeholder 역할이라
어차피 사람 개입이 필요한 활동).

## 6. 검증된 전체 경로

이번 세션에서 처음부터 끝까지 완전히 검증됨:
```
협력사 정보 접수(DONE)
→ 재무 건전성 스코어링(DONE, deepagents+스킬, 무인)
→ 제재·위규 이력 스코어링(DONE, deepagents+스킬, 무인)
→ 통합 리스크 등급 산정(DONE, 직접 완료 처리 — crewai-deep-research 미설치)
→ 최종 승인(DONE, 직접 완료 처리)
→ 등록 또는 반려 통보(DONE, 직접 완료 처리)
→ bpm_proc_inst.status = COMPLETED
```

## 데모 후 보고

- 생성된 proc_def id, 스킬 slug, 에이전트 이름/uuid
- 시작된 proc_inst id
- 스코어링 두 활동의 SUBMITTED→DONE 타임스탬프(무인 처리 증거)
- 스킬 참조 증거(출력 내용 + deepagents 로그 캡처)
- 최종 `bpm_proc_inst.status`
- crewai-deep-research 미설치로 직접 완료 처리한 활동이 있었다면 그 사실
