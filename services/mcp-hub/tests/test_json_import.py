"""JSON 붙여넣기 방식 회귀 테스트.

기존 등록 방식(mcpServers 블롭 통째로 붙여넣기)이 그대로 동작하되,
결과가 tenants.mcp 가 아니라 정본 테이블에 남는지 확인한다.
(정본에 남지 않으면 sync 트리거가 다음 변경 때 덮어써 유실된다.)

실행: MCP_HUB_URL=http://127.0.0.1:8500 .venv/bin/python tests/test_json_import.py
"""
import json
import os
import sys
import uuid

import httpx

HUB = os.getenv("MCP_HUB_URL", "http://127.0.0.1:8500").rstrip("/")
TENANT = os.getenv("TEST_TENANT", "__json_import_test__")
H = {"X-Tenant-Id": TENANT, "X-User-Email": "test@uengine.org"}
DB = os.getenv(
    "PROCESSGPT_DB_URL",
    "postgresql://postgres:your-super-secret-and-long-postgres-password@127.0.0.1:54322/postgres",
)
results = []


def check(name, ok, detail=""):
    results.append((ok, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  — {detail}" if detail else ""))


def sql(q, params=None, fetch=True):
    import psycopg
    from psycopg.rows import dict_row
    with psycopg.connect(DB) as c, c.cursor(row_factory=dict_row) as cur:
        cur.execute(q, params)
        return cur.fetchall() if fetch else None


BLOB = {
    "mcpServers": {
        "j-stdio": {"command": "uvx", "args": ["some-mcp"], "env": {"K": "V"}},
        "j-http": {"type": "streamable-http", "url": "http://svc:8000/mcp",
                   "headers": {"Authorization": "Bearer x"}},
        "j-off": {"command": "node", "args": ["s.js"], "enabled": False},
    }
}


def main() -> int:
    sql("insert into public.tenants (id, owner) values (%s, null) "
        "on conflict (id) do nothing", [TENANT], fetch=False)

    with httpx.Client(timeout=60) as c:
        print("\n[1] JSON 붙여넣기로 등록")
        r = c.post(f"{HUB}/servers/import", headers=H,
                   json={"mcpServers": BLOB["mcpServers"], "validate_after": False})
        r.raise_for_status()
        d = r.json()
        check("3개 생성", sorted(d["created"]) == ["j-http", "j-off", "j-stdio"], str(d["created"]))

        print("\n[2] 정본 테이블에 남았는가 (트리거에 덮이지 않는 조건)")
        rows = sql("select s.name, s.enabled, v.transport, v.command, v.url "
                   "from public.mcp_server s "
                   "join public.mcp_server_version v on v.id = s.current_version_id "
                   "where s.tenant_id = %s and s.is_deleted = false order by s.name", [TENANT])
        by = {r["name"]: r for r in rows}
        check("mcp_server 3행", len(rows) == 3, str(sorted(by)))
        check("stdio 로 해석", by.get("j-stdio", {}).get("transport") == "stdio")
        check("http -> streamable-http", by.get("j-http", {}).get("transport") == "streamable-http")
        check("enabled=false 보존", by.get("j-off", {}).get("enabled") is False)

        print("\n[3] 내보내기가 원본과 의미적으로 같은가")
        exp = c.get(f"{HUB}/servers/export", headers=H).json()["mcpServers"]
        def norm(d):
            out = {}
            for k, v in d.items():
                x = {kk: vv for kk, vv in v.items() if kk not in ("enabled", "is_default")}
                if x.get("type") == "http":
                    x["type"] = "streamable-http"
                out[k] = x
            return out
        check("왕복 동치", norm(exp) == norm(BLOB["mcpServers"]),
              f"{sorted(exp)}")

        print("\n[4] 같은 JSON 을 다시 넣으면 새 버전이 생기지 않는다")
        d2 = c.post(f"{HUB}/servers/import", headers=H,
                    json={"mcpServers": BLOB["mcpServers"], "validate_after": False}).json()
        check("전부 unchanged", sorted(d2["unchanged"]) == ["j-http", "j-off", "j-stdio"],
              f"created={d2['created']} updated={d2['updated']}")
        n = sql("select count(*) as n from public.mcp_server_version where tenant_id = %s",
                [TENANT])[0]["n"]
        check("버전이 3개 그대로", n == 3, f"{n}개")

        print("\n[5] URL 을 고치면 새 버전이 쌓인다")
        mod = json.loads(json.dumps(BLOB["mcpServers"]))
        mod["j-http"]["url"] = "http://svc:9000/mcp"
        d3 = c.post(f"{HUB}/servers/import", headers=H,
                    json={"mcpServers": mod, "validate_after": False}).json()
        check("j-http 만 갱신", d3["updated"] == ["j-http"], str(d3["updated"]))
        vs = sql("select v.version from public.mcp_server_version v "
                 "join public.mcp_server s on s.id = v.server_id "
                 "where s.name = 'j-http' and s.tenant_id = %s order by v.version", [TENANT])
        check("버전 2개로", [x["version"] for x in vs] == [1, 2], str([x["version"] for x in vs]))

        print("\n[6] 빠진 항목은 정리된다 (prune)")
        d4 = c.post(f"{HUB}/servers/import", headers=H,
                    json={"mcpServers": {"j-http": mod["j-http"]}, "validate_after": False}).json()
        check("2개 제거", sorted(d4["removed"]) == ["j-off", "j-stdio"], str(d4["removed"]))

        print("\n[7] prune=false 면 남긴다")
        c.post(f"{HUB}/servers/import", headers=H,
               json={"mcpServers": BLOB["mcpServers"], "validate_after": False})
        d5 = c.post(f"{HUB}/servers/import", headers=H,
                    json={"mcpServers": {"j-http": mod["j-http"]},
                          "prune": False, "validate_after": False}).json()
        check("제거 없음", d5["removed"] == [], str(d5["removed"]))

        print("\n[8] 레거시 tenants.mcp 미러도 따라온다")
        blob = sql("select mcp from public.tenants where id = %s", [TENANT])[0]["mcp"]
        check("미러 동기화", set((blob or {}).get("mcpServers", {})) ==
              set(x["name"] for x in sql(
                  "select name from public.mcp_server where tenant_id = %s and is_deleted = false",
                  [TENANT])),
              str(sorted((blob or {}).get("mcpServers", {}))))

    sql("delete from public.mcp_server where tenant_id = %s", [TENANT], fetch=False)
    sql("delete from public.tenants where id = %s", [TENANT], fetch=False)

    failed = [r for r in results if not r[0]]
    print(f"\n{'='*60}\n{len(results)-len(failed)}/{len(results)} 통과")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
