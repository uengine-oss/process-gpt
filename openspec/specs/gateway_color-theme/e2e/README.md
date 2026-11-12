# 색상 테마 — 시험

화면 시험은 process-gpt-vue3의 `playwright/e2e/rev1112b/`에 있다. 대비는 `contrast.ts`가 화면의 각 글자색과 가장 가까운 불투명 바탕색을 기준으로 계산한다.

```bash
BASE_URL=http://localhost:8088 UX_BASE_URL=http://localhost:8088 UX_HOST_MAP="MAP localhost 192.168.64.3" \
UX_ACCOUNTS=~/.config/pgtut/local-accounts.json npx playwright test playwright/e2e/rev1112b
```

실행 환경: 튜토리얼 VM(colima pgtut, 192.168.64.3:8088), 계정 `~/.config/pgtut/local-accounts.json`의 admin, 대화방 `RV_CHAT_ROOM`(기본: VM 「영업 제안서 승인 프로세스 설계」 방). 데이터는 읽기만 한다.

## 스펙 시나리오 ↔ 시험

| 시나리오 | 시험 | 결과(2026-11-12) |
|---|---|---|
| F-RV-E01 다크 테마의 사이드바 목록 | `dark-theme.spec.ts` F-RV-E01 | ✅ (수정 전 빌드 ✗) |
| F-RV-E02 다크 테마의 대화방 | `dark-theme.spec.ts` F-RV-E02 | ✅ (수정 전 빌드 ✗) |
| F-RV-E03 다크 테마의 로고 | `dark-theme.spec.ts` F-RV-E03 | ✅ (수정 전 빌드 ✗) |
| F-RV-E04 라이트 테마 | `dark-theme.spec.ts` F-RV-E04 | ✅ (수정 전 빌드도 ✅) |

## 함께 둔 점검 시험(이 스펙 밖)

같은 사진에서는 받아쓰기와 채팅 답변도 실패한 것으로 나타났다. 아래 시험을 통해 로컬에서는 정상적으로 작동함을 확인했다. 운영 환경의 실패는 서버(LLM 프록시) 쪽에서 발생했다(결정 기록 D-1112-02).

| 시험 | 확인 사항 |
|---|---|
| `voice-chat.spec.ts` F-RV-E05 | 녹음을 `/completion/upload`로 보내면 받아쓴 글(200)이 반환된다 |
| `voice-chat.spec.ts` F-RV-E06 | 휴대폰 웹 AI 탭에서 질문하면 에이전트의 답변이 온다(시험 대화방은 시험이 끝나면 삭제한다) |
