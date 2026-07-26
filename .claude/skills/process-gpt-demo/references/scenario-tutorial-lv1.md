# 시나리오 — 튜토리얼 Lv.1: 프로세스 생성과 실행 (영상 시리즈 1/5)

> **튜토리얼 영상 시리즈 1/5** — `docs/doc-site/content/ko/tutorial/tutorial-lv1.md`
> ("프로세스 생성과 실행")의 **현대화판**이다. 원본 튜토리얼은 수동 BPMN
> 팔레트 중심의 구버전 화면을 기준으로 쓰였으나, 현재 제품은 **우측 AI
> 채팅으로 자연어 요청 → 프로세스 자동 생성**이 주된 흐름이다. 이 시나리오는
> 그 현대화된 흐름으로 **영업 제안서 작성 프로세스**(고객 요청 입력 → 영업
> 담당자 제안서 작성, 2단계)를 만들고 끝까지 실행한다.
>
> 지금 제품의 기본 오케스트레이션은 **deepagents**다(정의 화면 상단 드롭다운
> "기본 에이전트"). crewai-action은 이 시리즈에서 다루지 않는다.
>
> 후속편 재사용: 여기서 만든 제안서 프로세스 정의를 **2편(에이전트 추가)**과
> **3편(게이트웨이 추가)**이 확장·재사용한다 — **이 proc_def를 삭제하지 말 것.**

전제: [demo-account.md](demo-account.md)의 고정 계정(`demo@localhost` /
`Demo1234!`, tenant `localhost`)으로 로그인. 게이트웨이 기본은
`http://localhost:8088`.

---

## 0. 실측값 (이번 실행 기준 — 재현 시 매번 갱신)

| 항목 | 값 |
| --- | --- |
| proc_def id | `b2f50721_3a7b_4f83_975e_cc046c8618c6` |
| proc_def name | 영업 제안서 작성 (`is_draft=false`, 채팅 생성 후 자동 저장됨) |
| 생성 채팅 room id | `0867ccac-f1ac-4b9f-a912-d2d2c3d9b102` |
| 활동 1 (id / name / role) | `task1` / 요청사항 입력 / 고객(`role_customer`) |
| 활동 2 (id / name / role) | `task2` / 제안서 작성 및 전달 / 영업 담당자(`role_sales_representative`) |
| 흐름 | `start_event → task1 → task2 → end_event` (선형, 게이트웨이 없음) |
| task1 폼 (`..._task1_form`) | `request_details`(요청사항, textarea) |
| task2 폼 (`..._task2_form`) | `customer_requests`(고객 요청사항, textarea), `proposal_document`(제안서 파일, file) |
| proc_inst id | `b2f50721_3a7b_4f83_975e_cc046c8618c6.bbb887fd-bfc2-4d7b-a60c-16131833cb98` |
| 워크아이템 task1 / task2 | `d7ac8ebc-f15b-44cf-a95b-46a37d736ac6` / `1b91eb4f-f317-4e61-88e8-55f9dea925c7` |
| 데모 계정 auth_uid | `bd0e585b-3828-496c-92aa-3f93f336d3d3` |

> **참고**: definition-map 채팅 생성물은 "이대로 프로세스 생성" 칩 + 응답 제출
> 직후 **자동으로 proc_def에 저장**된다(별도 💾 저장 클릭 불필요, `is_draft=false`).
> 대화방 우측 패널에 "저장됨" 배지와 함께 proc_def id가 표시된다.

DB 검증 쿼리 (`docker-infra`의 `.env` 사용):

```bash
cd /Users/uengine/process-gpt/docker-infra
PGPW=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
PSQL(){ docker exec -e PGPASSWORD="$PGPW" supabase-db psql -U supabase_admin -d postgres -tAc "$1"; }
PSQL "select id, name, is_draft from public.proc_def where tenant_id='localhost' and name ilike '%제안서%' order by id;"
```

---

## 1. 빌드타임 — AI 채팅으로 프로세스 생성

1. `/definition-map`로 이동. 상단에 통합 채팅 박스(에이전트 드롭다운 "기본
   에이전트" = deepagents), 하단에 "프로세스 정의 체계도" 트리가 있다. 원본
   튜토리얼의 **수동 BPMN 팔레트**는 프로세스 편집기(정의를 열었을 때의
   디자이너 캔버스)에 있으며, 현재 흐름에서는 잠깐만 언급하고 넘어간다.

2. 채팅 입력(visible textarea)에 아래 프롬프트를 실제로 타이핑해서 전송:
   ```
   영업 제안서 작성 프로세스를 만들어줘. 고객이 요청사항을 입력하면 영업
   담당자가 제안서를 작성해서 전달하는 2단계 프로세스야. 각 단계에 맞는 입력
   폼도 만들어줘.
   ```
   전송 즉시 URL이 `/chat?roomId=<uuid>`로 바뀐다(새 대화방 생성).

3. deepagents가 초안(활동 2개 + 흐름 + 폼)을 생성하고 **확인 패널**을 띄운다.
   확인 패널은 `HumanFeedbackPanel` 컴포넌트로, `approve_reject_with_edit`
   타입이면 **"승인"/"반려" 버튼**이, `suggestions` 타입이면 `.v-chip`
   확인 칩이 나온다.

4. ⚠️ **함정(검증됨)**: 확인 버튼/칩을 눌러도 **선택만 될 뿐 제출되지
   않는다.** 그 아래 별도로 뜨는 **"응답 제출"** 버튼
   (`.human-feedback-panel__actions button:has-text("응답 제출")`)을 반드시
   눌러야 실제 생성이 진행된다. **두 클릭은 같은 브라우저 세션(새로고침
   없이) 안에서** 해야 한다 — 세션이 끊기면 선택 상태가 사라져 submit이
   disabled로 남는다.

5. "응답 제출" 직후 "✅ BPMN 프로세스 생성 완료" 메시지가 뜨고 **자동으로
   저장**된다 — 이번 실행에서 `proc_def`에 `is_draft=false`로 즉시 영속화됐고
   대화방 우측 패널에 "저장됨" 배지 + proc_def id가 표시됐다. (별도 💾 저장
   버튼 클릭이 필요한 경우도 있으니 §0 쿼리로 실제 저장 여부·`is_draft`를
   확인할 것.) BPMN 다이어그램은 `/definitions/<proc_def_id>`에서 스윔레인
   형태(고객/영업 담당자 레인)로 열람 가능.

### 셀렉터 팁 (이번 실행에서 검증)

- 로그인: `/auth/login` 직행, `input[type="text"]` / `input[type="password"]`,
  `button:has-text("로그인")` (demo-account.md와 동일).
- 채팅 입력: `textarea:not([aria-hidden="true"])`의 **first** — v-textarea는
  숨겨진 `__sizer` textarea를 함께 렌더하므로 `.last()`를 쓰면 hidden sizer가
  잡혀 "element is not visible"로 실패한다.
- 전송 버튼: `.cp-send:visible`의 first (종이비행기 아이콘).
- 확인 패널: `.human-feedback-panel:not(.is-submitted)` 존재 여부로 대기.
  승인: `.human-feedback-panel button:has-text("승인")`; 칩:
  `.human-feedback-panel__chip`; 제출:
  `.human-feedback-panel__actions button:has-text("응답 제출")`.

---

## 2. 런타임 — 인스턴스 실행 → 완료

단일 데모 계정만 있으므로, 두 번째 활동(영업 담당자 제안서 작성)이 실제
로그인 사용자에게 자동 배정되지 않아 `/todolist`에 안 뜰 수 있다
(scenario-1-basic.md §3과 동일한 구조적 한계). 그래서 실행/전이는
`/completion/complete` API를 JWT로 직접 호출해 제출하되, **화면에는
워크아이템 상세·인스턴스 목록 화면을 띄워 상태 전이가 보이게** 한다.

토큰 추출(로그인한 Playwright 세션에서):
```javascript
const token = await page.evaluate(() => {
  for (const k of Object.keys(localStorage)) {
    if (k.includes('auth-token')) {
      const v = JSON.parse(localStorage.getItem(k));
      return v.access_token ?? v.currentSession?.access_token;
    }
  }
});
```

첫 활동(요청사항 입력) 제출 → 인스턴스 시작:
```
POST {gateway}/completion/complete
Authorization: Bearer <token>
{ "input": {
    "process_definition_id": "<proc_def_id>",
    "process_instance_id": "<proc_def_id>.<uuid>",
    "activity_id": "task1",
    "email": "demo@localhost",
    "user_id": "bd0e585b-3828-496c-92aa-3f93f336d3d3",
    "username": "demo",
    "form_values": { "<proc_def_id>_task1_form": { "request_details": "..." } }
} }
```
⚠️ `form_values`의 키는 **폼 id 전체**(`<proc_def_id>_task1_form`)다. 안전하게
평탄한 키(`request_details`)도 함께 넣어 주면 게이트웨이 조건 평가 양쪽을 모두
만족한다(`process_validator._form_values_for` 참고). 이후 활동은 `task_id`만으로
제출(activity_id/proc_def/proc_inst는 DB 자동
조회). ⚠️ `email`을 빼면 500(`'NoneType'...get`) — 항상 포함(troubleshooting #45).

제출 직후 상태는 `SUBMITTED` → `polling-service`가 비동기로 다음 단계를
집어가 처리한다. 폴링 확인:
```sql
select activity_id, status from todolist where proc_inst_id='<INST_ID>' order by start_date;
select proc_inst_id, status from bpm_proc_inst where proc_inst_id='<INST_ID>';
```
최종 `bpm_proc_inst.status = 'COMPLETED'`면 성공.

인스턴스/칸반: 좌측 사이드바 "인스턴스" 목록 또는 워크아이템 상세
(`/todolist/<workitem_id>`), 그리고 프로세스 칸반보드 탭에서 상태를 육안
확인한다.

---

## 3. 만난 함정 / 버그

- **#25 (기지, 이번에 재발)**: 채팅 생성 시 `/agent/chat/stream` **502**,
  nginx 로그 `base-agent-langchain-react could not be resolved`. 원인은
  `nginx/nginx.conf`의 `$upstream_agent`가 옛 접두사
  `process-gpt-base-agent-langchain-react`로 하드코딩된 것. `base-agent-
  langchain-react:8000`으로 고치고 nginx 컨테이너 재시작하면 해결.
  troubleshooting.md #25 참고. **이번 실행에서 이 오타가 다시 있어 재적용함.**

---

## 데모 후 보고 (이번 실행 결과)

- proc_def: `b2f50721_3a7b_4f83_975e_cc046c8618c6` / 영업 제안서 작성 /
  `is_draft=false` / room `0867ccac-f1ac-4b9f-a912-d2d2c3d9b102`
- 활동/폼: task1 요청사항 입력(`request_details`) · task2 제안서 작성 및
  전달(`customer_requests`, `proposal_document`)
- proc_inst `...bbb887fd...`, 상태 전이 타임라인(모두 검증됨):
  `task1: SUBMITTED → DONE` → (polling-service) → `task2: IN_PROGRESS →
  SUBMITTED → DONE` → `bpm_proc_inst.status = COMPLETED`
- 최종 영상: `demo-recordings/tutorial-lv1-process-basics-narrated.mp4`
- 2편(에이전트 추가)이 이어받을 상태: 위 proc_def가 **선형 2단계 userTask**로
  저장돼 있음. task2(제안서 작성 및 전달, role 영업 담당자)에 에이전트를
  바인딩(agent/agentMode)하면 자동 작성 시나리오로 확장 가능. proc_def를
  **삭제하지 말 것**.
