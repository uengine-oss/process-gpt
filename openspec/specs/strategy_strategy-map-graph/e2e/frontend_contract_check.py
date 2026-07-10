#!/usr/bin/env python
"""Task 10.6 프론트엔드 계약 무변경 대조 스크립트.

레거시 SQL 구현(process-gpt-strategy, http://localhost:8014, 읽기 전용)과 신규 그래프
구현(http://127.0.0.1:8114) 의 GET /api/map 응답 키 구조를 대조한다. 실행 중 컨테이너는
수정하지 않는다(레거시는 조회만).

실행:
  services/strategy/.venv/bin/python \
    openspec/specs/strategy_strategy-map-graph/e2e/frontend_contract_check.py
"""
import json
import os
import time
import uuid

import httpx

LEG = os.getenv("LEGACY_BASE_URL", "http://localhost:8014")
NEW = os.getenv("E2E_BASE_URL", "http://127.0.0.1:8114")
LEGACY_TENANT = os.getenv("LEGACY_TENANT", "localhost")

# 레거시 strategy_initiatives 테이블 컬럼(= 레거시 핸들러가 행을 그대로 반환하는 키).
# 레거시 테넌트에 이니셔티브 데이터가 없을 때의 대조 기준.
LEGACY_INITIATIVE_COLUMNS = sorted([
    "id", "tenant_id", "objective_id", "name", "description", "owner_email",
    "status", "progress", "proc_def_id", "start_date", "due_date",
    "created_at", "updated_at",
])


def keys(m, which):
    for obj in m["objectives"]:
        if which == "obj":
            return sorted(obj.keys())
        arr = "kpis" if which == "kpi" else "initiatives"
        if obj.get(arr):
            return sorted(obj[arr][0].keys())
    return []


def main():
    leg = httpx.get(f"{LEG}/api/map", params={"tenant_id": LEGACY_TENANT}, timeout=10).json()

    t = f"e2e-contract-{int(time.time())}-{uuid.uuid4().hex[:6]}"
    c = httpx.Client(base_url=NEW, timeout=15)
    o = c.post(f"/api/objectives?tenant_id={t}",
               json={"name": "목표", "perspective": "customer"}).json()
    c.post(f"/api/kpis?tenant_id={t}", json={
        "objective_id": o["id"], "name": "K", "measure_type": "survey_score",
        "direction": "increase", "baseline_value": 0, "target_value": 5})
    c.post(f"/api/initiatives?tenant_id={t}", json={"objective_id": o["id"], "name": "I"})
    new = c.get(f"/api/map?tenant_id={t}").json()
    c.close()

    report = {"top_level": {"legacy": sorted(leg.keys()), "new": sorted(new.keys())}}
    for level, w in (("objectives", "obj"), ("kpis", "kpi"), ("initiatives", "init")):
        lk = keys(leg, w)
        if not lk and w == "init":
            lk = LEGACY_INITIATIVE_COLUMNS  # 레거시 데이터 없음 → 테이블 컬럼 기준
        nk = keys(new, w)
        report[level] = {
            "legacy": lk, "new": nk,
            "legacy_keys_preserved": set(lk) <= set(nk),
            "only_new": sorted(set(nk) - set(lk)),
            "only_legacy": sorted(set(lk) - set(nk)),
        }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
