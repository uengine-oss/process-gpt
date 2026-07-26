from __future__ import annotations

import http.server
import subprocess
import threading
import time
from functools import partial
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
PORT = 9331
OUT = REPO / "docs/demo/deepagents-deterministic-replay-undo-demo.mp4"
SCRIPT = [
    ("d0", "DeepAgents에서도 검증된 업무 경로를 LLM 없이 재실행하고, 재작업은 안전하게 되돌립니다.", 4),
    ("d1", "실행 시작 전에 CrewAI와 같은 저장 코드를 조회합니다. 코드가 없을 때만 DeepAgents가 추론합니다.", 6),
    ("d2", "Replay는 새 업무 값만 추출해 검증된 MCP 호출 순서를 그대로 실행합니다. LLM 호출은 0회입니다.", 7),
    ("d3", "재작업은 이전 쓰기 이벤트로 Undo를 먼저 실행하고, 새 입력으로 순방향 코드를 이어서 실행합니다.", 7),
    ("d4", "운영 화면에는 결정론적 실행과 Undo 후 재실행이 별도 결과 카드로 명확히 표시됩니다.", 6),
    ("d5", "DeepAgents Deterministic Replay & Undo — 구현과 자동 테스트를 완료했습니다.", 4),
]


def main() -> None:
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", PORT),
        partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE)),
    )
    threading.Thread(target=server.serve_forever, daemon=True).start()
    video_dir = HERE / "video"
    video_dir.mkdir(exist_ok=True)
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            ctx = browser.new_context(
                viewport={"width": 1280, "height": 720},
                record_video_dir=str(video_dir),
                record_video_size={"width": 1280, "height": 720},
            )
            page = ctx.new_page()
            page.goto(f"http://127.0.0.1:{PORT}/demo.html")
            page.wait_for_load_state("networkidle")
            assert "deterministic-undo" in page.locator("#d4").inner_text()
            assert "3 tests passed" in page.locator("#d5").inner_text()
            for section, caption, dwell in SCRIPT:
                page.evaluate(
                    "([id,text])=>{caption.innerText=text;document.getElementById(id).scrollIntoView({behavior:'smooth'})}",
                    [section, caption],
                )
                time.sleep(dwell)
            video = page.video
            ctx.close()
            webm = video.path()
            browser.close()
        OUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(webm), "-an", "-c:v", "libx264",
             "-pix_fmt", "yuv420p", "-crf", "22", "-movflags", "+faststart", str(OUT)],
            check=True,
        )
        print(f"video: {OUT} ({OUT.stat().st_size / 1_000_000:.1f} MB)")
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
