#!/usr/bin/env python
"""Playwright 검증 — undo demo.html이 실측 결과를 올바르게 렌더하는지 확인.

전제: run_e2e.py 가 19/19 PASS 로 끝나 demo_data.json 이 존재.
(내레이션 영상 제작은 demo-recordings/deterministic-undo-demo/ 쪽 스크립트가 담당)
"""
from __future__ import annotations

import http.server
import threading
from functools import partial
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
PORT = 9322
URL = f"http://127.0.0.1:{PORT}/demo.html"


def main() -> None:
    if not (HERE / "demo_data.json").exists():
        raise SystemExit("demo_data.json 없음 — run_e2e.py 먼저 실행")
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1280, "height": 720})
            page.goto(URL)
            page.wait_for_load_state("networkidle")
            page.wait_for_selector("#tbl-final tr")
            checks = [
                ("undo 코드 역연산 표시", "#undo-code", "reverse_sql"),
                ("이벤트 로그 UPDATE 표시", "#event-logs", "UPDATE"),
                ("undo 전 80 표시", "#tbl-undo", "80"),
                ("undo 후 20(원복) 표시", "#tbl-undo", "원복됨"),
                ("Galaxy 보존 표시", "#tbl-undo", "보존"),
                ("역연산 스텝 표시", "#undo-results", "undo 2"),
                ("redo 최종 iPhone=60", "#tbl-final", "60"),
                ("재작업 로그 표시", "#tbl-log", "재작업 반영"),
                ("19/19 표기", "#u4", "19/19"),
            ]
            failed = []
            for name, sel, needle in checks:
                ok = needle in page.locator(sel).inner_text()
                print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
                if not ok:
                    failed.append(name)
            browser.close()
            if failed:
                raise SystemExit(f"검증 실패: {failed}")
            print("== all PASS ==")
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main()
