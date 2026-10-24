# E2E — pgpt-pro_credential-vault

보관함 저장 계약(봉투 암호화, 검증, 비노출, 여러 계정·카드, 수정·감지·확인, 활동 기록, 검증 조회)을 실제 데이터베이스에서 확인한다. 테스트는 임시 키링을 써서 서버의 실제 KEK 를 건드리지 않고, KEK → DEK → 항목 체인을 테스트 코드에서 독립적으로 다시 복호화한다.

```bash
cd <process-gpt-lite>/server && node --test test/vault.test.js
```

실행 환경: Supabase(Docker, db :54322) + BFF 소스(테스트는 BFF 프로세스 없이 모듈을 직접 불러 실행).

## 시나리오 ↔ 증거 (`results/vault.test.txt`)

| 스펙 시나리오 | 테스트 |
|---|---|
| 로그인 저장 후 데이터베이스에는 암호문만 남음 | a login is stored only as ciphertext under a per-user DEK wrapped by the KEK |
| 암호문을 다른 사이트로 옮기면 사용할 수 없음 | a ciphertext moved to another site no longer opens |
| 잘못된 카드 번호 / 만료된 카드 | cards are validated and kept apart by number |
| 카드와 로그인이 있는 보관함 조회 | listing and proof never return a secret, and proof checks all pass |
| 같은 사이트의 두 계정 / 두 장의 카드 | several accounts per site…, cards are validated… |
| 거부된 비밀번호만 바꾸기 | `pgpt-pro_browser-credential-handoff` 통합 테스트(login) |
| 새 비밀번호 감지 후 확인 / 확인 전에는 쓰이지 않음 | a captured login is sealed at once but used only after the user confirms it |
| 브라우저 작업이 로그인을 입력한 기록 | several accounts per site…(활동 `create, create, update, fill`), browser 통합 테스트(활동 순서) |
| 검증 통과 | listing and proof never return a secret, and proof checks all pass |

API 수준 확인(2026-10-23, 실제 BFF): 잘못된 카드 → `400 {"error":"카드 번호를 확인해 주세요."}`, 저장 응답·목록에 비밀 필드 없음, `GET /api/vault/proof` 의 모든 검사 `true`. UI 증거는 `../../pgpt-pro_browser-credential-handoff/e2e/results/11~15-*.png`.
