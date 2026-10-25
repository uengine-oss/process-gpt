"""process-miner REST API — 프론트엔드 '인계 마이닝' 화면이 읽는 서비스.

instance-classifier 의 서버 구조를 따른다(FastAPI + lifespan). 이 서비스는
handover_events 를 읽기만 하고, 제안은 proc_def_version(draft) + PR 로만 남긴다.
살아 있는 proc_def 는 절대 건드리지 않는다.

엔드포인트
  GET  /health
  GET  /threads          인계 스레드 묶음 (origin_room_id 기준, Gmail forward 묶음)
  GET  /network          핸드오버 네트워크(리소스 간 이관 매트릭스)
  GET  /organization     조직 마이닝 — 역할 클러스터·활동별 자격·네트워크
  GET  /eligibility      특정 활동을 수행할 자격이 있는 사람(근거 건수 포함)
  GET  /discovered       도출된 프로세스(정의 JSON 포함) — BPMN 모델러가 그대로 렌더
  POST /mine             마이닝 실행(PR 생성). dry_run=true 면 제안만 계산. case_ids 로 패턴 하나만
  GET  /patterns         반복 패턴 — 케이스를 활동 집합 유사도로 묶은 업무 묶음(패턴별 도출용)
  POST /discover         case_ids 로 고른 케이스만 도출(PR 없음)
"""
from __future__ import annotations

from collections import defaultdict
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import db, eventlog, miner, organizational, patterns as patterns_mod


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("[BOOT] process-miner 시작")
    yield
    db.close()


app = FastAPI(title="ProcessGPT Process Miner", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/health")
def health():
    try:
        with db.connect().cursor() as cur:
            cur.execute("select 1")
            cur.fetchone()
        return {"status": "ok"}
    except Exception as e:  # noqa: BLE001
        return {"status": "degraded", "detail": str(e)}


@app.get("/threads")
def threads(tenant_id: Optional[str] = Query(default=None), limit: int = 50):
    """인계 스레드 묶음. 한 업무가 여러 방·담당자를 거쳐도 origin_room_id 로 한 줄기."""
    rows = db.fetch_handover_events(tenant_id)
    grouped: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        key = r.get("origin_room_id") or r.get("case_id")
        if not key:
            continue
        grouped[key].append(
            {
                "from": r.get("from_user_name") or r.get("from_user_id"),
                "to": r.get("to_user_name") or r.get("to_user_id"),
                "to_is_agent": bool(r.get("to_is_agent")),
                "activity": r.get("next_activity_label") or r.get("activity_label"),
                "source": r.get("source"),
                "is_explicit": bool(r.get("is_explicit")),
                "occurred_at": str(r.get("occurred_at")),
            }
        )
    out = [
        {"origin_room_id": k, "step_count": len(v), "steps": v}
        for k, v in sorted(grouped.items(), key=lambda kv: -len(kv[1]))
    ]
    return {"count": len(out), "threads": out[:limit]}


@app.get("/network")
def network(tenant_id: Optional[str] = Query(default=None)):
    """리소스 간 이관 매트릭스. 사람과 에이전트를 같은 네트워크로 계산한다."""
    events = eventlog.build_events(db.fetch_handover_events(tenant_id))
    matrix = eventlog.handover_matrix(events)
    profile = eventlog.resource_profile(events)
    automation = {
        act: {
            "total": p["total"],
            "by_agent": p["by_agent"],
            "rate": round(p["by_agent"] / p["total"], 3) if p["total"] else 0,
        }
        for act, p in profile.items()
    }
    return {
        "edges": [{"from": a, "to": b, "count": n} for (a, b), n in sorted(matrix.items(), key=lambda kv: -kv[1])],
        "automation": automation,
    }


@app.get("/organization")
def organization(tenant_id: Optional[str] = Query(default=None)):
    """조직 마이닝 결과. 프로세스의 담당자를 이름이 아니라 역할·역량으로 풀기 위한 근거."""
    events = eventlog.build_events(db.fetch_handover_events(tenant_id))
    return organizational.analyze(events)


@app.get("/eligibility")
def eligibility(activity: str = Query(...), tenant_id: Optional[str] = Query(default=None)):
    """이 활동을 실제로 수행해 온 사람들. 인계 시 '자격 보유' 표시에 쓴다."""
    events = eventlog.build_events(db.fetch_handover_events(tenant_id))
    for e in organizational.activity_eligibility(events):
        if e["activity"] == activity:
            return e
    # 정확히 일치하는 활동이 없으면 부분 일치로 한 번 더 찾는다
    needle = activity.strip()
    for e in organizational.activity_eligibility(events):
        if needle and (needle in e["activity"] or e["activity"] in needle):
            return e
    return {"activity": activity, "required_capability": activity, "observations": 0, "candidates": []}


@app.get("/discovered")
def discovered(
    tenant_id: str = Query(default="localhost"),
    process_id: str = Query(default="mined_quote_process"),
    name: str = Query(default="견적 처리 프로세스"),
    min_freq: int = 1,
):
    """도출된 프로세스. definition 은 ProcessGPT 표준 형식이라 BPMN 모델러가 그대로 렌더한다."""
    result = miner.run(tenant_id=tenant_id, process_id=process_id, process_name=name, min_freq=min_freq, dry_run=True)
    if not result.get("ok"):
        raise HTTPException(status_code=422, detail=result.get("reason", "도출 실패"))
    return {
        "stats": result["stats"],
        "tree": result["tree"],
        "definition": result["definition"],
    }


class MineRequest(BaseModel):
    tenant_id: str = "localhost"
    process_id: str = "mined_quote_process"
    name: str = "견적 처리 프로세스"
    min_freq: int = 1
    dry_run: bool = False
    case_ids: Optional[list[str]] = None


@app.get("/patterns")
def patterns(tenant_id: str = Query(default="localhost"), min_cases: int = patterns_mod.MIN_CASES, similarity: float = patterns_mod.SIMILARITY):
    """반복되는 업무 묶음. 이미 마이닝 PR 이 열린 패턴은 proposed 로 표시한다."""
    found = patterns_mod.find(db.fetch_handover_events(tenant_id), min_cases=min_cases, similarity=similarity)
    prs = {r["resource_id"]: r for r in db.open_mining_prs(tenant_id)}
    for p in found:
        pr = prs.get(p["process_id"])
        p["proposed"] = {"pr_id": str(pr["id"]), "status": pr["status"], "branch": pr["branch_name"]} if pr else None
    return {"count": len(found), "patterns": found}


class DiscoverRequest(BaseModel):
    tenant_id: str = "localhost"
    process_id: str
    name: str
    case_ids: list[str]
    min_freq: int = 1


@app.post("/discover")
def discover_cases(req: DiscoverRequest):
    """고른 케이스만으로 도출한다(쓰기 없음)."""
    result = miner.run(tenant_id=req.tenant_id, process_id=req.process_id, process_name=req.name,
                       min_freq=req.min_freq, dry_run=True, case_ids=req.case_ids)
    if not result.get("ok"):
        raise HTTPException(status_code=422, detail=result.get("reason", "도출 실패"))
    return {"stats": result["stats"], "tree": result["tree"], "definition": result["definition"]}


@app.post("/mine")
def mine(req: MineRequest):
    """마이닝 실행. dry_run=false 면 draft 버전 + PR 을 만든다(살아있는 proc_def 는 안 건드림)."""
    result = miner.run(
        tenant_id=req.tenant_id,
        process_id=req.process_id,
        process_name=req.name,
        min_freq=req.min_freq,
        dry_run=req.dry_run,
        case_ids=req.case_ids,
    )
    if not result.get("ok"):
        raise HTTPException(status_code=422, detail=result.get("reason", "도출 실패"))
    return result
