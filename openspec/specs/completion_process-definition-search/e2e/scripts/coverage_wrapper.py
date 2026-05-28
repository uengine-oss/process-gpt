"""Coverage wrapper for source-run uvicorn on Windows.

Runs coverage.Coverage() around uvicorn so the spec-relevant `services/completion`
package gets line/branch coverage. Exposes a tiny HTTP control endpoint on
127.0.0.1:8001 (POST /save) so the suite can flush coverage data before
PowerShell `Stop-Process -Force` terminates the python interpreter
(`TerminateProcess` skips Python's atexit on Windows — see
openspec/e2e/memories/coverage-flush-windows-force-stop.md).

Usage (from the start_completion.ps1 helper):
    python openspec/specs/<spec-name>/e2e/scripts/coverage_wrapper.py
"""
from __future__ import annotations

import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import coverage

DATA_FILE = os.environ.get("COVERAGE_FILE", ".coverage")
COV = coverage.Coverage(
    data_file=DATA_FILE,
    source=["."],
    omit=[
        "tests/*",
        "semgrep-rules/*",
        "static/*",
        "*/site-packages/*",
        "*\\site-packages\\*",
    ],
    branch=True,
)
COV.start()


class _ControlHandler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        if self.path == "/save":
            try:
                COV.save()
                body = b"saved"
                code = 200
            except Exception as exc:  # pragma: no cover
                body = f"error: {exc}".encode("utf-8", "replace")
                code = 500
            self.send_response(code)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args, **kwargs):  # silence default logging
        return


def _serve_control() -> None:
    HTTPServer(("127.0.0.1", 8001), _ControlHandler).serve_forever()


threading.Thread(target=_serve_control, daemon=True).start()


def main() -> int:
    # Import after coverage has started so module-level lines are counted.
    import uvicorn

    sys.path.insert(0, os.getcwd())
    from main import app  # noqa: WPS433 (intentional late import for coverage)

    try:
        uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
    finally:
        try:
            COV.stop()
            COV.save()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
