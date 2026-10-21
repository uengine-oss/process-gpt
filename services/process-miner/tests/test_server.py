"""API 의 테넌트 격리와 DB 연결 회복.

테넌트 격리는 DB 없이 확인한다(fetch 를 가로챈다). 연결 회복은 실제 DB 가 있어야
의미가 있어서, 로컬 supabase(54322)에 닿지 않으면 건너뛴다.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

from app import db, server  # noqa: E402

ROWS = {
    "acme": [dict(id=1, tenant_id="acme", origin_room_id="r1", source="chat_handover", from_user_id="kim",
                  to_user_id="lee", activity_label="작성", next_activity_label="검토", occurred_at="2026-10-01")],
    "other": [dict(id=2, tenant_id="other", origin_room_id="r2", source="chat_handover", from_user_id="x",
                   to_user_id="y", activity_label="비밀 업무", next_activity_label="비밀 검토", occurred_at="2026-10-01")],
}


@pytest.fixture
def fetched(monkeypatch):
    calls = []

    def fake_fetch(tenant_id, limit=5000):
        calls.append(tenant_id)
        if not tenant_id:
            raise AssertionError("tenant 없이 조회했다")
        return ROWS.get(tenant_id, [])

    monkeypatch.setattr(db, "fetch_handover_events", fake_fetch)
    return calls


GET_PATHS = ["/threads", "/network", "/organization", "/eligibility?activity=검토", "/discovered"]


@pytest.mark.parametrize("path", GET_PATHS)
def test_without_token_is_rejected(monkeypatch, fetched, path):
    """기본(인증 사용)에서는 토큰 없이 부르면 아무 테넌트의 기록도 읽지 않는다."""
    monkeypatch.delenv("MINER_AUTH", raising=False)
    res = TestClient(server.app).get(path)
    assert res.status_code == 401
    assert fetched == []


@pytest.mark.parametrize("path", GET_PATHS)
def test_dev_mode_still_requires_tenant(monkeypatch, fetched, path):
    """인증을 끈 개발 모드에서도 tenant_id 가 없으면 전체 테넌트를 돌려주지 않는다."""
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).get(path)
    assert res.status_code == 400
    assert fetched == []


def test_mine_without_tenant_is_rejected(monkeypatch, fetched):
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).post("/mine", json={"dry_run": True})
    assert res.status_code == 400
    assert fetched == []


def test_dev_mode_returns_only_the_requested_tenant(monkeypatch, fetched):
    monkeypatch.setenv("MINER_AUTH", "off")
    body = TestClient(server.app).get("/threads?tenant_id=acme").json()
    assert fetched == ["acme"]
    assert "비밀" not in str(body)
    # 스레드 첫 단계는 시작한 사람이 한 일이다
    assert [s["activity"] for s in body["threads"][0]["steps"]] == ["작성", "검토"]


def test_token_for_another_tenant_is_forbidden(monkeypatch, fetched):
    """토큰의 테넌트와 다른 tenant_id 를 요청하면 403."""
    monkeypatch.delenv("MINER_AUTH", raising=False)
    from processgpt_agent_sdk import tenant_auth

    monkeypatch.setattr(tenant_auth, "verify_token", lambda token: {"sub": "u1", "app_metadata": {"tenant_id": "acme"}})
    client = TestClient(server.app)
    headers = {"Authorization": "Bearer t"}
    assert client.get("/threads?tenant_id=other", headers=headers).status_code == 403
    ok = client.get("/threads", headers=headers)
    assert ok.status_code == 200
    assert fetched == ["acme"]


def test_fetch_refuses_missing_tenant():
    with pytest.raises(ValueError):
        db.fetch_handover_events("")


def _db_available() -> bool:
    try:
        db.query("select 1 as ok")
        return True
    except Exception:  # noqa: BLE001
        db.close()
        return False


@pytest.mark.skipif(not _db_available(), reason="로컬 DB(54322)에 닿지 않음")
def test_failed_query_does_not_poison_the_next_request():
    """쿼리가 한 번 실패해도 같은 스레드의 다음 쿼리는 정상이고, 트랜잭션이 열린 채 남지 않는다."""
    import psycopg

    with pytest.raises(psycopg.Error):
        db.query("select * from public.__no_such_table__")
    assert db.query("select 1 as ok") == [{"ok": 1}]
    conn = db.connect()
    assert conn.info.transaction_status == psycopg.pq.TransactionStatus.IDLE


def test_mine_does_not_write_proposals(monkeypatch, fetched):
    """제안은 식별 화면이 버전 저장 → 병합 요청으로 만든다. 마이너가 쓰면 병합함에서 다룰 수 없는 모양이 된다."""
    monkeypatch.setenv("MINER_AUTH", "off")
    res = TestClient(server.app).post("/mine", json={"tenant_id": "acme", "dry_run": False})
    assert res.status_code == 410
    assert "새 프로세스로 제안" in res.json()["detail"]
