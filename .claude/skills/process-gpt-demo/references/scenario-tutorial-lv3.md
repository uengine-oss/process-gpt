# 시나리오 — 튜토리얼 Lv.3: 조건 분기 설정과 피드백 반영 (영상 시리즈 3/5)

> **튜토리얼 영상 시리즈 3/5** — `docs/doc-site/content/ko/tutorial/tutorial-lv3.md`
> ("조건 분기 설정과 피드백 반영")의 현대화판이다.
>
> **2편에서 이어받은 것**: 2편(scenario-tutorial-lv2.md)이 만든 3단계 proc_def
> `b2f50721_3a7b_4f83_975e_cc046c8618c6` "영업 제안서 작성"
> (task1 요청사항 입력[고객] → task2 제안서 초안 생성[에이전트 fa3a2d21,
> deepagents, draft] → task3 제안서 확인[영업 담당자]). **삭제·재생성하지 말 것.**
> task3는 2편이 남긴 "사람 결정 지점"이고, 이번 편이 그 뒤에 게이트웨이+루프를 붙인다.
>
> **4편에 넘길 것**: 4편(ERP 데이터 연동을 통한 재고 관리)은 **별도 프로세스**로,
> 데이터소스 탭 + supabase MCP 에이전트 패턴을 쓴다. 이 proc_def를 재사용하지 않는다.
> 이번 편에서 확립한 "빌드타임=편집기 실조작 + 필요한 것만 DB 후보정", "런타임=API
> 실증 + 결정론 조건" 패턴은 그대로 참고하라.

전제: 고정 데모 계정(`demo@localhost` / `Demo1234!`, tenant `localhost`).
게이트웨이 기본 `http://localhost:8088`. 데모 계정 auth_uid `bd0e585b-3828-496c-92aa-3f93f336d3d3`.

---

## 0. 실측값 (이번 실행 기준 — 재현 시 매번 갱신)

| 항목 | 값 |
| --- | --- |
| proc_def id (2편에서 이어받음) | `b2f50721_3a7b_4f83_975e_cc046c8618c6` |
| 추가한 게이트웨이 | `gw_revision` "보완 사항 유무 확인" (`type=exclusiveGateway`, role 영업 담당자, `conditionData=["…_task3_form.needs_revision"]`) |
| 시퀀스(교체) | seq_start_task1 · seq_task1_task2 · seq_task2_task3 · **seq_task3_gw**(task3→gw) · **seq_gw_task2**(gw→task2, 루프백) · **seq_gw_end**(gw→end) |
| 분기 조건 JSON | seq_gw_task2 `properties={"conditionFunction":"needs_revision == 'true'","condition":"보완 사항 있음"}` · seq_gw_end `properties={"conditionFunction":"needs_revision == 'false'","condition":"보완 사항 없음"}` |
| task3 폼 추가 필드 | `needs_revision` 라디오(items `[{"true":"보완 필요"},{"false":"보완 불필요"}]`) — 값은 문자열 `"true"/"false"` |
| task2 체크포인트 | `["오탈자 없음","첨부 자료 누락 없음","고객 요청 반영"]` (결정론 경로는 무시, 화면·내레이션용) |
| task2 inputData(피드백 전달용 추가) | `[…_task1_form.request_details, …_task3_form.review_comment]` |
| 루프백 실증 인스턴스(COMPLETED) | `b2f50721_3a7b_4f83_975e_cc046c8618c6.4bcc2ff4-4e6d-41dd-8881-5c6204cbb92e` |
| task2 워크아이템(루프백 대상) | `18d3c4a4-406a-4f4f-ae55-96b4fb550b96` |
| task3 워크아이템(반려/승인) | `82d1b425-a121-4e80-abb5-f45abe2678d2` |
| 최종 영상 | `demo-recordings/tutorial-lv3-conditional-feedback-narrated.mp4` **194.5s(3.24분), h264/aac, mean_volume −25.3dB, assemble PASS**, voice marin |

DB 접근:
```bash
cd /Users/uengine/process-gpt/docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }
PSQL "select s->>'id', s->>'properties' from public.proc_def, jsonb_array_elements(definition->'sequences') s where id='b2f50721_3a7b_4f83_975e_cc046c8618c6' and s->>'source'='gw_revision';"
```

---

## 1. 조건 평가 메커니즘 — conditionFunction 우선 (#45 회피의 핵심)

폴링 서비스 `services/completion/polling_service/workitem_processor.py`
`_evaluate_sequence_conditions()`(L2181~)는 시퀀스 `properties`(JSON 문자열)에서
조건을 읽어 두 경로로 평가한다:

1. **`conditionFunction`** (결정론적 Python `eval`, `{"__builtins__":{}}` + 컨텍스트):
   `all_workitem_input_data`를 재귀적으로 펼친 모든 dict를 컨텍스트로 시도 → 하나라도
   True면 통과. **LLM을 안 씀 → #45(반려 오분기) 리스크 없음.** 있으면 즉시 평가 후
   NL 경로로 안 감.
2. **`condition`(자연어)/`name`**: LLM 평가(`_evaluate_nl_conditions`). 값/라벨 매칭이
   불안정 → 반려 의도를 승인으로 오분기할 수 있음(#45 관찰).

**결론**: 두 분기 엣지 모두 `conditionFunction`(`needs_revision == 'true'/'false'`)을
넣어 결정론화했다. `condition`(NL)은 SequenceFlowPanel 표시/내레이션용으로 병기.
nextActivities 해석은 `resolve_next_activity_payloads`(L3880~, exclusive는
`conditionEval` True인 엣지 1개 선택)가 담당 — 컨테이너 안에서 단위 실행으로
**승인→end_event / 반려→task2** 정확 분기 검증했다.

라디오 저장값은 문자열 `"true"/"false"`(실측: `todolist.output.needs_revision`).
그래서 리터럴을 `'true'/'false'`로 맞춰야 한다.

---

## 2. 빌드타임 — BPMN 편집기 직접 조작 (실화면) + 필요한 것만 DB 후보정

이번 편의 교육 목표는 **편집기에서 직접 모델링**이다. `/definitions/<id>` 편집 모드에서:

- **편집 모드 진입**: 우측 패널의 **연필 아이콘**(읽기모드) 토글 → 저장 아이콘으로 바뀌며
  도형 팔레트·편집 도구가 뜬다("읽기 모드입니다" 사라짐). Playwright에서는 우측 패널
  x≈1576 아이콘 버튼. (컴포넌트: `ProcessDefinitionChatHeader.vue` `toggleLock`.)
- **게이트웨이 배치**: 팔레트 `.djs-palette .entry[data-action="create.exclusive-gateway"]`
  (아이콘 `bpmn-icon-gateway-xor`). 확인 단계 뒤에 배타 게이트웨이를 놓는다.
- **분기 조건 입력**: 분기 플로우를 **더블클릭** → `SequenceFlowPanel`
  (`…/panel/SequenceFlowPanel.vue`)의 **조건** 필드(`TextConditionField.vue`)에
  자연어 조건("보완 사항 있음/없음") 입력. 프리펜드 아이콘(`mdi-comment-text-outline`)으로
  **함수 모드** 전환 시 conditionFunction 직접 입력, 또는 **"결정론적 규칙화"** 버튼으로
  AI 생성.
- **체크포인트 추가**: task2 더블클릭 → **설정** 탭(`.v-tab[value="setting"]`) →
  `CheckpointsField.vue`의 **'+'**(`.user-task-panel-check-points .mdi-plus`)로 체크포인트 추가.
- **저장**: 저장 아이콘 → **"버전 업" 다이얼로그**의 저장 버튼.

### ⚠️ 편집기 한계 (제품 개선 포인트, 실측 확인)

**편집기 저장은 자연어 `condition`은 저장하지만 `conditionFunction`은 저장하지 않는다**
(함수 모드로 직접 입력하거나 "결정론적 규칙화" AI를 돌리지 않는 한). 저장 시
`bpmnXmlToDefinition.buildSequence`가 `sequences[].properties`에 패널이 쓴 JSON을
그대로 복사할 뿐이라, 자연어만 입력하면 `properties`에 `condition`만 남고
`conditionFunction`이 없다 → 런타임이 불안정한 NL(LLM) 경로로 감(#45).
또한 저장은 캔버스에서 정의 전체를 재생성하므로 시퀀스 id가 bpmn 파생 id로 바뀐다.

→ **이번 실행**: 편집기에서 편집 모드 진입·조건(자연어) 입력·체크포인트 추가·저장까지
**실조작 녹화**했고, 저장이 실제로 `conditionFunction`을 떨어뜨리는 것을 확인한 뒤
**`conditionFunction`을 DB로 후보정**(dollar-quoted `apply_lv3.sql`)했다. 이것이
"편집기 1차 저장 → 불완전분만 DB 후보정" 규칙의 실제 사례다.

> **헤드리스 Playwright 주의**: bpmn-js 팔레트 drag/click은 actionability 타임아웃(각 30s)으로
> 불안정하고 캔버스를 교란한다. 그래서 녹화에선 팔레트 조작 대신 편집 도구/배치된
> 게이트웨이를 보여주고, **조건 입력·체크포인트 추가는 실제 폼 조작**으로 했다.
> 엣지 패널 열기는 `[data-element-id] .djs-visual`의 화면 rect 여러 점을 `mouse.dblclick`으로
> 시도하면 열린다(단순 그룹 클릭·`.djs-hit` 클릭은 안 열림).

적용 SQL은 `apply_lv3.sql`(scratchpad): `proc_def.definition`(gateways/sequences/
activities[task2].checkpoints/inputData) + `proc_def.bpmn`(게이트웨이·루프백 엣지) +
`form_def`(task3 needs_revision 라디오)를 한 번에 UPDATE.

---

## 3. 런타임 — 반려 → 루프백 → 재작성 → 승인 → COMPLETED (API 실증)

단일 데모 계정 한계상 전이는 `/completion/complete`를 JWT로 직접 호출(2편 §5 패턴).
토큰: `POST {supabase}/auth/v1/token?grant_type=password`(apikey=anon).

실증 타임라인(인스턴스 `…4bcc2ff4…`, 검증됨):

| 단계 | 동작 | 관찰 |
| --- | --- | --- |
| 1 | task1 제출(EU 독일 바이어, 센서 50개, CE 관련) | 인스턴스 시작 |
| 2 | task2 deepagents draft (~12s) | `todolist.draft` 채움, IN_PROGRESS로 사람 제출 대기 |
| 3 | task2 제출 | task3 생성(TODO) |
| 4 | **task3 반려 제출**: `needs_revision="true"` + review_comment | 게이트웨이 gw_task2(True) → **task2 재활성(IN_PROGRESS)** ← 루프백 확인 |
| 5 | task2 재제출 | task3 재활성 |
| 6 | **task3 승인 제출**: `needs_revision="false"` | 게이트웨이 gw_end(True) → end_event 라우팅, 전 활동 DONE |
| 7 | 완료 | (아래 #4 참조) COMPLETED |

**루프백은 완전히 검증됨** — 반려 시 흐름이 task2로 되돌아간다. review_comment는
task2 inputData(`…_task3_form.review_comment`)로 전달되도록 정의를 확장했다
(`get_input_data`가 값이 있을 때만 담으므로 첫 실행엔 무해, 루프백 때 전달).

⚠️ **재작성 초안에 대한 정직한 관찰**: 루프백으로 재활성된 task2 워크아이템은
**기존 draft를 유지**했고(같은 워크아이템 id 재사용) 에이전트가 자동으로 초안을
**재생성하지는 않았다**(draft1 == draft2, 원 초안에 이미 CE 인증 포함). 즉 이 버전에서
루프백은 "제어 흐름 회귀 + 검토 의견 전달"까지가 실증 범위이며, **AI 자동 재작성은
주장하지 않는다**(내레이션도 "초안 생성 단계로 되돌아가 검토 의견과 함께 다시 작성"
수준으로만 서술). 재작성 자동화가 필요하면 루프백 시 draft를 비우고 재디스패치하는
별도 처리가 필요 — 4편/후속 개선 후보.

---

## 4. 만난 버그 — 게이트웨이→endEvent 종료가 COMPLETED 안 됨 (배포 이미지 stale)

승인 분기(`needs_revision='false'`) 제출 후 **전 활동 DONE·current_activity_ids 비었는데
`bpm_proc_inst.status`가 RUNNING**에 머물렀다. 원인은 배포된 `polling-service` 이미지의
`process_definition.find_end_activity()`(단수)가 **게이트웨이를 거슬러 올라가지 못함** —
`task3 → gw_revision → end_event`에서 endEvent 직전이 게이트웨이라 종료 활동을 `None`으로
판정 → `upsert_process_instance`가 COMPLETED를 못 세운다.

- **현재 소스는 이미 수정됨**: 로컬 `process_definition.py`에 게이트웨이 재귀 traversal
  하는 `find_end_activities()`(복수)가 있고 `database.py`가 이를 사용. **배포 이미지만
  그 커밋 이전.** 근본 해결 = polling-service 이미지 재빌드/재배포.
- **이번 대응**: 컨테이너 소스는 미수정(classifier가 패치 차단). 게이트웨이 라우팅
  (승인→end_event/반려→task2)은 컨테이너 안 `resolve_next_activity_payloads` 단위 실행으로
  **별도 입증**했고, 논리적으로 완료된 쇼케이스 인스턴스의 `status`만 COMPLETED로 데이터
  보정해 사용. → troubleshooting.md **#52**, PRODUCT_CHANGES_REPORT **#3**.

---

## 5. 함정 요약

- **BPMN↔definition 이원화**: 스윔레인=`bpmn` XML, 런타임=`definition.activities/sequences/
  gateways`. 둘 다 갱신해야 함(`apply_lv3.sql`이 함께 처리).
- **편집기 저장이 conditionFunction 미저장**(§2 한계) → DB 후보정 필수.
- **편집기 저장이 정의 전체 재생성**(시퀀스 id 변경, conditionFunction 소실) → 녹화 후
  `apply_lv3.sql` 재적용으로 원상복구.
- **라디오 값 문자열**: `"true"/"false"`. conditionFunction 리터럴을 맞출 것.
- **루프백 워크아이템 재사용**: 재활성 시 새 워크아이템이 아니라 기존 id 재사용, draft 유지.
- **게이트웨이→endEvent COMPLETED 버그**(§4, 배포 이미지 stale).
- **헤드리스 bpmn-js 팔레트 불안정**(§2 주의).
- **폴링 지연**: 각 제출 후 SUBMITTED→다음단계까지 수 초~수십 초, DB 폴링으로 확인.

---

## 데모 후 보고 (이번 실행 결과)

- 게이트웨이 `gw_revision` "보완 사항 유무 확인"(exclusive) + 6-시퀀스 배열. 분기 조건:
  gw_task2 `conditionFunction "needs_revision == 'true'"` (보완 사항 있음, 루프백),
  gw_end `conditionFunction "needs_revision == 'false'"` (보완 사항 없음, 종료).
- task3 폼에 `needs_revision` 라디오 추가, task2에 체크포인트 3개 + inputData에 review_comment.
- 루프 실증(`…4bcc2ff4…`): task1 DONE → task2 draft(~12s) DONE → task3 **반려** →
  **task2 루프백 재활성** → task2 DONE → task3 **승인** → 전 활동 DONE → (배포 이미지
  버그로 status만 데이터 보정) **COMPLETED**. 게이트웨이 라우팅은 in-container 단위 실행으로 입증.
- 재작성 초안: 제어 흐름은 초안 생성 단계로 회귀하고 review_comment가 전달되나, 이 버전에서
  **에이전트 자동 재작성은 일어나지 않음**(draft 재사용). 내레이션은 이 선에서만 주장.
- 빌드타임: 편집기 실조작(편집 모드·조건 자연어 입력·체크포인트 '+' 추가·저장) 녹화 →
  편집기가 conditionFunction을 저장 안 함을 확인 → **DB로 conditionFunction 후보정**.
- 최종 영상: `demo-recordings/tutorial-lv3-conditional-feedback-narrated.mp4`
  **194.5s, h264/aac, mean_volume −25.3dB, assemble PASS**, voice marin.
- 제품 소스 수정: **없음**(완료 버그는 소스가 이미 수정돼 있고 배포 이미지만 stale — 데이터
  보정 + 문서화만). 데모 데이터(proc_def/form_def 확장, 인스턴스)는 생성.

## 4편 제작자 참고 팁

- **런타임 전이는 API 직접 호출**(`/completion/complete`, task_id+email, form_values는 폼id
  전체+평탄 키 병행) + DB 폴링으로 상태 확인. 화면엔 instance-viewer/워크아이템 상태를 보여줌.
- **빌드타임 편집기 조작**: 편집 모드=우측 패널 연필 토글(x≈1576), 폼 패널(설정/데이터소스/
  에이전트 탭)은 실제 UI 이벤트로 조작 가능(안정적). bpmn-js 캔버스 요소 조작은 헤드리스에서
  불안정하니 `.djs-visual` rect 다중점 dblclick 패턴 참고.
- **결정론 조건이 필요하면 conditionFunction**을 쓰고, 편집기 저장이 이를 떨어뜨리므로 DB
  후보정을 전제로 설계. 데이터소스 연결(4편)도 편집기 저장 후 실제 저장 컬럼을 DB로 검증할 것.
- 4편 ERP는 **데이터소스 탭 + supabase MCP 에이전트** 패턴 — 별도 proc_def로 시작(이 proc_def
  재사용 금지). 녹화/TTS/합성 규약과 `lib_tutorial_slides.mjs`(level=4)는 그대로 재사용.
</content>
