#!/usr/bin/env python3
"""Deterministic external A2A agent stub for the
completion_agent-memory-chat E2E suite.

Replaces a real third-party agent so that the descriptor lookup route
`GET /multi-agent/fetch-data` has a stable target. The completion service
fetches `<agent_url>/.well-known/agent.json` from this server.

Endpoints (stdlib only, no pip install needed):
  GET /health                  -> readiness probe
  GET /.well-known/agent.json  -> A2A agent descriptor card
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8090

AGENT_CARD = {
    "name": "E2E External Agent",
    "description": "completion_agent-memory-chat E2E 원격 에이전트 디스크립터 스텁",
    "url": f"http://mock-external-agent:{PORT}",
    "version": "1.0.0",
    "capabilities": {"streaming": False, "pushNotifications": False},
    "defaultInputModes": ["text"],
    "defaultOutputModes": ["text"],
    "skills": [
        {
            "id": "e2e-echo",
            "name": "E2E Echo Skill",
            "description": "테스트용 에코 스킬",
        }
    ],
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[mock-external-agent]", fmt % args, flush=True)

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path in ("/health", "/healthz", ""):
            self._send_json({"status": "ok"})
            return
        if path == "/.well-known/agent.json":
            self._send_json(AGENT_CARD)
            return
        self._send_json({"error": "not found"}, status=404)


if __name__ == "__main__":
    print(f"[mock-external-agent] listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
