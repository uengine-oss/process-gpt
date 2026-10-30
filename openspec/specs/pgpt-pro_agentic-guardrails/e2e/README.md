# E2E — pgpt-pro_agentic-guardrails

정책 판단(PDP), 판단 집행(PEP: 실행·기록·보관·승인·회수), 결정 원장, 직무 분리, 메일 행위의 사실 추출, 막힌 출시의 대안 경로 최적화, 원장에서 배우는 정책 조정을 실제 데이터베이스와 실제 BFF 에서 확인한다.
- 판단 사례와 정책 조정은 서버 모듈을 직접 부른다. 각자 만든 테넌트를 쓰고 끝나면 지운다.
- 시나리오는 데모 테넌트 `localhost` 의 출연진(장진영·김민지·이도윤)으로 HTTP 와 채팅을 거친다. 끝나면 자기가 만든 것을 지운다.
- 메일은 실제로 나가지 않고 시연용 보낸편지함에만 들어간다.

```bash
# 공개 저장소 uengine-oss/process-gpt-lite, 브랜치 feat/agentic-bpm (https://github.com/uengine-oss/process-gpt-lite/tree/feat/agentic-bpm)
cd server && node --test test/policy.test.js test/agentic-regression.test.js test/agentic-insights.test.js
. <env: PRO_LLM_* (gpt-4.1-mini), PRO_BACKGROUND=0> && PRO_PORT=8793 node index.js     # BFF
PRO_API=http://localhost:8793 node test/scenario-mail.e2e.mjs                           # 메일 시나리오 (채팅 포함)
node test/scenario-release.e2e.mjs --api http://localhost:8793                          # 금요일 출시 (스스로 초기화)
node test/scenario-purchase.e2e.mjs --reset --api http://localhost:8793                 # 구매 승인 (프로세스 엔진 polling 필요)
cd ../e2e && API_URL=http://localhost:8793 npx playwright test --project=feature tests/feature/agentic.spec.js
```

실행 환경: Supabase(Docker, db :54322) + BFF 소스 실행(:8793) + process-gpt 프로세스 엔진(completion polling, 구매 요청 인스턴스를 진행) + OpenAI gpt-4.1-mini(라우터 도구 선택·대안 생성·QA 발견 문구·브리프 추천 문구).
SQL 이주 `server/sql/024_agentic_bpm.sql`, `025_scenario_mail.sql`, `026_scenario_purchase.sql`, `027_scenario_release.sql` 이 적용돼 있어야 한다.

## 시나리오 ↔ 증거 (`results/`, 2026-10-30)

| 스펙 시나리오 | 시험 | 증거 |
|---|---|---|
| 처음 조회한 테넌트 | `agentic-regression` "seed the catalog for a clean tenant" | `server-tests.txt` |
| 관리자가 아닌 사람이 정책을 끄려 함 / 형식이 틀림 | F-AG-01 | `playwright-agentic.txt` |
| 외부 메일에 개인정보 3건 / 50건 이상 / 허용 오차 결제 / 정책이 없는 행위 | 판단 사례 30개, F-AG-02 | `server-tests.txt`, `playwright-agentic.txt` |
| 하루 21번째 외부 메일 | `policy.test.js` "the window", 메일 E2E 7단계 | `server-tests.txt`, `scenario-mail.txt` |
| 개인정보 책임자가 승인 | 메일 E2E 4단계(이도윤 승인 → 장진영 이름으로 발송), F-AG-04 | `scenario-mail.txt`, `playwright-agentic.txt` |
| 요청한 사람이 스스로 승인하려 함 / 역할이 없는 사람 | F-AG-04(관리자인 요청자도 403), `policy.test.js` | `playwright-agentic.txt`, `server-tests.txt` |
| 기밀 자료를 반려 | 메일 E2E 6단계 | `scenario-mail.txt` |
| 외부 메일을 10분 안에 회수 | F-AG-03, 메일 E2E 3단계 | `playwright-agentic.txt`, `scenario-mail.txt` |
| 팀원이 원장을 봄 | F-AG-05 | `playwright-agentic.txt` |
| 개인정보가 든 메일의 원장 줄 | F-AG-04(원장에 번호·주소 원문 없음, `pii_count` 4), 메일 E2E 1단계 | `playwright-agentic.txt`, `scenario-mail.txt` |
| 사내 메일 / 고객 명단 전체 첨부 | 메일 E2E 2·5단계, 채팅 단계(라우터가 `send_mail` 을 고름) | `scenario-mail.txt` |
| 금요일 16시 공개 출시 / 릴리스 책임자의 선택 / 보안 점검 실패 | 릴리스 E2E 1·2·5·6단계 | `scenario-release.txt` |
| 고객 신뢰를 5순위로 | 릴리스 E2E 3단계 | `scenario-release.txt` |
| 1,000만 원 넘는 구매 / 승인 전 발주 / 두 승인 뒤 인계와 발주 / 반려의 보상 / 나중에 온 요청이 먼저 | 구매 E2E 1~6단계(26개 확인) | `scenario-purchase.txt` |
| 늘 승인되는 정책 / 관리자가 아닌 사람(리포트) | `agentic-insights.test.js`, F-AG-05 | `server-tests.txt`, `playwright-agentic.txt` |

화면 증거는 같은 시나리오를 녹화한 영상이다. 정책·가드레일 세 탭, 승인 알림 → 원장 줄 강조 → 승인, 채팅 카드가 바뀌는 모습, 전략맵과 다시 순위 매기기가 나온다(유튜브 일부 공개, 아래 표).

| 영상 | 내용 |
|---|---|
| 메일 가드레일 [-1VuYuna3EA](https://youtu.be/-1VuYuna3EA) | 사내 허용 · 외부 기록·회수 · 개인정보 승인 · 명단 전체 차단 · 21번째 메일 |
| 금요일 출시 [Pws7Y-HNSHk](https://youtu.be/Pws7Y-HNSHk) | 막힌 출시 → 대안 · 릴리스 책임자 선택 · 우선순위 변경 · 예외 권한자 |
| 승인 대기 줄이기 [zsqKdt57lU0](https://youtu.be/zsqKdt57lU0) | 구매 요청 → 결정 브리프 · 미리 해 둔 초안 · 재무 승인 · 인계 꾸러미 발주 · 반려 보상 |
| 원장에서 배우기 [wpwh7QEoRXM](https://youtu.be/wpwh7QEoRXM) | 리포트 · 정책 조정 제안 적용 · 시험해 보기 |
