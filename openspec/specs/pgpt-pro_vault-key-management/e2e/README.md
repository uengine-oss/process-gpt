# E2E — pgpt-pro_vault-key-management

KEK 공급원, 업그레이드 호환, KEK·DEK 교체, 폐기 KEK 정리, 전수 검증을 확인한다.

- 교체 시나리오는 임시 키링과 테스트 사용자만 대상으로 실행한다(`rotateKek({ userIds })`). 운영 키링은 바뀌지 않는다.
- 업그레이드 호환과 전수 검증은 실제 운영 데이터에 운영 명령을 실행한 결과다.

```bash
cd <process-gpt-lite>/server
node --test test/vault.test.js            # 교체·정리 테스트 포함
node scripts/vault-admin.mjs status        # 키링, KEK 별 DEK 수, 항목 수
node scripts/vault-admin.mjs verify        # 모든 항목 열기 + 구분 지문 채우기
# 운영 교체 (실행 후 BFF 재시작)
node scripts/vault-admin.mjs rotate-kek
node scripts/vault-admin.mjs prune-kek
node scripts/vault-admin.mjs rotate-dek <user-id|--all>
```

## 시나리오 ↔ 증거

| 스펙 시나리오 | 증거 |
|---|---|
| 보안 정보 조회 | `GET /api/config` → `vault: {kekId: "9707235137c3", provider: "file", keyVersions: 1, algorithm}` |
| 단일 키 파일에서 키링으로 | 업그레이드 직후 `verify`: 사용자 3, 항목 3, 성공 3, 구분 지문 채움 3, KEK `9707235137c3`(이전과 동일) |
| 교체 후 항목은 그대로, DEK 만 다시 감쌈 | `results/vault.test.txt` — KEK rotation rewraps DEKs without touching item ciphertext… |
| 교체 후 정리 | 같은 테스트 — 정리 후 이전 KEK 가 키링에서 사라지고 항목이 열림 |
| 로그인과 카드가 있는 사용자의 DEK 교체 | `results/vault.test.txt` — DEK rotation re-encrypts every item under a new DEK version |
| 운영 데이터 검증 | `results/vault-admin.txt` — `items` 와 `ok` 가 같고 `failed: []` |
| 환경 변수 공급원 / 오래된 DEK / DEK 교체 기록 | 코드 경로(교체 거절 메시지, 10분 캐시, `rotate_dek` 활동은 DEK 교체 테스트에서 확인) |
