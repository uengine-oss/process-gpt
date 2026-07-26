"""Playwright headed 녹화 — demo.html 을 스크롤하며 각 검증 섹션을 보여준다.

전제: strategy(:8014)/agent-feedback(:6789)/analytic(:8022) 서비스 실행 중,
      demo.html 이 :9321 에서 서빙 중, demo_ids.json 존재.
산출: video/ 에 .webm, screenshots/ 에 섹션별 PNG.
"""

import os
import time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "http://127.0.0.1:9321/demo.html"
SECTIONS = ["s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8"]


def main() -> None:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context(
            viewport={"width": 1280, "height": 860},
            record_video_dir=os.path.join(HERE, "video"),
            record_video_size={"width": 1280, "height": 860},
        )
        page = context.new_page()
        page.goto(URL)
        page.wait_for_selector("body[data-ready='1']", timeout=30000)
        time.sleep(2.5)  # 헤더 + ① 전략맵을 잠시 보여준다

        for sid in SECTIONS:
            page.locator(f"#{sid}").scroll_into_view_if_needed()
            time.sleep(0.4)
            page.locator(f"#{sid}").screenshot(
                path=os.path.join(HERE, "screenshots", f"{sid}.png")
            )
            time.sleep(2.6)  # 각 섹션을 읽을 시간

        page.evaluate("window.scrollTo({top: document.body.scrollHeight, behavior: 'smooth'})")
        time.sleep(2)
        video_path = page.video.path()
        context.close()
        browser.close()
        print("video:", video_path)


if __name__ == "__main__":
    main()
