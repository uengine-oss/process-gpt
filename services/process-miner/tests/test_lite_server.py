"""Process GPT Lite 엔드포인트(/patterns · /discover)도 다른 엔드포인트와 같은 테넌트 인증을 거친다.

DB 없이 확인한다(조회를 가로챈다). feat/pgpt-lite-mining 에서는 이 둘이 인증 없이 열려 있었고
/mine 이 초안·PR 을 썼다. 여기서는 토큰 없이 부르면 아무 기록도 읽지 않고, 어느 경로도 쓰지 않는다.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

from app import db, server  # noqa: E402
from app.lite import miner as lite_miner  # noqa: E402


def _case(case, acts, tenant="acme"):
    return [dict(id=f"{case}-{i}", tenant_id=tenant, origin_room_id=case, source="chat_handover",
                 to_user_id=f"u{i}", to_user_name=f"담당{i}", to_role="", to_is_agent=False,
                 next_activity_label=a, occurred_at=f"2026-10-01T00:0{i}:00", artifact_refs=[])
            for i, a in enumerate(acts)]


ROWS = {
    "acme": [r for c in ("c1", "c2", "c3") for r in _case(c, ["견적 요청 접수", "견적 작성", "회신"])],
    "other": [r for c in ("x1", "x2", "x3") for r in _case(c, ["비밀 업무", "비밀 검토"], tenant="other")],
}


@pytest.fixture
def fetched(monkeypatch):
    calls = []

    def fake_fetch(tenant_id, case_ids=None, limit=5000):
        calls.append(tenant_id)
        rows = ROWS.get(tenant_id, [])
        return [r for r in rows if not case_ids or r["origin_room_id"] in case_ids]

    monkeypatch.setattr(lite_miner, "fetch_events", fake_fetch)

    def no_write(*a, **k):
        raise AssertionError("Lite 경로가 DB 에 쓰려 했다")

    monkeypatch.setattr(db, "connect", no_write)
    return calls


DISCOVER = {"tenant_id": "acme", "process_id": "mined_x", "name": "견적", "case_ids": ["c1", "c2", "c3"]}


def test_patterns_without_token_is_rejected(monkeypatch, fetched):
    monkeypatch.delenv("MINER_AUTH", raising=False)
    res = TestClient(server.app).get("/patterns?tenant_id=acme")
    assert res.status_code == 401
    assert fetched == []


def test_discover_without_token_is_rejected(monkeypatch, fetched):
    monkeypatch.delenv("MINER_AUTH", raising=False)
    res = TestClient(server.app).post("/discover", json=DISCOVER)
    assert res.status_code == 401
    assert fetched == []


def test_patterns_need_tenant_even_in_dev_mode(monkeypatch, fetched):
    monkeypatch.setenv("MINER_AUTH", "off")
    assert TestClient(server.app).get("/patterns").status_code == 400
    assert fetched == []


def test_patterns_read_only_the_requested_tenant(monkeypatch, fetched):
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).get("/patterns?tenant_id=acme&min_cases=3")
    assert res.status_code == 200, res.text
    body = res.json()
    assert fetched == ["acme"]
    assert body["count"] == 1
    assert body["patterns"][0]["main_variant"] == ["견적 요청 접수", "견적 작성", "회신"]
    assert "비밀 업무" not in res.text


def test_discover_draws_only_and_writes_nothing(monkeypatch, fetched):
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).post("/discover", json=DISCOVER)
    assert res.status_code == 200, res.text
    body = res.json()
    assert [a["name"] for a in body["definition"]["activities"]] == ["견적 요청 접수", "견적 작성", "회신"]
    assert "pr" not in body


def test_mine_still_refuses_writes(monkeypatch, fetched):
    """Lite 가 예전처럼 /mine 으로 제안을 쓰려 해도 main 의 거절(410)이 그대로다."""
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).post("/mine", json={"tenant_id": "acme", "dry_run": False})
    assert res.status_code == 410


# ---------- 서버 간 호출(service_role 키) ----------

SECRET = "test-secret-for-miner-at-least-32-bytes!!"


def _token(**claims):
    import jwt
    import time

    return jwt.encode({"exp": int(time.time()) + 600, **claims}, SECRET, algorithm="HS256")


@pytest.fixture
def auth_on(monkeypatch):
    from processgpt_agent_sdk import tenant_auth

    monkeypatch.delenv("MINER_AUTH", raising=False)
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    tenant_auth.clear_caches()
    yield
    tenant_auth.clear_caches()


def _get(token, tenant="acme"):
    return TestClient(server.app).get(f"/patterns?tenant_id={tenant}&min_cases=3", headers={"Authorization": f"Bearer {token}"})


def test_service_role_key_reads_the_requested_tenant(auth_on, fetched):
    res = _get(_token(role="service_role", iss="supabase"))
    assert res.status_code == 200, res.text
    assert fetched == ["acme"]


def test_service_role_still_needs_tenant(auth_on, fetched):
    res = TestClient(server.app).get("/patterns", headers={"Authorization": f"Bearer {_token(role='service_role')}"})
    assert res.status_code == 400
    assert fetched == []


def test_service_role_signed_with_another_key_is_rejected(auth_on, fetched):
    import jwt

    forged = jwt.encode({"role": "service_role"}, "another-secret-another-secret-another!!", algorithm="HS256")
    assert _get(forged).status_code == 401
    assert fetched == []


def test_anon_key_does_not_pass_as_server(auth_on, fetched):
    assert _get(_token(role="anon", iss="supabase")).status_code == 401
    assert fetched == []


def test_user_token_still_sees_only_its_tenant(auth_on, fetched):
    user = _token(role="authenticated", sub="u-1", tenant_id="acme")
    assert _get(user, "other").status_code == 403
    assert fetched == []
    assert _get(user, "acme").status_code == 200
    assert fetched == ["acme"]
