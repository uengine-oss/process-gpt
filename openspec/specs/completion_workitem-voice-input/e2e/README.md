# 업무 폼 음성 입력 — 시험

## 실행

```bash
# process-gpt-vue3 fix/rev1111 작업 트리. VM(튜토리얼 설치본)에 붙은 개발 서버로(배포 없이):
~/.claude/skills/screen-review-ship/scripts/devserver/start.sh $PWD 5297 5299
BASE_URL=http://127.0.0.1:5297 UX_BASE_URL=http://127.0.0.1:5297 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/rev1111-b
# VM 에 반영한 뒤에는 UX_BASE_URL=http://localhost:8088 로 같은 시험
npm run test:unit
```

가짜 마이크: Chromium `--use-file-for-fake-audio-capture` 로 `say -v Yuna` 한국어 wav 를 재생한다(시험이 만든다). 업무 행 쓰기는 모두 막아 VM 데이터를 바꾸지 않는다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| F-RV-B01 한 칸 덧붙이기 | `F-RV-B01` · 단위 `dictation` | ✅ 실제 받아쓰기 |
| F-RV-B02 말한 칸만 | `F-RV-B02`(채우기 응답 흉내, 요청 내용은 실제) · `F-RV-B05`(실제 언어 모델, `RV_LIVE_LLM=1`) | ✅ |
| F-RV-B03 받아쓰기 장애 · 권한 거부 | `F-RV-B03` | ✅ |
| F-RV-B04 채우기 장애 | `F-RV-B04` | ✅ |

## 증거

`results/`(.gitignore): `devserver-rev1111-b.txt`(개발 서버) · `vm-rev1111-b.txt`(VM 반영 뒤) · 고치기 전/후 사진(`before-*` · `after-*`).
단위 시험은 합친 브랜치에서 1164 중 1149 통과, 실패 15 는 origin/main 과 같은 것(Node 25 localStorage · ChatRoomPage.serverContent).
