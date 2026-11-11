# 결정 칸 — E2E

- 단위: process-gpt-vue3 `node --test src/shared/decisionField/decisionField.test.js` (3개)
- 회귀: `playwright/e2e/mobile-view` 의 F-MV-11 — `MV_APPROVAL_TASK_ID=<처음 연 승인 업무 id>` 가 있어야 돈다. 같은 단계가 다시 돌아 지난 값이 남은 업무(반려 뒤 재검토)는 지난 값이 보이므로 쓰지 않는다.
- 2026-11-11 설치본(VM): 새 「영업 제안서 승인」 인스턴스의 첫 검토 업무에서 ✅ (검토 결과 비어 있음, 제출 막힘, 업무 IN_PROGRESS 유지)
