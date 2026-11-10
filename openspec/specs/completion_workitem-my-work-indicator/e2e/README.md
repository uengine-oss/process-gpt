# completion_workitem-my-work-indicator — E2E

## 실행 환경
- 백엔드: Process GPT 공식 설치본(process-gpt-infra-docker) VM. Supabase는 `localhost:54321`, 게이트웨이는 `:8088`이다.
- 프런트: process-gpt-vue3 main(#241 이후) 작업 트리를 `vite`로 띄운다(`127.0.0.1:5291`). API는 VM 게이트웨이로 보낸다.
- 칩 시험(F-UX-14)은 인스턴스 목록과 내 업무 조회 응답을 Playwright가 정해 준다. 설치본 데이터와 상관없이 세는 규칙만 본다.

## 실행 명령
```bash
# process-gpt-vue3 작업 트리에서
UX_BASE_URL=http://127.0.0.1:5291 BASE_URL=http://127.0.0.1:5291 \
UX_HOST_MAP="MAP localhost 192.168.64.3" UX_ACCOUNTS=~/.config/pgtut/local-accounts.json \
npx playwright test playwright/e2e/ux-review -g "F-UX-1[3-6]" --reporter=list

# 세는 규칙 단위 시험 (DB 없음)
node --test src/utils/instanceListDisplay.test.js
```

## 스펙 시나리오 ↔ 시험
| 시나리오 | 시험 | 결과 |
|---|---|---|
| 데스크톱 상단 줄 | F-UX-13 | ✅ |
| 주소로 연다 | F-UX-13 | ✅ |
| 내 차례인 업무가 있는 인스턴스 | F-UX-14 (「내 업무 2」) · 단위 「진행 중 · 제출 · 보류/반송만」 | ✅ |
| 남의 차례이거나 아직 차례가 아닌 인스턴스 | F-UX-14 (다른 인스턴스 칩 없음) · 단위 「예정 · 완료는 뺀다」 · 「이름이 겹치는 남의 업무」 | ✅ |
| 하위 인스턴스의 업무 | 단위 「최상위 인스턴스로 묶고」 | ✅ (단위) |
| 업무를 끝낸다 | 수동 확인(`todolist-updated` 뒤 다시 셈) | ◐ |
| 표시를 읽지 못한다 | 코드 검토(조회 실패 시 목록 그대로) | ◐ |

## 증거
- `results/ux-review-playwright.txt`: 회귀 13/13(F-UX-01~05 · 09~16, 2026-11-10)
- `results/unit-my-work-count.txt`: 단위 10/10
- `results/chip.png`: 「견적 승인 프로세스 · 한빛오피스」에 「내 업무 2」, 남의 차례인 「휴가 신청」에는 표시 없음
