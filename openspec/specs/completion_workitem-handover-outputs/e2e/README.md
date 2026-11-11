# 업무 화면의 전달받은 산출물과 해야 할 작업 — 시험

## 실행

```bash
# process-gpt-vue3 fix/rev1111 작업 트리. VM(튜토리얼 설치본)에 붙은 개발 서버로(배포 없이):
~/.claude/skills/screen-review-ship/scripts/devserver/start.sh $PWD 5297 5299
BASE_URL=http://127.0.0.1:5297 UX_BASE_URL=http://127.0.0.1:5297 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/rev1111-a
# VM 에 반영한 뒤에는 UX_BASE_URL=http://localhost:8088 로 같은 시험
npm run test:unit
```

시험 데이터: `playwright/e2e/rev1111-a/seed-vm.mjs` 가 운영과 같은 모양(자유 입력 + 이름 없는 `text-field-2` · `boolean-field-3`, 녹화의 글)을 `beforeAll` 에 만들고 `afterAll` 에 지운다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| F-RV-A01 이름 | `F-RV-A01` | ✅ 개발 서버 · VM |
| F-RV-A02 자유 입력 폼 | `F-RV-A02` · 단위 `formPresentation` | ✅ |
| F-RV-A03 목록 · 절 제목 · 정화 | `F-RV-A03` · 단위 `markdownText` 7 | ✅ (고치기 전: 목록 여백 0, 절 제목이 목록 안, `<img onerror>` 실행) |
| F-RV-A04 이름 없는 칸 | `F-RV-A04` · 단위 `formPresentation` | ✅ |
| F-RV-A05 접힌 줄 | `F-RV-A05` · 단위 `workItemOutput` | ✅ |

## 증거

`results/`(.gitignore): `devserver-rev1111-a.txt`(개발 서버) · `vm-rev1111-a.txt`(VM 반영 뒤) · 고치기 전/후 사진(`before-*` · `after-*`).
단위 시험은 합친 브랜치에서 1164 중 1149 통과, 실패 15 는 origin/main 과 같은 것(Node 25 localStorage · ChatRoomPage.serverContent).
