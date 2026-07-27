#!/bin/bash
# Off-camera companion to record_wms_full_demo.mjs.
#
# The ProcessGPT agent files what it saw. It signs in as the real
# process-agent-a@demo.local identity and calls wms_propose_agent_action /
# wms_log_agent_decision over PostgREST — the same RPCs the MCP tools wrap and
# the same ones the UI calls. PROCESS_AGENT has no grant for the actions it is
# proposing, which is the whole point: they land as PROPOSED and wait for a
# human.
set -euo pipefail
BASE=http://127.0.0.1:55321
ANON=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
TA=10000000-0000-0000-0000-00000000000a
WA=20000000-0000-0000-0000-00000000000a
DB=supabase_db_process-gpt-sample-app-wms

TOK=$(curl -s -X POST "$BASE/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H 'Content-Type: application/json' \
  -d '{"email":"process-agent-a@demo.local","password":"Demo1234!"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

rpc() {
  curl -s -X POST "$BASE/rest/v1/rpc/$1" -H "apikey: $ANON" -H "Authorization: Bearer $TOK" \
    -H 'Content-Profile: wms' -H 'Accept-Profile: wms' -H 'Content-Type: application/json' -d "$2"
  echo
}
q() { docker exec -i "$DB" psql -U postgres -d postgres -qAt -c "$1"; }

AGENT_ID=$(q "select id from auth.users where email='process-agent-a@demo.local'")
PROD_A2=$(q "select id from wms.products where sku='SKU-A-002' and tenant_id='$TA'")
UUID1=$(uuidgen); UUID2=$(uuidgen); UUID3=$(uuidgen)
# The audit log joins reasoning by correlation_id and takes the MOST RECENT
# matching decision, so each decision needs its OWN id — reuse one across all
# three and every agent row in the log renders the last decision's reasoning.
STAMP=$(date +%H%M%S)
CORR1=DEMO-AGENT-SLOTTING-$STAMP
CORR2=DEMO-AGENT-LABOR-$STAMP
CORR3=DEMO-AGENT-DISPATCH-$STAMP

# 1) The gap the slotting board just showed on screen: class B has no policy,
#    so SKU-A-002 was silently dropped from recommendation generation.
rpc wms_propose_agent_action "$(python3 - "$TA" "$WA" "$PROD_A2" "$UUID1" "$AGENT_ID" "$CORR1" <<'PYEOF'
import json,sys
ta,wa,prod,key,actor,corr = sys.argv[1:7]
print(json.dumps({
 "p_tenant_id": ta, "p_warehouse_id": wa,
 "p_proposal_type": "SLOTTING_POLICY_GAP",
 "p_target_entity_type": "product", "p_target_entity_id": prod,
 "p_reasoning": ("\ubc29\uae08 \uacc4\uc0b0\ub41c \ucd9c\ud558 \uc18d\ub3c4\uc5d0\uc11c SKU-A-002(Pallet Wrap Roll)\ub294 \ucd9c\ud558 15\uac1c\ub85c B\ub4f1\uae09\uc744 \ubc1b\uc558\uc9c0\ub9cc, "
   "B\ub4f1\uae09\uc5d0\ub294 \ubaa9\ud45c \uc811\uadfc\uc131 \uc815\ucc45\uc774 \uc5c6\uc5b4 \ucd94\ucc9c \uc0dd\uc131\uc5d0\uc11c \uadf8\ub300\ub85c \uc81c\uc678\ub410\ub2e4(\uc0dd\uc131 2\uac74, \uc815\ucc45 \uc5c6\uc5b4 \uc81c\uc678\ub41c \ub4f1\uae09 B). "
   "A\ub4f1\uae09\uc740 \uc21c\uc704 5, C\ub4f1\uae09\uc740 \uc21c\uc704 40\uc774\ubbc0\ub85c \uadf8 \uc0ac\uc774\uc778 \uc21c\uc704 10\uc73c\ub85c B\ub4f1\uae09 \uc815\ucc45\uc744 \ub4f1\ub85d\ud560 \uac83\uc744 \uc81c\uc548\ud55c\ub2e4. "
   "\uc815\ucc45 \ub4f1\ub85d\uc740 \ucc3d\uace0 \uc804\uccb4\uc758 \ubc30\uce58 \uae30\uc900\uc744 \ubc14\uafb8\ub294 \uacb0\uc815\uc774\ub77c \uc5d0\uc774\uc804\ud2b8 \uad8c\ud55c \ubc16\uc774\ub2e4."),
 "p_proposed_action": {"rpc": "wms_register_slotting_class_policy", "velocity_class": "B",
   "max_accessibility_rank": 10},
 "p_signals_snapshot": {"velocity_class": "B", "outbound_qty": 15, "outbound_event_count": 1,
   "generated_count": 2, "skipped_no_policy_classes": ["B"],
   "existing_policies": {"A": 5, "C": 40}},
 "p_actor_id": actor, "p_correlation_id": corr,
 "p_idempotency_key": key}, ensure_ascii=False))
PYEOF
)"

# 2) A labor rebalance, also proposal-only.
rpc wms_propose_agent_action "$(python3 - "$TA" "$WA" "$UUID2" "$AGENT_ID" "$CORR2" <<'PY'
import json,sys
ta,wa,key,actor,corr = sys.argv[1:6]
print(json.dumps({
 "p_tenant_id": ta, "p_warehouse_id": wa,
 "p_proposal_type": "LABOR_REBALANCE",
 "p_reasoning": ("오늘 완료된 계측 활동은 inbound-a의 RECEIVING 1건(170개, 1494초)뿐이고 "
   "quality-a는 0건이다. 도크에 붙은 차량 1대분 물량이 검수 대기로 넘어오면 "
   "품질 검사 쪽이 병목이 된다. 오후 적치 일부를 quality-a에게 넘길 것을 제안한다 — "
   "인력 재배치를 실행하는 RPC 자체가 이 시스템에 없으므로 사람이 조치해야 한다."),
 "p_proposed_action": {"move": "PUTAWAY", "from": "inbound-a@demo.local",
   "to": "quality-a@demo.local", "window": "오후"},
 "p_signals_snapshot": {"completed_today": {"inbound-a": 1, "quality-a": 0},
   "units_today": {"inbound-a": 170, "quality-a": 0}},
 "p_actor_id": actor, "p_correlation_id": corr,
 "p_idempotency_key": key}, ensure_ascii=False))
PY
)"

# 3) Something the agent WAS allowed to do, logged after the fact.
rpc wms_log_agent_decision "$(python3 - "$TA" "$WA" "$UUID3" "$AGENT_ID" "$CORR3" <<'PY'
import json,sys
ta,wa,key,actor,corr = sys.argv[1:6]
print(json.dumps({
 "p_tenant_id": ta, "p_warehouse_id": wa,
 "p_proposal_type": "DISPATCH_MONITORING",
 "p_reasoning": ("웨이브 릴리즈 후 AGV-07에 나간 MOVE 명령이 ACKNOWLEDGED에서 COMPLETED까지 "
   "정상 진행되는 것을 확인했다. 큐 적체도 임계값 미만이라 재시도나 라우팅 개입은 하지 않았다. "
   "판단 근거만 남긴다."),
 "p_actor_id": actor, "p_correlation_id": corr,
 "p_idempotency_key": key}, ensure_ascii=False))
PY
)"
