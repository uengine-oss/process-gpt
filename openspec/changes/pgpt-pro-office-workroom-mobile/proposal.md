## Why
- 에이전트가 만든 문서(한글·엑셀·파워포인트)를 사람이 내려받아 다른 프로그램으로 고쳐야 했다. process-gpt 프론트엔드에는 이음오피스 편집기가 붙어 있지만 pgpt-pro 에는 없었다.
- 에이전트가 일한 폴더(Claude Code worktree, deepagents 작업 폴더)를 사람이 들여다보거나 고치거나, 실행 중·실행 뒤에 방향을 바꿀 길이 없었다. "동작 보기" 는 기록만 보여 줬다.
- 외부(휴대폰, 사외)에서 pgpt-pro 를 쓰려면 공개 주소와 모바일 앱이 필요했다.

## What Changes
- **이음오피스 편집**: office-mcp(origin/main, `store_and_render_hwpx`)를 붙이고 문서 결과·샌드박스 문서를 저장소 URL 카드로 만들어 편집기 시트로 연다. 저장하면 편집본으로 카드가 바뀐다.
- **에이전트 작업실**: 실행 폴더의 파일 트리·미리보기·편집(코드 주입), 셸, Claude Code 세션 이어서(`--resume`), deepagents 스티어링, 화면 펼치기.
- **공개 접속**: Cloudflare 임시 터널 + 접근 암호(쿠키), 터미널 열쇠, SSE 대신 롱폴링 자동 전환.
- **Android 앱**: 서버 주소를 설정하는 Kotlin WebView APK.

## Capabilities
### New Capabilities
- `pgpt-pro_office-editor`, `pgpt-pro_agent-workroom`, `pgpt-pro_android-app`
### Modified Capabilities
없음

## Impact
- **백엔드**: `services/office-mcp` 를 origin/main(7e95c6e)으로 빨리감기, `.env` 생성(사내 LLM), :1192 실행.
- **테넌트 MCP**: `office-mcp`, `ieum-office` 등록.
- **로컬 Supabase**: `deep_research_files`·`deepagent_files` 공개 버킷과 정책 추가.
- **pgpt-pro 서버**: `lib/office.js`, `lib/workroom.js`(node-pty, ws), `lib/bus.js`(롱폴링), `index.js`, `config.js`(`PRO_HWPX_TEMPLATE_URL`, `PRO_TERMINAL_KEY`, `PRO_CLI_WORKSPACE_ROOT`).
- **pgpt-pro 화면**: `OfficeEditorFrame.vue`, `OfficeSheet.vue`, `officeEditor.js`, `WorkroomView.vue`, `WorkroomTerminal.vue`, `vite.config.js`(`/office` 프록시, 공개 접근 게이트).
- **Android**: `pgpt-pro/android`(APK `docs/demo/pgpt-pro-0.1.0.apk`).
