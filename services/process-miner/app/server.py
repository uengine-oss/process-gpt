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
  GET  /processes        업무 묶음 목록 — 서로 다른 업무를 갈라 묶음마다 도출한다
  GET  /discovered       도출된 프로세스(정의 JSON 포함) — BPMN 모델러가 그대로 렌더. process_key 로 묶음 지정
  POST /mine             마이닝 실행(PR 생성). dry_run=true 면 제안만 계산
"""
from __future__ import annotations

import os
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import db, eventlog, grouping, miner, organizational


@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"[BOOT] process-miner 시작 (인증 {'사용' if _auth_required() else '끔 — 개발용'})")
    yield
    db.close()


app = FastAPI(title="ProcessGPT Process Miner", version="0.2.0", lifespan=lifespan)
# 게이트웨이(nginx)·vite 프록시를 거치면 같은 출처라 CORS 가 필요 없다. 직접 부르는 출처만 연다.
_origins = [o.strip() for o in os.environ.get("MINER_CORS_ORIGINS", "").split(",") if o.strip()]
if _origins:
    app.add_middleware(CORSMiddleware, allow_origins=_origins, allow_methods=["GET", "POST"], allow_headers=["*"])


def _auth_required() -> bool:
    return os.environ.get("MINER_AUTH", "required").strip().lower() not in ("off", "false", "0", "disabled")


async def tenant_scope(request: Request) -> str:
    """요청이 볼 수 있는 테넌트 하나.

    기본은 요청자의 Supabase JWT 를 검증해 그 사용자가 속한 테넌트만 허용한다
    (agent SDK 의 tenant_auth 와 같은 규칙). 요청이 보낸 tenant_id 는 그 집합 안에 있을
    때만 통과한다. MINER_AUTH=off 는 로컬 단위 확인용이며, 그때도 tenant_id 는 필수다.
    어느 경우에도 tenant_id 없이 전체 테넌트 기록을 돌려주지 않는다.
    """
    if not _auth_required():
        tenant = (request.query_params.get("tenant_id") or "").strip()
        if not tenant and request.method == "POST":
            try:
                tenant = str((await request.json()).get("tenant_id") or "").strip()
            except Exception:  # noqa: BLE001
                tenant = ""
        if not tenant:
            raise HTTPException(status_code=400, detail="tenant_id 가 필요합니다")
        request.state.tenant_id = tenant
        request.state.user_id = ""
        return tenant

    from processgpt_agent_sdk.tenant_auth import TenantAuthError, authorize_tenant

    try:
        await authorize_tenant(request)
    except TenantAuthError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message) from e
    return request.state.tenant_id


@app.get("/health")
def health():
    try:
        db.query("select 1 as ok")
        return {"status": "ok"}
    except Exception as e:  # noqa: BLE001
        return {"status": "degraded", "detail": str(e)}


def _thread_steps(rows: list[dict]) -> list[dict]:
    """한 스레드의 단계. 첫 인계는 넘긴 사람이 한 일을 시작 단계로 앞에 둔다(도출과 같은 규칙)."""
    rows = sorted(rows, key=lambda r: str(r.get("occurred_at")))
    steps: list[dict] = []
    first = next((r for r in rows if r.get("source") in ("chat_handover", "todolist")), None) or {}
    done = eventlog.normalize_label(first.get("activity_label"))
    if done and first.get("from_user_id"):
        steps.append(
            {
                "from": None,
                "to": first.get("from_user_name") or first.get("from_user_id"),
                "to_is_agent": bool(first.get("from_is_agent")),
                "activity": done,
                "source": "start",
                "is_explicit": True,
                "occurred_at": str(rows[0].get("occurred_at")),
            }
        )
    for r in rows:
        steps.append(
            {
                "from": r.get("from_user_name") or r.get("from_user_id"),
                "to": r.get("to_user_name") or r.get("to_user_id"),
                "to_is_agent": bool(r.get("to_is_agent")),
                "activity": eventlog.pick_label(r) or r.get("activity_label"),
                "source": r.get("source"),
                "is_explicit": bool(r.get("is_explicit")),
                "occurred_at": str(r.get("occurred_at")),
            }
        )
    return steps


@app.get("/threads")
def threads(tenant: str = Depends(tenant_scope), limit: int = 50):
    """인계 스레드 묶음. 한 업무가 여러 방·담당자를 거쳐도 origin_room_id 로 한 줄기.

    스레드마다 업무 묶음(process_key)을 붙인다. 끝난 스레드는 속한 묶음, 진행 중 스레드는 가장
    가까운 묶음(표시용). 어디에도 가깝지 않으면 null.
    """
    rows = db.fetch_handover_events(tenant)
    groups = miner.processes(rows, tenant)["processes"]
    key_of: dict[str, str] = {}
    for p in groups:
        for c in p["cases"]:
            key_of[c] = p["process_key"]
    # 진행 중 스레드는 거친 단계가 가장 많이 겹치는 업무에 붙여 보인다(도출에는 넣지 않는다)
    open_traces = eventlog.to_traces(eventlog.build_events(rows))
    for c, t in open_traces.items():
        if c not in key_of and t:
            k = grouping.closest(t, groups)
            if k:
                key_of[c] = k
    grouped: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        key = r.get("origin_room_id") or r.get("case_id")
        if key:
            grouped[key].append(r)
    out = []
    for k, rs in grouped.items():
        steps = _thread_steps(rs)
        out.append(
            {
                "origin_room_id": k,
                "step_count": len(steps),
                "finished": eventlog.thread_finished(rs),
                "process_key": key_of.get(k),
                "steps": steps,
            }
        )
    out.sort(key=lambda t: (-t["step_count"], t["origin_room_id"]))
    return {"count": len(out), "threads": out[:limit]}


@app.get("/network")
def network(tenant: str = Depends(tenant_scope)):
    """리소스 간 이관 매트릭스. 사람과 에이전트를 같은 네트워크로 계산한다(위임 포함)."""
    events = eventlog.build_events(db.fetch_handover_events(tenant))
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
def organization(tenant: str = Depends(tenant_scope)):
    """조직 마이닝 결과. 프로세스의 담당자를 이름이 아니라 역할·역량으로 풀기 위한 근거."""
    events = eventlog.build_events(db.fetch_handover_events(tenant))
    return organizational.analyze(events)


@app.get("/eligibility")
def eligibility(activity: str = Query(...), tenant: str = Depends(tenant_scope)):
    """이 활동을 실제로 수행해 온 사람들. 인계 시 '자격 보유' 표시에 쓴다."""
    events = eventlog.build_events(db.fetch_handover_events(tenant))
    rows = organizational.activity_eligibility(events)
    for e in rows:
        if e["activity"] == activity:
            return e
    # 정확히 일치하는 활동이 없으면 부분 일치로 한 번 더 찾는다
    needle = activity.strip()
    for e in rows:
        if needle and (needle in e["activity"] or e["activity"] in needle):
            return e
    return {"activity": activity, "required_capability": activity, "observations": 0, "candidates": []}


@app.get("/processes")
def processes(tenant: str = Depends(tenant_scope)):
    """업무 묶음 목록. 끝난 스레드를 거친 단계가 겹치는 것끼리 묶는다(grouping)."""
    out = miner.processes(db.fetch_handover_events(tenant), tenant)
    for p in out["processes"]:
        p.pop("cases", None)
    return out


@app.get("/discovered")
def discovered(
    tenant: str = Depends(tenant_scope),
    process_id: Optional[str] = Query(default=None),
    name: Optional[str] = Query(default=None),
    process_key: Optional[str] = Query(default=None),
    min_freq: int = 1,
):
    """도출된 프로세스. definition 은 ProcessGPT 표준 형식이라 BPMN 모델러가 그대로 렌더한다."""
    result = miner.run(
        tenant_id=tenant, process_id=process_id, process_name=name, min_freq=min_freq, dry_run=True, process_key=process_key
    )
    if not result.get("ok"):
        raise HTTPException(status_code=422, detail=result.get("reason", "도출 실패"))
    return {
        "stats": result["stats"],
        "tree": result["tree"],
        "definition": result["definition"],
    }


class MineRequest(BaseModel):
    tenant_id: Optional[str] = None
    process_id: Optional[str] = None
    name: Optional[str] = None
    min_freq: int = 1
    dry_run: bool = False
    process_key: Optional[str] = None


@app.post("/mine")
def mine(req: MineRequest, request: Request, tenant: str = Depends(tenant_scope)):
    """마이닝 실행. dry_run=false 면 draft 버전 + PR 을 만든다(살아있는 proc_def 는 안 건드림)."""
    result = miner.run(
        tenant_id=tenant,
        process_id=req.process_id,
        process_name=req.name,
        min_freq=req.min_freq,
        dry_run=req.dry_run,
        requester_id=getattr(request.state, "user_id", "") or None,
        process_key=req.process_key,
    )
    if not result.get("ok"):
        raise HTTPException(status_code=422, detail=result.get("reason", "도출 실패"))
    return result
