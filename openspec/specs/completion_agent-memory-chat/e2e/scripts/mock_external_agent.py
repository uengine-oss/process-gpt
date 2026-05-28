"""Deterministic external A2A agent stub for the fetch-data E2E scenario."""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DESCRIPTOR = {
    "name": "e2e-mock-agent",
    "description": "E2E mock external agent",
    "url": "http://mock-external-agent:8090",
    "version": "0.0.1",
    "capabilities": {"streaming": False},
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        return

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        if self.path == "/.well-known/agent.json":
            self._send_json(200, DESCRIPTOR)
            return
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        self._send_json(404, {"error": "not found", "path": self.path})


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", 8090), Handler)
    print("[mock-external-agent] listening on :8090", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
