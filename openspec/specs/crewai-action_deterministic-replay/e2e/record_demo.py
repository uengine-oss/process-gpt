#!/usr/bin/env python
"""Playwright 데모 — 검증(assertions) + 무음 데모 영상 녹화.

전제: run_e2e.py 가 19/19 PASS 로 끝나 demo_data.json 이 존재.
동작:
  1) demo.html 을 로컬 http 서버(:9321)로 서빙
  2) Playwright(Chromium)로 열어 핵심 사실을 assert (Playwright 테스트)
  3) 섹션별 자막(음성 대체)을 바꿔가며 스크롤 — recordVideo 로 .webm 녹화
  4) ffmpeg 로 무음 .mp4 변환 → docs/demo/deterministic-replay-demo.mp4
산출: video/*.webm, screenshots/*.png, ../../../../docs/demo/deterministic-replay-demo.mp4
"""
from __future__ import annotations

import http.server
import os
import subprocess
import sys
import threading
import time
from functools import partial
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
PORT = 9321
URL = f"http://127.0.0.1:{PORT}/demo.html"
OUT_MP4 = REPO / "docs" / "demo" / "deterministic-replay-demo.mp4"

# (섹션 id, 대사 자막, 머무는 시간 s)
SCRIPT = [
    ("s0", "Process GPT의 <b>실행 경로 고착화</b> — 한 번 성공한 AI 실행을 코드로 기억해, "
           "이후에는 LLM 없이 정확하게 재실행합니다.", 5.5),
    ("s1", "LLM 재량 실행은 매번 달라질 수 있습니다. Process GPT는 <b>검증된 실행 경로를 "
           "고착화</b>해 이 리스크를 없앱니다.", 7.5),
    ("s2", "먼저 테넌트에 <b>Supabase MCP 서버</b>를 등록합니다. 에이전트는 execute_sql "
           "도구로 DB를 읽고 씁니다.", 7.5),
    ("s3", "1차 실행 — LLM 에이전트가 SELECT로 재고를 확인하고 UPDATE와 INSERT를 "
           "실행합니다. <b>모든 도구 호출이 이벤트로 기록</b>됩니다.", 9.5),
    ("s4", "고착화 — 기록된 이력이 <b>파라미터화된 Python 코드</b>로 변환되어 "
           "프로세스·활동 단위로 저장됩니다.", 9.5),
    ("s5", "재실행 — 새 지시(Galaxy, 250)에서 <b>값만 추출</b>해 고착화된 코드를 그대로 "
           "실행합니다. LLM 추론은 <b>0회</b>입니다.", 9.5),
    ("s6", "두 실행 모두 실제 DB에 반영되었습니다. 1차는 LLM이, 2차는 고착화된 코드가 — "
           "<b>결과는 동일한 품질</b>로.", 8.5),
    ("s7", "정확성 · 비용 · 감사 가능성 · 프로그래밍 없는 자동화 — 기업 업무에 필요한 "
           "<b>확신할 수 있는 AI 실행</b>이 됩니다.", 10.0),
    ("s8", "한 번 배운 업무는, 매번 정확하게 — Process GPT Deterministic Replay.", 5.5),
]


def serve() -> http.server.ThreadingHTTPServer:
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def run_assertions(page) -> None:
    """Playwright 테스트 — demo_data.json(=실측 결과)이 페이지에 반영됐는지 검증."""
    checks = [
        ("execute_sql 도구 노출", "#mcp-tools", "execute_sql"),
        ("Supabase MCP 설정 표시", "#mcp-config", "postgres-mcp"),
        ("1차 실행 UPDATE 기록", "#tool-log", "UPDATE"),
        ("1차 실행 INSERT 기록", "#tool-log", "INSERT"),
        ("고착화 코드 파라미터 템플릿", "#gen-code", "${product_name}"),
        ("고착화 코드 call_tool 경로", "#gen-code", "call_tool"),
        ("파라미터 명세", "#gen-params", "stock_quantity"),
        ("재실행 3스텝", "#replay-results", "step 3"),
        ("inventory Galaxy=250 반영", "#tbl-inv", "250"),
        ("감사 로그 Galaxy", "#tbl-log", "Galaxy"),
        ("E2E 21/21 표기", "#s6", "21/21"),
    ]
    failed = []
    for name, sel, needle in checks:
        content = page.locator(sel).inner_text()
        ok = needle in content
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
        if not ok:
            failed.append(name)
    if failed:
        raise SystemExit(f"Playwright 검증 실패: {failed}")


def main() -> None:
    if not (HERE / "demo_data.json").exists():
        raise SystemExit("demo_data.json 없음 — run_e2e.py 먼저 실행")
    (HERE / "screenshots").mkdir(exist_ok=True)
    httpd = serve()
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            ctx = browser.new_context(
                viewport={"width": 1280, "height": 720},
                record_video_dir=str(HERE / "video"),
                record_video_size={"width": 1280, "height": 720},
            )
            page = ctx.new_page()
            page.goto(URL)
            page.wait_for_load_state("networkidle")
            page.wait_for_selector("#tbl-inv tr")

            print("== Playwright 검증 ==")
            run_assertions(page)

            print("\n== 녹화 시작 ==")
            for sec, caption, dwell in SCRIPT:
                page.evaluate(
                    "([sec, cap]) => {"
                    "  document.getElementById('caption').innerHTML = cap;"
                    "  document.getElementById(sec).scrollIntoView({behavior:'smooth'});"
                    "}", [sec, caption])
                time.sleep(dwell)
                page.screenshot(path=str(HERE / "screenshots" / f"{sec}.png"))
            video = page.video
            ctx.close()
            webm = video.path()
            browser.close()

        OUT_MP4.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(webm), "-an", "-c:v", "libx264",
             "-pix_fmt", "yuv420p", "-crf", "22", "-movflags", "+faststart",
             str(OUT_MP4)],
            check=True, capture_output=True)
        size = OUT_MP4.stat().st_size / 1e6
        print(f"\n영상 저장: {OUT_MP4} ({size:.1f} MB, 무음)")
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main()
