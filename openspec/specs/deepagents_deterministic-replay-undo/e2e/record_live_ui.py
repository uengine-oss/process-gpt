#!/usr/bin/env python
"""Record only the real Process GPT UI for DeepAgents replay and undo."""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
FRONT = "http://localhost:5199"
FIRST = "22222222-3333-4444-5555-666666660001"
REPLAY = "22222222-3333-4444-5555-666666660002"
UNDO = "22222222-3333-4444-5555-666666660003"
OUT_DIR = REPO / "demo-recordings/deepagents-deterministic-live-demo"
OUT_MP4 = REPO / "demo-recordings/deepagents-deterministic-live-demo.mp4"

CAP_JS = """(text) => {
  let el = document.getElementById('pg-live-demo-caption');
  if (!el) {
    el = document.createElement('div');
    el.id = 'pg-live-demo-caption';
    el.style.cssText =
      'position:fixed;left:24px;right:24px;bottom:18px;z-index:999999;' +
      'background:rgba(7,14,27,.94);color:#eef5ff;border:1px solid #35517a;' +
      'border-radius:12px;padding:16px 24px;font-size:20px;line-height:1.45;' +
      'box-shadow:0 8px 32px rgba(0,0,0,.35);font-family:"Apple SD Gothic Neo",sans-serif';
    document.body.appendChild(el);
  }
  el.innerHTML = text.replace(/<b>/g, '<b style="color:#55a7ff">');
}"""


def main() -> None:
    raw_dir = OUT_DIR / "raw"
    shots = OUT_DIR / "screenshots"
    raw_dir.mkdir(parents=True, exist_ok=True)
    shots.mkdir(parents=True, exist_ok=True)
    timings: list[dict] = []

    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(
            viewport={"width": 1440, "height": 900},
            record_video_dir=str(raw_dir),
            record_video_size={"width": 1440, "height": 900},
        )
        page = context.new_page()
        started = time.monotonic()

        def scene(number: int, caption: str, dwell: float = 7.0) -> None:
            timings.append({"scene": number, "start_sec": round(time.monotonic() - started, 2)})
            page.evaluate(CAP_JS, caption)
            page.screenshot(path=str(shots / f"scene-{number:02d}.png"))
            time.sleep(dwell)

        # 1. Real login page and interaction.
        page.goto(f"{FRONT}/auth/login", wait_until="load", timeout=30_000)
        page.wait_for_selector("input[type=text]", timeout=15_000)
        scene(1, "실제 Process GPT 로그인 화면입니다. 고정 데모 계정으로 로그인합니다.", 2.0)
        page.locator("input[type=text]").first.type("demo@localhost", delay=35)
        page.locator("input[type=password]").first.type("Demo1234!", delay=35)
        page.get_by_role("button", name="로그인").click()
        page.wait_for_timeout(4_000)

        # 2. Real worklist with DeepAgents records.
        page.goto(f"{FRONT}/todolist", wait_until="load", timeout=30_000)
        page.wait_for_timeout(5_000)
        body = page.locator("body").inner_text()
        if "DeepAgents 재고 반영" not in body:
            raise RuntimeError("실제 업무 목록에서 DeepAgents 데모 워크아이템을 찾지 못했습니다.")
        target = page.get_by_text("DeepAgents 재고 반영")
        if target.count():
            target.first.scroll_into_view_if_needed()
        scene(
            2,
            "실제 업무 목록에 <b>DeepAgents 재고 반영</b> 작업 3건이 있습니다. "
            "1차 LLM 실행, 결정론적 Replay, Undo 후 Replay입니다.",
            8.0,
        )

        def open_monitor(scene_no: int, todo_id: str, expected: str, caption: str) -> None:
            page.goto(f"{FRONT}/todolist/{todo_id}", wait_until="load", timeout=30_000)
            page.wait_for_timeout(5_000)
            tab = page.get_by_role("tab").filter(has_text="에이전트에 맡기기")
            if tab.count():
                tab.first.click()
                page.wait_for_timeout(3_000)
            text = page.locator("body").inner_text()
            if expected not in text:
                raise RuntimeError(f"실제 에이전트 모니터에서 카드 누락: {expected}")
            card = page.get_by_text(expected)
            if card.count():
                card.first.scroll_into_view_if_needed()
            scene(scene_no, caption, 9.0)

        # 3. First DeepAgents LLM run with tool events.
        open_monitor(
            3,
            FIRST,
            "DeepAgents 1차 LLM 실행",
            "1차 실행의 실제 에이전트 모니터입니다. <b>DeepAgents</b>가 선택한 "
            "execute_sql 도구 호출과 완료 이벤트가 기록돼 있습니다.",
        )

        # 4. Actual deterministic replay result emitted by the implemented code path.
        open_monitor(
            4,
            REPLAY,
            "DeepAgents 결정론적 코드 실행 결과",
            "같은 활동의 다음 실행입니다. <b>DeepAgents 결정론적 코드 실행 결과</b> 카드만 있고, "
            "LLM 도구 추론 이력은 없습니다. 실제 DB에는 Galaxy 재고 250이 반영됐습니다.",
        )

        # 5. Actual deterministic undo + forward replay.
        open_monitor(
            5,
            UNDO,
            "DeepAgents Undo 후 재실행 결과",
            "재작업 화면입니다. 저장된 Undo 코드가 이전 iPhone 변경을 되돌린 뒤 "
            "정정 입력으로 순방향 코드를 실행했습니다. 최종 재고는 60, LLM 호출은 0회입니다.",
        )

        # 6. Return to actual list as the closing shot.
        page.goto(f"{FRONT}/todolist", wait_until="load", timeout=30_000)
        page.wait_for_timeout(4_000)
        scene(
            6,
            "실제 Process GPT 화면에서 DeepAgents Replay와 Undo 결과를 확인했습니다. "
            "<b>검증된 경로는 코드로 반복하고, 재작업은 안전하게 되돌립니다.</b>",
            6.0,
        )

        video = page.video
        context.close()
        webm = Path(video.path())
        browser.close()

    raw_webm = raw_dir / "demo-raw.webm"
    if raw_webm.exists():
        raw_webm.unlink()
    webm.rename(raw_webm)
    (OUT_DIR / "scenes-timing.json").write_text(
        json.dumps(timings, ensure_ascii=False, indent=2)
    )
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(raw_webm), "-an", "-c:v", "libx264",
            "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart",
            str(OUT_MP4),
        ],
        check=True,
        capture_output=True,
    )
    print(json.dumps({
        "ok": True, "video": str(OUT_MP4),
        "duration_scenes": timings, "screenshots": len(list(shots.glob("*.png"))),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
