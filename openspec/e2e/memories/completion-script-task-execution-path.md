---
name: completion-script-task-execution-path
description: completion polling 의 scriptTask 는 자체 workitem 처리 경로가 아니라 handle_workitem 의 LangChain 완료/다음활동 판정 뒤에서 _execute_script_tasks 가 next activity 로 실행됨. E2E 로 검증하려면 userTask 선행 + completion LLM mock + role_bindings 가 필요. 실제 적용 패턴은 completion_automated-task-execution e2e 참고.
applies-to:
  - completion-polling
  - script-task
  - langchain
  - workitem_processor
last-verified: 2026-05-27
metadata:
  type: workaround
---

# scriptTask execution is downstream of LangChain completion pipeline — E2E pattern

`services/completion/polling_service/polling_service.py:69` dispatch:

```python
if task_type in ('userTask', 'scriptTask', 'manualTask'):
    await handle_workitem(workitem)
elif task_type == 'serviceTask':
    await handle_service_workitem(workitem)
```

`handle_workitem` 는 4000+ 라인의 LangChain heavy 핸들러로 userTask/scriptTask/manualTask 를
공통 처리. 실제 파이썬 코드 실행(`_execute_script_tasks` → `code_executor.execute_python_code`)
은 `handle_workitem` 의 `execute_next_activity(completed_json, tenant_id)` 호출 안에서만 실행됨.
그리고 `_execute_script_tasks` 는 **현재 워크아이템의 활동이 아닌 `process_result.nextActivities`
중 type='scriptTask' 인 항목** 만 실행함:

```python
def _execute_script_tasks(process_instance, process_result, ...):
    for activity in process_result.nextActivities:
        activity_obj = process_definition.find_activity_by_id(activity.nextActivityId)
        if activity_obj and activity_obj.type == "scriptTask":
            result = execute_python_code(activity_obj.pythonCode, env_vars=env_vars)
            ...
```

즉, `scriptTask` 워크아이템이 직접 SUBMITTED 상태로 들어와도 거기서 pythonCode 가 실행되지
않음. 항상 선행 활동(보통 userTask) 이 완료될 때 `completed_json.nextActivities` 에 포함되어
다음 활동으로 즉시 실행되는 구조.

## What works (실증 패턴)

`completion_automated-task-execution/e2e` 에서 다음 패턴으로 scriptTask success/failure 양쪽을
결정적으로 검증:

1. **proc_def 구조**: `startEvent → userTask_setup → scriptTask → endEvent`. role 은 모두
   `"everyone"`.
2. **proc_inst.role_bindings**: `[{"name": "everyone", "endpoint": ["<human-uuid>"]}]` 로
   미리 매핑. 이렇게 하면 `resolve_next_activity_payloads` 의 `_resolve_next_user_email` 이
   엔드포인트를 채워주어 `check_role_binding` 의 LLM 폴백을 회피.
3. **mock-llm**: 도구(`tools`) 없는 chat completion 요청에는 generic JSON
   `{"completedActivities":[],"nextActivities":[],"assignments":[]}` 를 반환. langgraph
   `CustomJsonOutputParser` 가 무사히 파싱하고, run_completed_determination 의 결과(pure
   Python) 가 있으면 LLM 응답이 비어도 다음 단계로 진행.
4. **mock-llm streaming**: `model = create_llm(streaming=True)` 라 `body.stream=true` SSE
   응답이 필수. content/tool_calls 를 단일 chunk + finish chunk + `[DONE]` 으로 emit.
5. **pythonCode 부수효과 마커**: scriptTask 의 pythonCode 가 `/coverage/ate_script_NN.{out,err}`
   에 결정적 마커를 기록하고 stdout/stderr 에도 출력. Playwright 가 `docker exec ... cat
   /coverage/ate_script_NN.*` 로 마커를 검증.
6. **trigger workitem reservation**: scriptTask 시드는 `consumer='hold-test-NN'` 으로
   reserve, Playwright 가 시나리오 시작 시점에 `consumer=null` 로 해제 (시나리오 직렬화).

처리 후 workitem 은 `[Error] ... timedelta NoneType` 로 retry 3 회 후 DONE 처리되지만,
**첫 시도에서 pythonCode 는 정상 실행**되어 마커 파일이 생성됨. UI 에서는 trigger
userTask 가 DONE 컬럼으로 이동.

## Why

- `handle_service_workitem` 은 serviceTask 전용 단순 경로 (MCP 도구 호출 → 결과 기록)
- `handle_workitem` 은 LangChain 으로 활동 완료 여부와 다음 활동 후보를 LLM 에게 묻는 복잡한 경로
- `run_completed_determination` 은 pure Python — checkpoints 가 없는 userTask 는 자동
  DONE 처리되므로 LLM 호출 없이 completed_json 이 채워짐
- `resolve_next_activity_payloads` 도 pure Python — sequences/gateways 만 보면 됨
- LLM 호출이 실제로 필수가 되는 분기는 `check_event_expression`, `check_subprocess_expression`,
  `check_role_binding` 정도. role_bindings 와 사건이 없는 경우 회피 가능

## How to apply

- Triggered when:
  - scriptTask E2E 시나리오 작성을 시도할 때
  - serviceTask 와 동일한 패턴으로 SUBMITTED workitem 을 시드해도 pythonCode 가 실행되지 않을 때
- Skip if:
  - serviceTask 만 검증하면 충분한 스펙

Related: [[polling-mcp-processor-quirks]], [[completion-bcrypt-seed-stability]]
