# completion_workitem-delegation — E2E

## 실행 환경
- 인프라와 백엔드: Process GPT 공식 설치본(process-gpt-infra-docker)을 올린 VM. Supabase는 `localhost:54321`, 게이트웨이는 `:8088`이다.
- 프런트엔드: process-gpt-vue3 `fix/ux-review-1109`(PR #240) 작업 트리를 `vite`로 직접 띄운다(`127.0.0.1:5291`).
  - API 경로는 모두 VM 게이트웨이로 프록시한다.
  - 브라우저는 `--host-resolver-rules="MAP localhost <VM IP>"`로 Supabase 주소를 VM으로 돌린다.
- 계정: 관리자 장진영, 담당자 김민지, 다른 참여자 박서연(관리자 아님).
  - 시험 업무는 담당자가 김민지이고 시작자가 장진영인 TODO 업무다.
- **업무 행(todolist)에 쓰는 요청은 Playwright가 모두 가로채 내용만 확인하므로 데이터는 바뀌지 않는다.**

## 실행 명령
```bash
# process-gpt-vue3 작업 트리에서
UX_BASE_URL=http://127.0.0.1:5291 BASE_URL=http://127.0.0.1:5291 \
UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json \
UX_TASK_ID=<담당자=김민지, 시작자≠박서연 인 업무 id> \
npx playwright test playwright/e2e/ux-review --reporter=list

# 판단 규칙 단위 시험 (DB 없음)
node --test src/utils/workItemAccess.test.js src/utils/agentDelegation.test.js
```

## 스펙 시나리오 ↔ 시험
| 시나리오 | 시험 | 결과 |
|---|---|---|
| 담당자가 자기 업무를 연다 | F-UX-07 (위임 수단 1개) · 단위 「담당자 본인 · 시작자 · 관리자만」 | ✅ |
| 관리자가 남의 업무를 연다 | F-UX-08 | ✅ |
| 시작자가 남에게 넘어간 업무를 연다 | 단위 「담당자 본인 · 시작자 · 관리자만」, 「담당자가 비어 있는 업무」 | ✅ (단위, 화면 시험은 비관리자 시작자 데이터가 없어 ◐) |
| 다른 참여자가 남의 업무를 연다 | F-UX-06 (쓰기 요청 0건) | ✅ |
| 끝난 업무 | 단위 「끝난 업무는 아무도 넘길 수 없다」 | ✅ (단위) |
| 다른 참여자가 에이전트 탭을 연다 | F-UX-06 | ✅ |
| 관리자도 남의 업무를 에이전트에게 맡기지 못한다 | F-UX-08 | ✅ |
| 에이전트가 일한 기록은 누구나 본다 | 화면 확인(`shots/03-admin-agent-tab-readonly.png`: 실패한 진행 기록이 보이고 채택 단추 없음) | ◐ 수동 |
| 정해 둔 방식이 없는 업무를 처음 맡긴다 | F-UX-07 (요청 본문 `IN_PROGRESS`·`DRAFT`·`deepagents`, `user_id` 그대로) | ✅ |
| 업무에 정해 둔 방식이 있다 | 단위 「업무에 정해 둔 방식이 있으면 그대로」 | ✅ (단위) |
| 지난번에 고른 방식을 기억한다 | 단위 「지난번 고른 방식」 | ✅ (단위) |
| 방식을 바꾸고 싶을 때 | 수동 확인 | ◐ |

## 남은 공백
- **서버 강제 없음 ✗**: todolist의 UPDATE 정책이 `tenant_id = tenant_id()`뿐이다. 그래서 같은 조직 사람이면 API로 남의 업무를 바꿀 수 있다. 막는 정책은 `openspec/changes/ux-review-1109/design.md`에 제안했고 아직 적용하지 않았다.

## 증거
- `results/ux-review-playwright.txt`: 회귀 묶음 12/12 통과(이 스펙과 함께 고친 첫 화면 · 사이드바 · 조직도 · 목록 시험 포함)
- `results/unit-workitem-access.txt`: 단위 11/11
- `shots/01-other-participant-readonly.png`: 박서연이 남의 업무를 연 화면. 위임 수단이 없고 에이전트 탭에 안내가 보인다
- `shots/02-assignee-one-click.png`: 김민지가 한 번 눌러 맡긴 직후. 「대기열에 등록되었습니다」가 보인다
- `shots/03-admin-agent-tab-readonly.png`: 관리자가 남의 업무 에이전트 탭을 연 화면. 기록만 보이고 선택 · 채택 단추가 없다
