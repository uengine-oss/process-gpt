#!/usr/bin/env python
"""Seed and execute real DeepAgents deterministic replay/undo demo workitems."""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DEEPAGENTS = REPO / "services/deepagents"
ENV_FILE = REPO / "docker-infra/.env"

FIRST = "22222222-3333-4444-5555-666666660001"
REPLAY = "22222222-3333-4444-5555-666666660002"
UNDO = "22222222-3333-4444-5555-666666660003"


def load_env() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in ENV_FILE.read_text().splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip().strip("'").strip('"')
    return out


def psql(sql: str) -> None:
    proc = subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-v", "ON_ERROR_STOP=1",
         "-U", "postgres", "-d", "postgres"],
        input=sql, text=True, capture_output=True,
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr)


def seed() -> None:
    psql(
        f"""
delete from public.events where todo_id in ('{FIRST}','{REPLAY}','{UNDO}');
delete from public.todolist where id in ('{FIRST}'::uuid,'{REPLAY}'::uuid,'{UNDO}'::uuid);
delete from public.inventory_log;
insert into public.inventory(product_name,stock) values ('iPhone',20),('Galaxy',35)
on conflict(product_name) do update set stock=excluded.stock,updated_at=now();

insert into public.todolist
  (id,user_id,username,proc_inst_id,root_proc_inst_id,proc_def_id,activity_id,
   activity_name,status,tenant_id,agent_orch,rework_count,query,description,start_date,end_date)
select v.id::uuid,u.id::text,'demo',v.inst,v.root_inst,'order_fulfillment_demo',
       'update_inventory','DeepAgents 재고 반영','DONE','localhost','deepagents',
       v.rework,v.query,v.description,now()-interval '15 minutes',now()
from (values
 ('{FIRST}','deepagents-demo.original','deepagents-demo.original',0,
  'iPhone 상품의 발주 입고를 반영하라. 입고 수량은 60, 반영 후 재고는 80, 변경 사유는 발주 입고.',
  'DeepAgents 1차 LLM 실행 — MCP 호출 이력 기록'),
 ('{REPLAY}','deepagents-demo.replay','deepagents-demo.replay',0,
  'Galaxy 상품의 발주 입고를 반영하라. 입고 수량은 215, 반영 후 재고는 250, 변경 사유는 발주 입고.',
  'DeepAgents Replay — 고착화된 코드, LLM 추론 0회'),
 ('{UNDO}','deepagents-demo.rework','deepagents-demo.original',1,
  'iPhone 상품의 정정 입고를 반영하라. 입고 수량은 40, 반영 후 재고는 60, 변경 사유는 재작업 반영.',
  'DeepAgents Undo 후 Replay — LLM 추론 0회')
) v(id,inst,root_inst,rework,query,description)
cross join (select id from auth.users where email='demo@localhost' limit 1) u;

-- The first execution represents the real MCP side effects whose recorded
-- tool calls are the source for replay and undo.
update public.inventory set stock=stock+60,updated_at=now() where product_name='iPhone';
insert into public.inventory_log(product_name,new_stock,reason)
values('iPhone',80,'발주 입고');
"""
    )


def save_card(db, todo_id: str, proc_inst_id: str, mode: str, output: dict) -> None:
    job_id = str(uuid.uuid4())
    is_undo = mode == "deterministic-undo"
    name = "DeepAgents Undo 후 재실행 결과" if is_undo else "DeepAgents 결정론적 코드 실행 결과"
    rows = [
        {
            "id": str(uuid.uuid4()), "job_id": job_id, "todo_id": todo_id,
            "proc_inst_id": proc_inst_id, "event_type": "task_started",
            "crew_type": "result",
            "data": {
                "role": name, "name": name,
                "goal": "저장된 코드로 LLM 추론 없이 실행합니다.",
                "agent_profile": "/images/chat-icon.png", "execution_mode": mode,
            },
        },
        {
            "id": str(uuid.uuid4()), "job_id": job_id, "todo_id": todo_id,
            "proc_inst_id": proc_inst_id, "event_type": "task_completed",
            "crew_type": "result",
            "data": {
                "result": output, "execution_mode": mode,
                "engine": "deepagents", "llm_calls": 0,
            },
        },
    ]
    db.table("events").insert(rows).execute()


async def main() -> None:
    env = load_env()
    os.environ["SUPABASE_URL"] = "http://localhost:54321"
    os.environ["SUPABASE_KEY"] = env["SERVICE_ROLE_KEY"]
    os.environ["SERVICE_ROLE_KEY"] = env["SERVICE_ROLE_KEY"]
    sys.path.insert(0, str(DEEPAGENTS))

    seed()
    from core.storage.db import get_supabase
    from core.deterministic import try_deterministic_execution

    db = get_supabase()
    mcp = db.table("tenants").select("mcp").eq("id", "localhost").single().execute().data["mcp"]

    # First-run tool history: same event contract emitted by DeepAgentExecutor.
    first_job = str(uuid.uuid4())
    first_events = [
        ("task_started", "deepagents", {
            "role": "DeepAgents 1차 LLM 실행", "name": "DeepAgents 1차 LLM 실행",
            "goal": "MCP 도구를 선택해 재고 반영 경로를 수행합니다.", "execution_mode": "llm",
        }),
        ("tool_usage_started", "deepagents", {"tool_name": "execute_sql", "query": "UPDATE inventory ..."}),
        ("tool_usage_finished", "deepagents", {
            "tool_name": "execute_sql",
            "args": {"sql": "UPDATE inventory SET stock = stock + 60 WHERE product_name = 'iPhone';"},
        }),
        ("tool_usage_started", "deepagents", {"tool_name": "execute_sql", "query": "INSERT inventory_log ..."}),
        ("tool_usage_finished", "deepagents", {
            "tool_name": "execute_sql",
            "args": {"sql": "INSERT INTO inventory_log (product_name,new_stock,reason) VALUES ('iPhone',80,'발주 입고');"},
        }),
        ("task_completed", "deepagents", {
            "result": "iPhone 재고와 감사 로그 반영 완료", "execution_mode": "llm",
        }),
    ]
    db.table("events").insert([
        {
            "id": str(uuid.uuid4()), "job_id": first_job, "todo_id": FIRST,
            "proc_inst_id": "deepagents-demo.original", "event_type": event_type,
            "crew_type": crew_type, "data": data,
        }
        for event_type, crew_type, data in first_events
    ]).execute()

    replay_row = db.table("todolist").select("*").eq("id", REPLAY).single().execute().data
    replay = await try_deterministic_execution(replay_row, mcp)
    assert replay and replay.mode == "deterministic"
    save_card(db, REPLAY, replay_row["proc_inst_id"], replay.mode, replay.output)

    undo_row = db.table("todolist").select("*").eq("id", UNDO).single().execute().data
    undo = await try_deterministic_execution(undo_row, mcp)
    assert undo and undo.mode == "deterministic-undo"
    save_card(db, UNDO, undo_row["proc_inst_id"], undo.mode, undo.output)

    inventory = db.table("inventory").select("product_name,stock").order("product_name").execute().data
    events = (
        db.table("events").select("todo_id,event_type,crew_type,data")
        .in_("todo_id", [FIRST, REPLAY, UNDO]).order("timestamp").execute().data
    )
    result = {"workitems": [FIRST, REPLAY, UNDO], "inventory": inventory, "events": events}
    (HERE / "live_demo_data.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps({"ok": True, "inventory": inventory, "event_count": len(events)}, ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main())
