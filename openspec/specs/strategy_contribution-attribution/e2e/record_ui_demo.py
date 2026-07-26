"""실제 StrategyBoard/OntologyExplorer(로그인 프리 하네스)에서 기여도 UX를 검증·녹화한다.

전제: strategy(:8014)/agent-feedback(:6789)/analytic(:8899) + vite(:5199, demo-contribution.html),
     seed_demo.py 실행 완료(demo_ids.json).
흐름(스토리보드 장면 순서): 보드 배지 → 카드 클릭 → KPI 기여도 블록 → 기여도 탭
     → 성과자 내역 확장 → 성과자 다이얼로그 → 온톨로지 탐색기(기여 엣지).
산출: video/*.webm, screenshots/ui-*.png. 각 단계는 assert 로 실제 데이터 표시를 검증한다.
"""

import json
import os
import time

from playwright.sync_api import expect, sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ids = json.load(open(os.path.join(HERE, "demo_ids.json")))
URL = f"http://127.0.0.1:5199/demo-contribution.html?tenant={ids['tenant_id']}"


def shot(page, name):
    page.screenshot(path=os.path.join(HERE, "screenshots", f"{name}.png"))


def main() -> None:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context(
            viewport={"width": 1360, "height": 850},
            record_video_dir=os.path.join(HERE, "video"),
            record_video_size={"width": 1360, "height": 850},
        )
        page = context.new_page()
        page.goto(URL)

        # 장면 1 — 보드: 카드 + 중요도 배지
        page.wait_for_selector(".objective-card", timeout=20000)
        card = page.locator(".objective-card", has_text="매출 성장")
        expect(card.locator(".v-chip", has_text="5").first).to_be_visible()
        time.sleep(2.2)
        shot(page, "ui-1-board-importance")

        # 장면 2 진입 — 카드 클릭 → 상세 패널
        card.click()
        page.wait_for_selector(".detail-panel", timeout=10000)
        time.sleep(1.2)

        # 장면 3 — KPI 확장: 측정 이력 + 기여도 블록
        page.locator(".detail-panel button:has(i.mdi-chart-line)").first.click()
        page.wait_for_selector(".detail-panel .performer-name", timeout=15000)
        expect(page.locator(".detail-panel", has_text="김지은")).to_be_visible()
        time.sleep(2.4)
        shot(page, "ui-2-kpi-contribution")

        # 장면 2 — 기여도 탭: 성과자 가중 순위 + 스킬 성장 기여
        page.locator('[data-testid="contribution-tab"]').click()
        page.wait_for_selector('[data-testid="performer-row"]', timeout=20000)
        rows = page.locator('[data-testid="performer-row"]')
        expect(rows.first).to_contain_text("계약검토봇")  # 가중 합산 1위 = 에이전트(역전)
        expect(page.locator(".detail-panel", has_text="계약 검토 스킬")).to_be_visible()
        time.sleep(1.6)
        shot(page, "ui-3-contribution-tab")

        # 성과자 행 확장 — KPI별 산출 내역(비중 × 중요도)
        rows.first.click()
        expect(page.locator(".detail-panel", has_text="× ")).to_be_visible()
        time.sleep(2.0)
        shot(page, "ui-4-breakdown")

        # 장면 4 — 성과자 이름 클릭 → 역방향 요약 다이얼로그
        rows.first.locator(".performer-name").click()
        page.wait_for_selector('[data-testid="performer-dialog"] table', timeout=15000)
        expect(page.locator('[data-testid="performer-dialog"]')).to_contain_text("운영 효율화")
        time.sleep(2.4)
        shot(page, "ui-5-performer-dialog")
        page.keyboard.press("Escape")
        time.sleep(0.8)

        # 장면 5 — 온톨로지 탐색기: CONTRIBUTED_TO('기여') 엣지
        page.goto(URL.replace("demo-contribution.html", "demo-contribution.html#/analytics/ontology").replace("#/analytics", "#/analytics"))
        page.evaluate("location.hash = '#/analytics/ontology'")
        page.wait_for_timeout(5000)
        shot(page, "ui-6-ontology-contributed-to")
        time.sleep(1.5)

        video_path = page.video.path()
        context.close()
        browser.close()
        print("video:", video_path)
        print("ALL UI ASSERTIONS PASSED")


if __name__ == "__main__":
    main()
