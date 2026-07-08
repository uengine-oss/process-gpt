# Playwright Headed 데모 — "휴가 신청 프로세스" E2E 시연

설치 검증 통과 후, 사용자가 지켜보는 **headed 모드** 브라우저로 Process GPT의
핵심 플로우를 시연한다. 실전에서 end-to-end 동작이 확인된 시나리오다.

## 준비

```bash
# playwright가 없으면 (스크래치 디렉토리 등 격리된 곳에):
npm init -y && npm i playwright && npx playwright install chromium
```

MCP playwright 도구가 세션에 있으면 그것을 우선 사용 (headed 옵션 확인).
없으면 아래 시나리오를 스크립트로 작성해 실행한다.

- BASE URL: 게이트웨이 `http://localhost:8088` (또는 dev 서버 :5199 / 원격 호스트)
- 계정: verification.md 4에서 준비한 계정
- 각 단계마다 `page.screenshot()` 저장 → 종료 후 사용자에게 경로 보고

## 시나리오 (스텝별 기대 결과)

1. **접속/로그인**: `$BASE` → 이메일/비밀번호 로그인 → 메인 화면.
   - 실패 시: troubleshooting #11/#12.
2. **메인 채팅 진입**: `/definition-map` — placeholder
   "예: 휴가 신청 프로세스 만들어줘 …"인 textarea 확인.
3. **초안 생성**: "휴가 신청 프로세스 만들어줘" 입력·전송.
   - 네트워크 기대: `chat_rooms` 201 → `chats` 201 → `agent-router/route` 503
     (정상 폴백) → `agent/chat/stream` 200 (SSE).
   - 화면 기대: 에이전트가 4단계 초안(휴가 신청 → 상사 승인 요청 → 승인/반려
     결정 → 결과 통보) + 흐름도 렌더 (수십 초).
   - `chat_rooms` 400이면 #13, "생각 중" 고착이면 #13-b.
4. **확정 생성**: "이대로 생성해줘" 전송 → `/definitions/chat`으로 이동 →
   BPMN 다이어그램 + 폼 생성, "프로세스 생성을 모두 완료하였습니다 🎉" (~30초).
5. **저장**: BPMN 디자이너의 💾 (또는 결과 카드 "저장",
   `ProcessArtifactViewer`의 `save-generated-process`, 아이콘
   `mdi-content-save-outline`) 클릭 → 저장 다이얼로그 확인.
   - headless에서 💾가 selector로 안 잡히면: 캔버스 좌표 클릭 + `Ctrl/Cmd+S`
     + 다이얼로그 "저장" 조합. headed 실브라우저에선 💾 한 번으로 충분.
   - **자동저장은 설계상 없음** — 저장 클릭 전 `proc_def` 0건은 정상.
6. **영속화 확인**:
   ```bash
   PSQL "select id, name, tenant_id from public.proc_def order by created_at desc limit 3;"
   ```
   `POST /rest/v1/proc_def` 201 + 행 존재 → 데모 성공.
   400 PGRST204(agent_id)면 #16-b 컬럼 보정.

## 스크립트 골격 (참고)

```javascript
// demo.mjs — node demo.mjs 로 실행 (headed)
import { chromium } from 'playwright';
const BASE = process.env.BASE ?? 'http://localhost:8088';
const browser = await chromium.launch({ headless: false, slowMo: 300 });
const page = await browser.newPage();
page.on('response', r => { if (r.status() >= 400) console.log('HTTP', r.status(), r.url()); });

await page.goto(BASE);
// 로그인 → 채팅 입력 → 스트리밍 대기 → 확정 → 저장. selector는 실제 DOM을
// 브라우저 스냅샷으로 확인하며 채울 것 (빌드 버전에 따라 달라짐).
await page.screenshot({ path: 'step1-login.png' });
// ...
```

selector는 프론트 빌드에 따라 바뀌므로 하드코딩 유지하지 말고, 실행 시점에
스냅샷/접근성 트리로 확인하면서 진행한다. SSE 응답 대기는 고정 sleep 대신
화면 텍스트(예: "휴가") 출현을 폴링한다 (최대 120초).

## 데모 후 보고

- 스텝별 스크린샷 경로 목록
- 확인된 네트워크 상태 (chat_rooms/chats/proc_def 상태코드)
- `proc_def`에 저장된 프로세스 id/name
- 발견된 이상 징후와 적용한 수정 (troubleshooting에 추가했는지)
