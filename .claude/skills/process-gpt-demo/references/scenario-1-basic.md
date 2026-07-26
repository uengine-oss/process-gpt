# 시나리오 1 — 프로세스 데모(간단): 휴가 신청 프로세스

기본(default/basic) 에이전트로 텍스트 대화만으로 분기(승인/반려)가 있는
프로세스를 생성하고, **실제로 인스턴스를 끝까지 실행**해서 신청서 작성 →
승인 → 등록/통보까지 진행되는 걸 보여준다. 생성만으로 끝내는 게 아니라
실제 폼을 통해 한 단계씩 제출해가며 완료 상태(`COMPLETED`)까지 확인하는
것이 이 시나리오의 핵심 — 이 레포에서 이번에 처음 검증된 부분이다.

전제: [demo-account.md](demo-account.md)의 고정 계정으로 로그인돼 있어야
한다.

## 1. 분기가 있는 프로세스 생성

⚠️ **주의**: 그냥 "휴가 신청 프로세스를 만들어줘"라고만 하면 대부분
**분기 없는 선형 흐름**(신청 → 승인 → 통보)으로 생성된다 — 이번 세션에서
직접 확인함. 분기(게이트웨이)를 확실히 만들려면 승인/반려 갈림을 명시적으로
요청해야 한다.

1. `/definition-map`에서 아래 프롬프트로 전송(`.cp-send` 버튼):
   ```
   휴가 신청 프로세스를 만들어줘. 사원이 휴가 신청서를 작성하면 상사가
   검토해서 승인 또는 반려를 결정하는 분기가 반드시 있어야 하고, 승인되면
   인사팀이 등록하고, 반려되면 신청자에게 반려 사유를 통보해야 해.
   ```
2. 초안(활동 4~5개 + 승인/반려 분기 흐름도)이 뜨면 확인.
3. **확정**: "이대로 프로세스 생성" 같은 확인 칩(chip)이 뜬다 — 이건 칩을
   눌러도 **선택만 될 뿐 제출되지 않는다**. 칩 선택 후 별도로 뜨는
   "응답 제출" 버튼을 반드시 눌러야 실제로 생성이 진행된다. **두 클릭 모두
   같은 브라우저 세션(같은 페이지, 새로고침 없이) 안에서 해야 한다** —
   세션이 끊기면(스크립트를 나눠 실행하는 등) 칩 선택 상태가 사라져
   "element is not enabled" 에러가 난다.
4. BPMN 다이어그램 + 폼 생성 완료 메시지 확인 → 💾 저장 → 저장 다이얼로그
   확인.
5. 영속화 확인:
   ```sql
   select id, name, tenant_id from public.proc_def order by created_at desc limit 3;
   ```
   이번 검증에서 생성된 proc_def id: `9330f1d1_8214_4155_a0e8_af0de277d9c9`
   (재현 시 매번 새 id가 생성되니 참고용).

### 생성된 폼 필드 스키마 (참고)

`form_def` 테이블에서 조회 가능:
```sql
select fields_json::text from form_def where id='<proc_def_id>_<activity_id>_form';
select html from form_def where id='<proc_def_id>_<activity_id>_form';  -- 라디오 items 등 실제 값 확인
```

- `task_apply_form`: `applicant_name`, `vacation_type`, `start_date`,
  `end_date`, `vacation_reason`, `attachment`(파일)
- `task_review_form`: `approval_status`(라디오, 값 `"approved"`/`"rejected"`,
  표시 라벨 승인/반려), `review_comment`(textarea)
- `task_register_form`: `vacation_application_file`(파일),
  `approval_status`(라디오)
- `task_notify_approve_form`: `free_input`(textarea)

활동 이름/필드명은 매번 재생성 시 달라질 수 있으니, 데모 직전에 위 쿼리로
실제 스키마를 다시 확인할 것.

## 2. 인스턴스 실행 시작

메인 채팅에서 "휴가 신청 프로세스 실행해줘"라고 요청하면:
- 동일 이름 프로세스가 여러 개면 에이전트가 어떤 것인지 되묻는다.
- 이후 대화형으로 신청서 필드(신청자명/휴가종류/시작일/종료일/사유 등)를
  하나씩 수집한다.
- 내부적으로 MCP 툴 체인 `get_process_list → get_process_detail →
  get_form_fields → execute_process`가 호출되고, `execute_process`가
  `POST {gateway}/completion/complete`로 인스턴스를 시작시킨다.

⚠️ 이 실행 경로가 자체 호스팅 설치에서 동작하려면
troubleshooting.md **#44**(work-assistant MCP의 하드코딩 SaaS 도메인) 수정이
이미지에 반영돼 있어야 한다 — `PROCESS_GPT_API_BASE_URL` env가 게이트웨이
주소(`http://nginx:8088`)로 설정돼 있는지 먼저 확인.

## 3. 담당자 배정의 한계 — 단일 데모 계정에서 직접 API 제출이 필요한 이유

`execute_process`는 `role_mappings`를 만들 때 **첫 번째 활동(신청서 작성)의
역할만** 실제 로그인 사용자(`demo@localhost`)에 바인딩한다. 이후 활동들
(상사 검토="role_manager", 인사팀 등록="role_hr" 등)은 proc_def의 `roles`
배열에 있는 원본 문자열 그대로 남아 **실제로 조회 가능한 사용자에게
배정되지 않는다** — 즉 데모 계정 하나만 갖고 있으면 이 워크아이템들은
`/todolist` 화면에 뜨지 않는다.

**해결**: `/todolist` UI 대신 `/completion/complete` API를 JWT와 함께 직접
호출해서 제출한다. Playwright로 로그인한 세션에서 토큰을 뽑아 쓰는 패턴:

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

### API 호출 형식

- **첫 워크아이템(신청서) 제출** — `task_id`가 아직 없다면 `execute_process`가
  이미 만들어준 것을 쓰거나, 직접 인스턴스를 시작할 때:
  ```
  POST {gateway}/completion/complete
  Authorization: Bearer <token>
  {
    "input": {
      "process_definition_id": "<proc_def_id>",
      "process_instance_id": "<proc_def_id>.<uuid>",
      "activity_id": "task_apply",
      "email": "demo@localhost",
      "user_id": "<auth_uid>",
      "username": "demo",
      "form_values": { "task_apply_form": { "applicant_name": "...", ... } }
    }
  }
  ```
- **이후 워크아이템 제출** (`task_id`만 있으면 activity_id/proc_def_id/
  proc_inst_id는 DB에서 자동 조회됨):
  ```
  POST {gateway}/completion/complete
  Authorization: Bearer <token>
  {
    "input": {
      "task_id": "<todolist.id>",
      "email": "demo@localhost",
      "form_values": { "task_review_form": { "approval_status": "approved", "review_comment": "..." } }
    }
  }
  ```
  ⚠️ `email`을 빼면 500 `'NoneType' object has no attribute 'get'`로
  실패한다(troubleshooting #45, 수정 완료 — 그래도 요청엔 항상 포함할 것).

제출 직후 상태는 바로 `DONE`이 아니라 `SUBMITTED`다 — 실제 다음 단계
진행(게이트웨이 분기 포함)은 `polling-service` 컨테이너가 비동기로
집어가서 처리한다. 아래로 폴링해서 확인:
```sql
select activity_id, status from todolist where proc_inst_id='<proc_inst_id>' order by start_date;
```

## 4. 검증된 경로: 승인(approve)

이번 세션에서 처음부터 끝까지 완전히 검증됨:
```
task_apply(DONE) → task_review(approved, DONE) → task_register(DONE)
→ task_notify_approve(DONE) → bpm_proc_inst.status = COMPLETED
```
데모에서 재현 순서:
1. `task_apply` 제출(신청서 폼 값 채워서).
2. `task_review` 제출: `approval_status: "approved"`.
3. `task_register`, `task_notify_approve`가 자동/후속으로 `DONE` 처리되는지
   폴링 확인.
4. 최종 확인:
   ```sql
   select proc_inst_id, status from bpm_proc_inst where proc_inst_id='<proc_inst_id>';
   ```
   `status = 'COMPLETED'`가 나오면 성공.

## 5. 알려진 한계: 반려(reject) 경로는 구조적으로만 존재 (미확정)

`approval_status: "rejected"`로 제출해도 실제로는 반려 분기가 아니라
`task_register`(승인 쪽 활동)가 활성화되는 것이 이번 세션에서 두 번
관찰됐다(자연어 채팅 실행 1회 + API 직접 호출 1회, 두 경우 모두 반려 의도가
명확했음에도 동일). 원인은 게이트웨이 분기 선택 로직 내부까지 추적했으나
정확한 코드 경로는 특정하지 못했다 — 자세한 내용은
troubleshooting.md **#45**("버그 2") 참고.

**데모 진행 지침**: 반려 분기가 실제 존재하고 `task_notify_reject` 같은
워크아이템이 proc_def에 미리 정의돼 있다는 점(구조적으로는 있다)까지는
보여줘도 되지만, "반려하면 반려 분기로 간다"를 라이브로 단정 시연하지
말 것. 승인 경로를 메인으로 시연하고, 반려를 보여주고 싶다면 사전에
```sql
select activity_id, status from todolist where proc_inst_id='<inst_id>' order by start_date;
```
로 실제 어느 활동이 활성화됐는지 확인한 뒤 결과에 맞게 설명한다.

## 데모 후 보고

- 생성된 proc_def id/name
- 시작된 proc_inst id
- 각 활동의 상태 전이(activity_id → status) 타임라인
- 최종 `bpm_proc_inst.status`
- 반려 경로를 함께 시도했다면 실제 어느 분기가 선택됐는지 DB 근거와 함께
