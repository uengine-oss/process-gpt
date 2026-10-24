"""엔진 게이트 통합 테스트.

deepagents 의 hub_allowed_servers() 가 허브의 판정을 그대로 받아오는지,
그리고 허브에 닿지 못할 때 기존 tenants.mcp 경로로 폴백하는지 확인한다.

실행:
  cd services/mcp-hub
  MCP_HUB_URL=http://127.0.0.1:8500 .venv/bin/python tests/test_engine_gate.py
"""
import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "deepagents"))

import httpx  # noqa: E402

HUB = os.getenv("MCP_HUB_URL", "http://127.0.0.1:8500").rstrip("/")
TENANT = "localhost"
AGENT = os.getenv("TEST_AGENT", "ae2e7322-6b5f-5514-96c2-22cfb1f458d5")

os.environ["MCP_HUB_URL"] = HUB
from core.llm.mcp import _is_enabled, hub_allowed_servers  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))


async def set_perms(server_id, entries):
    async with httpx.AsyncClient(timeout=10) as c:
        await c.put(f"{HUB}/servers/{server_id}/permissions",
                    headers={"X-Tenant-Id": TENANT}, json=entries)


async def patch_server(server_id, patch):
    async with httpx.AsyncClient(timeout=10) as c:
        await c.patch(f"{HUB}/servers/{server_id}",
                      headers={"X-Tenant-Id": TENANT}, json=patch)


async def main() -> int:
    async with httpx.AsyncClient(timeout=10) as c:
        servers = (await c.get(f"{HUB}/servers", headers={"X-Tenant-Id": TENANT})).json()
    demo = next((s for s in servers if s["name"] == "demo-inventory"), None)
    if not demo:
        print("demo-inventory 서버가 없습니다"); return 1
    sid = demo["id"]

    # 깨끗한 상태에서 시작
    await set_perms(sid, [])
    await patch_server(sid, {"enabled": True})

    print("\n[1] 허브 게이트 기본 동작")
    allowed = await hub_allowed_servers(TENANT, AGENT)
    check("허브가 응답", allowed is not None, str(list(allowed or {})))
    check("바인딩된 서버가 보임", "demo-inventory" in (allowed or {}))

    print("\n[2] enabled=false 를 엔진이 실제로 존중한다")
    await patch_server(sid, {"enabled": False})
    off = await hub_allowed_servers(TENANT, AGENT)
    check("허브 경로에서 제외", "demo-inventory" not in (off or {}), str(list(off or {})))
    check("jsonb 폴백 경로에서도 제외",
          _is_enabled({"url": "x", "enabled": False}) is False)
    check("enabled 미지정이면 사용", _is_enabled({"url": "x"}) is True)
    await patch_server(sid, {"enabled": True})

    print("\n[3] 툴 단위 차단이 엔진까지 전달된다")
    await set_perms(sid, [{"principal_type": "tenant", "permission": "use",
                           "denied_tools": ["create_stock_adjustment"]}])
    gated = await hub_allowed_servers(TENANT, AGENT)
    tools = (gated or {}).get("demo-inventory", {}).get("tools")
    check("허용 툴 목록이 내려옴", tools is not None, str(tools))
    check("파괴적 툴이 빠짐", tools is not None and "create_stock_adjustment" not in tools)
    check("읽기 툴은 남음", tools is not None and "check_stock" in tools)

    print("\n[4] 부서 권한 불일치면 서버 자체가 사라진다")
    await set_perms(sid, [{"principal_type": "department", "principal_id": "영업팀",
                           "permission": "use"}])
    denied = await hub_allowed_servers(TENANT, AGENT)
    check("권한 없는 에이전트에게 미노출", "demo-inventory" not in (denied or {}),
          str(list(denied or {})))

    print("\n[5] 허브에 못 닿으면 폴백(None)")
    import core.llm.mcp as m
    saved = m.MCP_HUB_URL
    m.MCP_HUB_URL = "http://127.0.0.1:1"
    fallback = await hub_allowed_servers(TENANT, AGENT)
    m.MCP_HUB_URL = saved
    check("None 을 돌려줘 tenants.mcp 로 폴백", fallback is None)

    # 원상복구
    await set_perms(sid, [])
    await patch_server(sid, {"enabled": True})

    failed = [r for r in results if not r[0]]
    print(f"\n{'='*60}\n{len(results)-len(failed)}/{len(results)} 통과")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
