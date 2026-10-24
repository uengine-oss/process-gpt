"""context-router: decides which conversation a chat message belongs to, in front of the agents.

  POST /decide       generic typed decision (judge → logprob → json), for any service
  POST /route        which conversation a message belongs to (no forwarding)
  POST /chat/stream  route, then forward the chat request to the agent and stream its answer
                     back unchanged, after one leading ``metadata`` event carrying the routing
  GET  /router/health
  *    anything else   passed through to the default agent unchanged

The agents themselves are untouched: they receive an ordinary chat request whose
``conversation_id`` the router chose.
"""
from __future__ import annotations

import json
import logging
import os

import httpx
import uvicorn
from dotenv import load_dotenv
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("context-router")

from decide import Option, from_env  # noqa: E402
from router import route  # noqa: E402
from router import store  # noqa: E402
from router.select import gist_of  # noqa: E402

decider = from_env()
THRESHOLD = float(os.getenv("ROUTER_THRESHOLD", "0.55"))
#: agent type → its chat endpoint; a request may name one in metadata.agent
TARGETS = json.loads(os.getenv("ROUTER_TARGETS") or json.dumps({
    "deepagents": "http://localhost:8888/chat/stream",
    "cliagents": "http://localhost:8890/chat/stream",
}))
DEFAULT_TARGET = os.getenv("ROUTER_DEFAULT_TARGET", "deepagents")
#: Routing is opt-in per request (metadata.auto_route): a client whose rooms are already fixed
#: conversations (process-gpt chat rooms) must not have them switched underneath it.
AUTO_ROUTE_DEFAULT = os.getenv("ROUTER_AUTO_ROUTE_DEFAULT", "false").lower() == "true"


async def decide_ep(request: Request):
    b = await request.json()
    opts = [Option(str(o["key"]), str(o.get("label", o["key"])), str(o.get("hint", ""))) for o in b.get("options", [])]
    d = await decider.decide(b.get("state", ""), b.get("question", ""), opts)
    return JSONResponse(d.as_dict())


async def route_ep(request: Request):
    b = await request.json()
    md = b.get("metadata") or {}
    r = await route(decider, message=b.get("message", ""), tenant_id=b.get("tenant_id", ""), user_id=b.get("user_uid") or b.get("user_id", ""),
                    current=b.get("conversation_id"), client_contexts=md.get("contexts"), threshold=THRESHOLD)
    return JSONResponse(r.as_dict())


async def chat_ep(request: Request):
    b = await request.json()
    md = dict(b.get("metadata") or {})
    tenant, user = b.get("tenant_id", ""), b.get("user_uid") or b.get("user_id", "")
    # the client may decorate the agent prompt; route on what the user actually said
    message = md.get("route_text") or b.get("message") or b.get("text") or ""
    routing = None
    if md.get("auto_route", AUTO_ROUTE_DEFAULT) and message:
        r = await route(decider, message=message, tenant_id=tenant, user_id=user, current=b.get("conversation_id"),
                        client_contexts=md.get("contexts"), threshold=THRESHOLD)
        b["conversation_id"] = r.conversation_id
        routing = r.as_dict()
        logger.info("routed → %s (%s, %s %.2f)", r.conversation_id[:12], r.action, r.decision.get("strategy"), r.decision.get("confidence", 0))
    target = TARGETS.get(md.get("agent") or DEFAULT_TARGET, TARGETS[DEFAULT_TARGET])
    headers = {"Content-Type": "application/json"}
    if request.headers.get("authorization"):
        headers["Authorization"] = request.headers["authorization"]

    async def stream():
        if routing:
            yield f"event: metadata\ndata: {json.dumps({'conversation_id': b['conversation_id'], 'routing': routing}, ensure_ascii=False)}\n\n".encode()
        answer, buf = "", ""
        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("POST", target, headers=headers, json=b) as up:
                async for chunk in up.aiter_bytes():
                    yield chunk
                    buf += chunk.decode("utf-8", "ignore")
                    *lines, buf = buf.split("\n")
                    for line in lines:
                        if line.startswith("data:"):
                            try:
                                j = json.loads(line[5:])
                            except Exception:  # noqa: BLE001
                                continue
                            if j.get("type") in ("token", "text") and j.get("content"):
                                answer += j["content"]
                            elif j.get("type") == "done" and j.get("content"):
                                answer = j["content"]
        if routing and tenant and user:
            prev = routing.get("context") or {}
            title = prev.get("title") or message.strip().splitlines()[0][:60]
            summary = f"최근 요청: {message.strip()[:200]}\n최근 답: {answer.strip()[:300]}"
            # the request being replaced survives as keywords in the gist
            gist = gist_of(prev.get("gist") or "", prev.get("summary") or "")
            await store.touch(tenant, user, b["conversation_id"], title=title, summary=summary, gist=gist, kind=prev.get("kind") or "conversation")

    return StreamingResponse(stream(), media_type="text/event-stream")


async def passthrough(request: Request):
    """Everything else goes to the default agent unchanged, so the gateway can point the agent's
    route at the router (attach, skills, files... keep working)."""
    base = TARGETS[DEFAULT_TARGET].rsplit("/chat/stream", 1)[0]
    url = f"{base}/{request.path_params['path']}"
    if request.url.query:
        url += f"?{request.url.query}"
    headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}
    body = await request.body()
    client = httpx.AsyncClient(timeout=None)
    up = await client.send(client.build_request(request.method, url, headers=headers, content=body), stream=True)

    async def relay():
        try:
            async for chunk in up.aiter_raw():
                yield chunk
        finally:
            await up.aclose()
            await client.aclose()
    keep = {k: v for k, v in up.headers.items() if k.lower() not in ("content-length", "transfer-encoding", "content-encoding", "connection")}
    return StreamingResponse(relay(), status_code=up.status_code, headers=keep)


async def health(_):
    return JSONResponse({"status": "ok", "strategies": [s.name for s in decider.strategies], "targets": list(TARGETS)})


app = Starlette(routes=[
    Route("/decide", decide_ep, methods=["POST"]),
    Route("/route", route_ep, methods=["POST"]),
    Route("/chat/stream", chat_ep, methods=["POST"]),
    Route("/router/health", health),
    Route("/{path:path}", passthrough, methods=["GET", "POST", "PUT", "PATCH", "DELETE"]),
])

if __name__ == "__main__":
    uvicorn.run(app, host=os.getenv("HOST", "0.0.0.0"), port=int(os.getenv("PORT", "8895")))
