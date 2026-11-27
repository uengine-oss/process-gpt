"""/chat/stream as a proxy: what the agent receives, and what the client gets back."""
import json

import httpx
import pytest
from starlette.testclient import TestClient

import server
from router.route import RouteResult

SSE = b'event: metadata\ndata: {"conversation_id": "c1"}\n\ndata: {"type": "token", "content": "hi"}\n\n'


@pytest.fixture
def agent(monkeypatch):
    """The agent behind the router: records each request and answers with ``reply``."""
    seen = {"requests": [], "reply": lambda req: httpx.Response(200, content=SSE, headers={"content-type": "text/event-stream"})}

    def handler(req: httpx.Request):
        seen["requests"].append(req)
        return seen["reply"](req)

    real = httpx.AsyncClient
    monkeypatch.setattr(server.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    touched = []

    async def touch(*a, **kw):
        touched.append((a, kw))
    monkeypatch.setattr(server.store, "touch", touch)
    seen["touched"] = touched
    return seen


def body(**md):
    return {"message": "decorated prompt", "tenant_id": "t1", "user_uid": "u1", "conversation_id": "c0", "metadata": md}


def test_the_agent_gets_the_clients_headers(agent):
    r = TestClient(server.app).post("/chat/stream", json=body(), headers={
        "Authorization": "Bearer jwt", "X-Tenant-Id": "t1", "X-LLM-Key": "k", "X-LLM-Tags": "chat"})
    assert r.status_code == 200
    h = agent["requests"][0].headers
    assert (h["authorization"], h["x-tenant-id"], h["x-llm-key"], h["x-llm-tags"]) == ("Bearer jwt", "t1", "k", "chat")
    assert h["content-type"] == "application/json"
    assert json.loads(agent["requests"][0].content)["conversation_id"] == "c0"
    assert r.content == SSE


def test_a_refusal_keeps_its_status(agent):
    agent["reply"] = lambda req: httpx.Response(401, json={"detail": "invalid token"})
    r = TestClient(server.app).post("/chat/stream", json=body())
    assert r.status_code == 401
    assert r.json() == {"detail": "invalid token"}


def test_an_unreachable_agent_is_503(agent):
    def down(req):
        raise httpx.ConnectError("refused", request=req)
    agent["reply"] = down
    r = TestClient(server.app).post("/chat/stream", json=body())
    assert r.status_code == 503


def test_a_routed_message_says_where_it_went_first_and_is_recorded(agent, monkeypatch):
    async def fake_route(decider, **kw):
        assert kw["message"] == "what the user said"
        return RouteResult("c9", "continue", {"title": "출장 준비", "summary": "", "gist": "", "kind": "conversation"},
                           {"strategy": "fake", "choice": "c9", "confidence": 0.9})
    monkeypatch.setattr(server, "route", fake_route)
    r = TestClient(server.app).post("/chat/stream", json=body(auto_route=True, route_text="what the user said"))
    first = r.content.split(b"\n\n")[0].decode()
    assert first.startswith("event: metadata") and '"conversation_id": "c9"' in first
    assert r.content.endswith(SSE)
    assert json.loads(agent["requests"][0].content)["conversation_id"] == "c9"
    (args, kw), = agent["touched"]
    assert args[:3] == ("t1", "u1", "c9") and kw["title"] == "출장 준비" and "hi" in kw["summary"]


def test_an_unsure_message_that_stays_keeps_the_conversations_title(agent, monkeypatch):
    """A "stay" whose conversation was not among the candidates carries no context: the row keeps its own title, not the
    message's first line (Process GPT Lite 2026-11-27 — 「…로 해서 보내」 became the conversation's title)."""
    async def fake_route(decider, **kw):
        return RouteResult("c0", "stay", None, {"strategy": "fake", "choice": "__new__", "confidence": 0.4})

    async def title_of(tenant, user, conv):
        assert (tenant, user, conv) == ("t1", "u1", "c0")
        return "의자 견적 회신"
    monkeypatch.setattr(server, "route", fake_route)
    monkeypatch.setattr(server.store, "title_of", title_of)
    TestClient(server.app).post("/chat/stream", json=body(auto_route=True, route_text="900101으로 해서 보내"))
    (args, kw), = agent["touched"]
    assert args[:3] == ("t1", "u1", "c0") and kw["title"] == "의자 견적 회신"


def test_a_stay_in_a_conversation_with_no_row_yet_is_named_after_the_message(agent, monkeypatch):
    async def fake_route(decider, **kw):
        return RouteResult("c0", "stay", None, {"strategy": "fake", "choice": "__new__", "confidence": 0.4})

    async def title_of(*_a):
        return None
    monkeypatch.setattr(server, "route", fake_route)
    monkeypatch.setattr(server.store, "title_of", title_of)
    TestClient(server.app).post("/chat/stream", json=body(auto_route=True, route_text="처음 하는 말"))
    (_args, kw), = agent["touched"]
    assert kw["title"] == "처음 하는 말"
