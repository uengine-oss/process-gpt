"""분기 판단 이력 저장 -> 조회 왕복을 실제 DB 로 검증한다."""
import os, sys, json
sys.path.insert(0, os.getcwd())

from dotenv import dotenv_values
env = dotenv_values('/Users/uengine/process-gpt/.env')
url = env['SUPABASE_URL']
key = env['SERVICE_ROLE_KEY']

from supabase import create_client
import database
from decision_journal import DecisionRecorder, RULE_SINGLE_TRUE, RULE_NO_CANDIDATE, METHOD_NATURAL_LANGUAGE, VERDICT_TRUE, VERDICT_FALSE

client = create_client(url, key)
database.supabase_client_var.set(client)

INST = "journal.e2e.instance.1"
TENANT = "localhost"

# 정리
client.table("events").delete().eq("proc_inst_id", INST).execute()

rec = DecisionRecorder(
    proc_inst_id=INST, root_proc_inst_id=INST, proc_def_id="journal.e2e",
    proc_def_version="1", activity_id="Task_A", workitem_id="journal-e2e-wi-1",
    tenant_id=TENANT, execution_scope=None, rework_count=0,
)
rec.record_llm_trace(prompt={"conditions": [{"sequenceId": "Flow_3"}]},
                     response='{"results":[{"sequenceId":"Flow_3","conditionMet":true,"reason":"1200만원"}]}',
                     sequence_ids=["Flow_3"])
rec.record_sequence_evaluation("Flow_3", method=METHOD_NATURAL_LANGUAGE, verdict=VERDICT_TRUE,
                               effective=True, reason="신청 금액이 1200만원", input_snapshot={"form_a": {"amount": 12000000}})
rec.record_sequence_evaluation("Flow_4", method=METHOD_NATURAL_LANGUAGE, verdict=VERDICT_FALSE, effective=False)
rec.record_decision(source_id="Gateway_1", source_name="금액 구분", source_type="gateway",
                    branch_type="exclusiveGateway", selection_rule=RULE_SINGLE_TRUE,
                    candidate_sequence_ids=["Flow_3", "Flow_4"], selected_sequence_ids=["Flow_3"],
                    selected_targets=[{"activityId": "Task_B", "activityName": "팀장 승인"}])

rows = rec.build_events()
database.insert_events(rows, TENANT, client=client)
print(f"inserted {len(rows)} rows")

# 조회
events = database.fetch_decision_events_by_proc_inst_id(INST, TENANT, client=client)
print(f"fetched {len(events)} events by proc_inst_id")
assert len(events) == 2, events

by_todo = database.fetch_decision_events_by_todo_id("journal-e2e-wi-1", TENANT, client=client)
assert len(by_todo) == 2, by_todo
print("fetch by todo_id OK")

traversed = database.fetch_traversed_sequence_ids(INST, TENANT, client=client)
print("traversed:", traversed)
assert traversed == ["Flow_3"], traversed

decision = next(e for e in events if e["event_type"] == "gateway_decision")
trace = next(e for e in events if e["event_type"] == "gateway_decision_trace")
assert decision["data"]["selectedSequenceIds"] == ["Flow_3"]
assert decision["data"]["unselectedSequenceIds"] == ["Flow_4"]
assert decision["data"]["evaluations"][0]["reason"] == "신청 금액이 1200만원"
assert decision["data"]["evaluations"][0]["inputSnapshot"] == {"form_a": {"amount": 12000000}}
assert trace["data"]["decisionIds"] == [decision["data"]["decisionId"]]
assert decision["data"]["traceIds"] == [trace["data"]["traceId"]]
print("cross-reference + payload OK")

# 테넌트 격리: 다른 테넌트로 조회하면 안 보여야 한다
other = database.fetch_decision_events_by_proc_inst_id(INST, "other-tenant", client=client)
assert other == [], other
print("tenant isolation OK")

# 이력 없는 인스턴스는 빈 결과 (오류 아님)
assert database.fetch_decision_events_by_proc_inst_id("no.such.instance", TENANT, client=client) == []
assert database.fetch_traversed_sequence_ids("no.such.instance", TENANT, client=client) == []
print("empty-for-unknown-instance OK")

# 재실행 회차 누적: 같은 활동을 다시 판단해도 덮어쓰지 않는다
rec2 = DecisionRecorder(proc_inst_id=INST, proc_def_id="journal.e2e", activity_id="Task_A",
                        workitem_id="journal-e2e-wi-1", tenant_id=TENANT, rework_count=1)
rec2.record_decision(source_id="Gateway_1", selection_rule=RULE_SINGLE_TRUE,
                     candidate_sequence_ids=["Flow_3", "Flow_4"], selected_sequence_ids=["Flow_4"],
                     selected_targets=[{"activityId": "Task_C"}])
database.insert_events(rec2.build_events(), TENANT, client=client)
events2 = database.fetch_decision_events_by_proc_inst_id(INST, TENANT, client=client)
decisions2 = [e for e in events2 if e["event_type"] == "gateway_decision"]
assert len(decisions2) == 2, decisions2
rework = sorted(d["data"].get("reworkCount") for d in decisions2)
assert rework == [0, 1], rework
print("rework accumulation OK:", rework)

client.table("events").delete().eq("proc_inst_id", INST).execute()
print("\nALL E2E CHECKS PASSED")
