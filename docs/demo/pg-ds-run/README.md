# Process GPT — 디자인 시스템 전면 교체 시연

`feat/design-system-claude` 브랜치를 **전체 Supabase 스택(15개 컨테이너)과 함께** 띄워
디자인 시스템 교체 결과를 로그인부터 앱 전반까지 돌린 기록이다.

| 파일 | 내용 |
|---|---|
| `process-gpt-design-system.mp4` | 전체 시연 (44초, 1440×900) |
| `before-vuetify-blue.png` | **교체 전** — 기존 Material 블루 팔레트 |
| `final.png` | **교체 후** — 인스턴스 목록 화면 |
| `contact-sheet.png` | 4초 간격 키프레임 |

`before-vuetify-blue.png` 와 `final.png` 를 나란히 보면 교체 범위가 바로 보인다.

## 시연 순서

**1부 — 디자인 시스템 자체 (`/design-system`)**
1. 색 · 타이포그래피 · 버튼
2. 폼 상호작용 → 다이얼로그 → 대화 UI (말풍선 · 세리프 본문 · 표 · 컴포저)
3. 다크 모드 전환

**2부 — 실제 제품 화면**
4. 로그인 (Pg* 로 재작성)
5. `demo@localhost` 실제 로그인 → 프로세스 정의 체계도
6. BPMN 편집기 (실제 프로세스 정의 로드)
7. 할일 목록 (칸반)
8. 인스턴스 목록

## 교체 방식

화면 570개를 하나씩 고치는 대신 **Vuetify 의 팔레트·형태 언어 자체를 새 토큰으로 갈아끼웠다.**

| 레이어 | 파일 | 역할 |
|---|---|---|
| 토큰 → Vuetify 테마 | `src/ds/vuetify-bridge/theme.ts` | 색 팔레트를 토큰 값으로 |
| 형태·타이포 덮개 | `src/ds/vuetify-bridge/overrides.css` | 라운드·그림자·헤어라인·타이포 스케일·대문자 버튼 제거·리플 제거 |
| 테마 상수 | `src/theme/{LightTheme,DarkTheme}.ts` | 기존 12개 Material 테마 → 단일 언어(라이트/다크) |
| 컴포넌트 기본값 | `src/plugins/vuetify.ts` | elevation 0, 컴팩트 밀도, 토큰 라운드 |

덕분에 `<v-*>` 를 쓰는 570개 파일이 코드 수정 없이 전부 새 디자인 언어로 렌더된다.

## 재현

```bash
# 1) 전체 스택 (studio/neo4j 는 기존 컨테이너와 포트가 겹쳐 재매핑)
cd docker-infra
NEO4J_HTTP_PORT=7476 NEO4J_BOLT_PORT=7689 STUDIO_PORT=3005 docker compose up -d

# 2) 데모 계정 비밀번호
SRK=$(grep '^SERVICE_ROLE_KEY=' .env | cut -d= -f2)
UID=$(docker exec supabase-db psql -U postgres -d postgres -tAc \
  "select id from auth.users where email='demo@localhost'")
curl -s -X PUT "http://localhost:54321/auth/v1/admin/users/$UID" \
  -H "apikey: $SRK" -H "Authorization: Bearer $SRK" -H "Content-Type: application/json" \
  -d '{"password":"demo1234","email_confirm":true}'

# 3) 프론트엔드 (Node 22 필요 — Node 25 는 vite-plugin-monaco-editor 가 죽는다)
cd ../services/frontend && npx vite --host 127.0.0.1 --port 5199

# 4) 시연 + 녹화
node playwright/demo/design-system-run.mjs ../../docs/demo/pg-ds-run
```

## 확인된 것 / 남은 것

**동작 확인 (9/9 단계)**
- Vuetify 를 쓰는 모든 화면이 새 팔레트·형태 언어로 렌더
- **하드코딩 색상 치환** — `.vue` 200개에서 1,550건.
  `<style>` 내 1,953건 → 586건, 인라인 `style=""` 201건 → 22건
- **BPMN 캔버스 토큰화** — 도형·외곽선·상태색이 토큰 기반.
  SVG 속성은 `var()` 를 못 읽어 `customBpmn/dsPalette.js` 가 불투명 hex 로 해석해 넘긴다
- Supabase 인증 → 테넌트 설정 → 앱 라우팅
- 빌드 통과, 신규/변경 코드 타입 에러 0

**아직 새 디자인 시스템이 아닌 것**
- **`<script>` 안의 색 623건.** 차트 옵션 · `THREE.Color` · 일부 렌더러 값처럼
  CSS 가 아닌 곳에서 쓰여 `var()` 를 넣으면 깨진다. 값별로 판단해 옮겨야 한다.
- **`<style>` 잔여 586건.** 매핑에 없던 롱테일(각 7건 이하)로,
  장식용 그라디언트·일러스트 전용 색이 대부분이다.
- **Vuetify 자체는 아직 제거되지 않았다.** 570개 파일이 `<v-*>` 를 쓰고 있어
  물리적 제거를 하려면 97종 호환 컴포넌트 + Vuetify 유틸리티 CSS
  (`ma-*`, `d-flex`, `text-h*` 등) 대체가 선행돼야 한다.
- Pg* 로 실제 재작성한 화면은 로그인 하나.

**미확인 (서비스 미기동)**
스킬 서비스, `get_credit_balance` RPC, `palette_task_types` 테이블 부재로 콘솔 에러 발생.
AI 기능(completion/deepagents)은 마이크로서비스를 띄우지 않아 검증하지 않았다.
