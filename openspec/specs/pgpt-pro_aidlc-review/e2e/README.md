# E2E — pgpt-pro_aidlc-review

검토 보드·볼트 보드·산출물 보기(Lite 앱 규약의 앱 셋, v2 는 `pgpt-pro_mcp-apps`)를 실제 서버와 실제 DB에 대고 확인한다. 세션은 `pgpt-pro_aidlc-team` 과 같은 대역(tmux 안에서 Claude Code 선택 창 화면을 그리고 받은 키를 적는 스크립트)이라 모델 호출이 없다. 실제 Claude Code + AI-DLC 2.11.2 classic 한 판(「팀 회의실 예약」, 유닛 6개)은 영상 판(`pgpt-pro/demo/product/robo-dlc-review-ko`)에서 같은 흐름으로 돌렸고, 그 화면을 `results/real-*.png` 에 두었다. 결과 파일은 저장소 `.gitignore` 라 올라가지 않으며 사본이 `pgpt-pro/docs/robo-dlc/results/review/` 에 있다.

```bash
cd /Users/uengine/uengine-platform/process-gpt-lite-mcpapps/server            # feat/mcp-apps (v2 MCP Apps, 함께 고르기·의도 → 유닛 → 볼트)
node --test test/apps.test.js                                                  # 규약·화면 묶음·보드 판단(voteState)·볼트(unitBolts) (25)
PRO_E2E_API=http://127.0.0.1:8799/api node --test --test-concurrency=1 test/apps.e2e.test.js   # 실제 서버 10단계 (PRO_AIDLC_WATCH=1)
cd ../e2e && PGPT_URL=http://127.0.0.1:5198 API_URL=http://127.0.0.1:8799 npx playwright test tests/feature/robo-dlc.spec.js -g "F-RD-0[678]"
```

실행 환경: Supabase(Docker) + 기능 브랜치 BFF(`feat/robo-dlc`, `PRO_PORT=8798 PRO_BACKGROUND=0 PRO_AIDLC_WATCH=1`) + `vite preview --port 5197`. 앱 표(`app_review_*`)는 서버가 처음 뜰 때 `lite_migrations` 에 `app:review/001_review.sql` 로 적용된다.

## 스펙 시나리오 ↔ 시험

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| AI-DLC 폴더의 앱 단추 | E2E 준비(`/apps/for/:folder`), F-RD-06 | `results/e2e.txt`, `results/playwright.txt` |
| 고르기 전에는 가려진다 | E2E 「함께 고르기」, F-RD-06(두 브라우저: 고르기 전엔 「1명 골랐어요」), 단위 「함께 고르기…」(voteState), 실제 실행(비품 대여 · 유저 스토리 질문 4개) | `results/e2e.txt`, `results/playwright.txt`, `results/unit.txt`, `results/real-together-hidden.png` |
| 다르면 의견 갈림, 같으면 합의 | E2E 「함께 고르기」, F-RD-06(두 화면에 바로 「의견 갈림」), 실제 실행(Q1 A·B로 갈림, Q2~Q4 세 사람 합의) | `results/e2e.txt`, `results/playwright.txt`, `results/real-together-split.png` |
| 결정권자가 갈린 카드를 정한다 | E2E 「함께 고르기」(409 · 403 · 정함 · B·A·A), 실제 실행(PO가 개발자의 B로 정함) | `results/e2e.txt`, `results/real-together-settled.png` |
| 검토자마다 자기 카드 (역할별로) | E2E 2·3단계(보드를 「역할별로」로 바꾼 뒤) | `results/e2e.txt` |
| 이의는 이유와 함께 (역할별로) | E2E 3단계 | `results/e2e.txt` |
| 같이 보는 사람 | E2E 3단계, F-RD-06(두 브라우저), 실제 실행(요구사항 질문 8개, PO·개발자 동시) | `results/e2e.txt`, `results/playwright.txt`, `results/real-board.png`, `results/real-dispute.png` |
| 근거 붙인 의견 | E2E 3단계, 단위 「근거 찾기…」, 실제 실행(근거 → 원본 절) | `results/e2e.txt`, `results/real-original.png` |
| 논의가 남은 보내기 · 한 번에 보내기 | E2E 4단계 | `results/e2e.txt` |
| 위치가 원본 링크가 된다 | 단위 「검토 파일…」(실제 실행의 지적) | `results/unit.txt` |
| 고칠 것 하나와 받아들일 것 하나 | E2E 5단계(대역 세션이 받은 키 = `3` + 글), 단위 「지적들의 결정이…」, 실제 실행(유저 스토리 지적 5개 → Request Changes, AI-DLC 가 rejected 로 기록하고 고침) | `results/e2e.txt`, `results/real-preview.png`, `results/real-shell.png` |
| ADR 하나에 초점 | F-RD-07, 단위 「산출물 보기…」(ADR-004·앞 낱말), 실제 실행(US5.4 절 초점) | `results/playwright.txt`, `results/real-focus.png` |
| 기록 밖 | E2E 6단계, 단위 「문서…」 | `results/e2e.txt` |
| 되돌아온 유닛은 볼트가 여럿 | 단위 「unitBolts…」(실제 실행 u3 의 사건 순서), F-RD-08(유닛 → 볼트, 묶음 B1·B2), 실제 실행(회의실 예약: 유닛 6 · 볼트 11 · 되돌아옴 5) | `results/unit.txt`, `results/playwright.txt`, `results/real-bolts-tree.png` |
| 지금 도는 유닛 | 실제 classic 실행(비품 대여, 첫 유닛 코드 생성 중), F-RD-08(끝난 실행) | `results/playwright.txt` |
| 유닛이 아직 없다 | E2E 7단계 | `results/e2e.txt` |
| 코드 계획은 개발자에게 | 단위 「지금 유닛 단계…」(실제 실행의 사건 순서와 계획 파일 Context), 실제 classic 실행(u2 「Approve the code plan」 → 강다은) | `results/unit.txt`, `results/real-plan-page.png` |
