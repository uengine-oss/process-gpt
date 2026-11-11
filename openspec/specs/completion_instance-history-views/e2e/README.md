# 프로세스 인스턴스의 칸반 · 산출물 · 액티비티 — 시험

## 실행

```bash
# process-gpt-vue3 fix/rev1111 작업 트리. VM(튜토리얼 설치본)에 붙은 개발 서버로(배포 없이):
~/.claude/skills/screen-review-ship/scripts/devserver/start.sh $PWD 5297 5299
BASE_URL=http://127.0.0.1:5297 UX_BASE_URL=http://127.0.0.1:5297 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/rev1111-c
# 휴대폰 손가락 누르기(F-RV-D*): 같은 환경에서 playwright/e2e/rev1112 — 안드로이드 가로(882×411, 배율 2.625) · PC 화면(폭 1280) · 손가락
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
| F-RV-D01 손가락 누르기(흔들림 1~2px · 4~6px) | `F-RV-D01` ×2 | ✅ 2026-11-12 (고치기 전 VM 빌드 실패 — 클릭 이벤트가 오지 않음) |
| F-RV-D02 길게 눌러 끌기 | `F-RV-D02` | ✅ (고치기 전에도 통과 — 끌기가 그대로인지 지킨다) |
| F-RV-D03 녹화와 같은 조건 | `F-RV-D03` | ✅ (고치기 전 실패) |
| F-RV-D04 PC 마우스 | `F-RV-D04` | ✅ |

## 증거

`results/`(.gitignore): `devserver-rev1111-c.txt`(개발 서버) · `vm-rev1111-c.txt`(VM 반영 뒤) · 고치기 전/후 사진(`before-*` · `after-*`).
단위 시험은 합친 브랜치에서 1164 중 1149 통과, 실패 15 는 origin/main 과 같은 것(Node 25 localStorage · ChatRoomPage.serverContent).

2026-11-12 휴대폰 녹화(F-RV-D*): 개발 서버 · VM 반영 뒤 모두 5개 통과, 고치기 전 VM 빌드는 D01 ×2 · D03 실패. 단위 시험 1259 중 1244 통과(실패 15 는 origin/main 과 같은 것). 사진 `before-d01-*` · `after-d01-*` · `vm-d01-*`.
