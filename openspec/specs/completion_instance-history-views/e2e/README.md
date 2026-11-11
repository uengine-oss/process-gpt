# 프로세스 인스턴스의 칸반 · 산출물 · 액티비티 — 시험

## 실행

```bash
# process-gpt-vue3 fix/rev1111 작업 트리. VM(튜토리얼 설치본)에 붙은 개발 서버로(배포 없이):
~/.claude/skills/screen-review-ship/scripts/devserver/start.sh $PWD 5297 5299
BASE_URL=http://127.0.0.1:5297 UX_BASE_URL=http://127.0.0.1:5297 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/rev1111-c
# VM 에 반영한 뒤에는 UX_BASE_URL=http://localhost:8088 로 같은 시험
npm run test:unit
```

VM 의 실제 인스턴스(검토 → 반려 → 재작성 고리를 두 번 돈 「영업 제안서 승인 한빛물산 대전 사무실 가구」)를 읽기만 한다. 바뀌면 `RV_LOOP_INST` · `RV_LOOP_TASK` 로 다른 인스턴스를 준다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-11) |
|---|---|---|
| F-RV-C01 칸반 | `F-RV-C01`(밝게 · 어둡게) · 단위 `kanbanTone` | ✅ (고치기 전 실패) |
| F-RV-C02 산출물 · 빈 상태 | `F-RV-C02`(밝게 · 어둡게) · 단위 `workItemOutput` | ✅ (고치기 전 실패) |
| F-RV-C03 회차 · 되돌아감 · 진행 중 | `F-RV-C03`(밝게 · 어둡게) · 단위 `activityHistory` 8 | ✅ (고치기 전 실패) |
| F-RV-C03b 휴대폰 폭 | `F-RV-C03b` | ✅ |

## 증거

`results/`(.gitignore): `devserver-rev1111-c.txt`(개발 서버) · `vm-rev1111-c.txt`(VM 반영 뒤) · 고치기 전/후 사진(`before-*` · `after-*`).
단위 시험은 합친 브랜치에서 1164 중 1149 통과, 실패 15 는 origin/main 과 같은 것(Node 25 localStorage · ChatRoomPage.serverContent).
