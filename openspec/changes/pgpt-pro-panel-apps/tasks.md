## 1. 설계
- [x] 1.1 참고 영상(hark pro part2) 흐름 정리, 기존 패널·공유 폴더·이음오피스 연동 확인 (`design.md` 1~2장)
- [x] 1.2 앱 정의·저장 위치·시트 배치·동시 편집·권한·도구 결정 (`design.md` 3장)

## 2. 서버
- [x] 2.1 `sql/008_panel_apps.sql` — `pro_panel_apps`, `pro_panel_app_prefs`
- [x] 2.2 `lib/panelApps/sheet.js` — 정의 검증, 계산 식, xlsx 쓰기·읽기(exceljs), 행 해시
- [x] 2.3 `lib/panelApps/service.js` — 설계(LLM)·생성(폴더·파일·커밋·색인)·행 CRUD(직렬화·409)·시트 사본·편집본 되돌려 쓰기·구성원 알림
- [x] 2.4 `routes/panelApps.js` API, `index.js` 연결
- [x] 2.5 `agent.js` — `create_panel` 확장, `panel_record`, 앱 이름 요청의 폴더 변형 경로 제외
- [x] 2.6 `mcp/panelapps.js` + 테넌트 MCP·mcp-hub 등록

## 3. 화면
- [x] 3.1 `PanelAppCard.vue` — 요약·목록·폼·시트 열기·공유·숨기기
- [x] 3.2 `HomeDock.vue`·`stores/app.js` — 목록 로드, `panelapp` 이벤트
- [x] 3.3 `OfficeSheet.vue` — 앱 시트 저장 시 원본으로 되돌려 쓰기

## 4. 검증
- [x] 4.1 채팅으로 "리드 관리", "휴가 일수 관리" 생성
- [x] 4.2 패널로 행 추가·수정, 409 확인
- [x] 4.3 이음오피스 시트에서 행 확인·셀 수정·저장 → 패널 반영
- [x] 4.4 공유: 구성원은 보임, 비구성원 403
- [x] 4.5 스크린샷 검토, 녹화 시나리오 1회 실행

## 5. 검증 결과 (2026-10-24)
- 채팅 "리드 관리 패널 만들어줘…" → 라우터 `create_panel` → 앱 생성 17초, Home "새 패널 만들기: 팀 휴가 일수 관리…" → 결정적 경로로 생성. 채팅 "리드 관리에 한빛상사 김과장 추가해줘…" → `panel_record` 로 행 추가(3000만원 → 30000000).
- 이음오피스 시트 편집기(Univer)는 저장 시 숨은 ID 열·ID 값·계산 열 수식(`=(C2-D2)`)을 그대로 보존함을 확인. 저장은 툴바 저장 아이콘(Ctrl/Cmd+S 는 `saved` 메시지를 보내지 않음).
- 행 고치기 409, 필수·형식 422, 비구성원 목록 빈 배열·행/시트 API 403, 팀원(editor) 행 추가 → 소유자 패널에 이벤트로 반영, 폴더 이력에 작성자별 커밋.
- MCP `/mcp/panelapps` 테넌트 등록(`pgpt-panelapps`)·mcp-hub active, `panel_app_list` 응답 확인. 단위 테스트 `server/test/panelApps.test.js` 3/3.
- 남은 것: 시트 드롭다운(데이터 유효성)은 exceljs 가 범위를 잘못 써서 넣지 않음(선택지는 패널·서버가 검증). 편집기를 연 채 패널에서 행이 바뀌면 편집기 저장은 409(셀 단위 병합 없음). 편집기 자체 알림 "편집본이 원본 옆에 올라갔어요" 는 패널 앱 시트에도 그대로 뜸.

## 6. 2단계 — 저장 단계·이벤트 소싱·기본 보안
- [x] 6.1 `sql/009_panel_data.sql`(panel_data 스키마, folder_role, 단계 열, 변경 기록), `sql/010_panel_privacy.sql`(kind, privacy_ack, 감사)
- [x] 6.2 `lib/panelApps/rules.js` 어휘 검증·고정 템플릿 컴파일(정책·가드 트리거·열 권한·가린 보기)·JS 미러·한국어 설명
- [x] 6.3 `lib/panelApps/db.js` 사람 = `set local role authenticated` + JWT 클레임, 소유자 = DDL, 오류 → 한국어
- [x] 6.4 `lib/panelApps/events.js` 기록 정의·검증·replay·k-익명·이벤트 탭/요약 탭(SUMIFS)·저장 비교·추가만 되는 기록 표
- [x] 6.5 `lib/panelApps/privacy.js` 민감도 하한·대상·기본 규칙·단계 결정·기본값 카드
- [x] 6.6 서비스·API: 규칙/항목/민감도 변경(낮춤 확인·감사), 기록 추가, 시트 보기(사람별 사본)·저장 비교, 폴더 스냅샷(가림), 목록→기록 전환, 기본값 확인
- [x] 6.7 화면: 행 권한 배지·규칙 요약, 행별 보기 전용, 기록 앱 본문(요약·현황·기록·기록 폼·취소), 기본값 카드, 권한 규칙 시트(미리보기·민감도·기록 권한·항목)
- [x] 6.8 채팅(panel_record 기록 앱, "…패널 만들어줘" 바로 처리)·MCP(panel_app_append_event, 가림 반영)
- [x] 6.9 PostgREST 노출(`pgrst.db_schemas` 에 panel_data, DDL 뒤 reload schema)
- [x] 6.10 시험: 규칙 컴파일·주입(6), 이벤트·개인정보 단위(9), RLS 통합(8), 이벤트 통합(7), 통로별 개인정보 E2E(6)
- [x] 6.11 3인 공유 캘린더 확인(화면·API·시트 보기), 스크린샷, 녹화 시나리오
- [ ] 6.12 채팅으로 규칙 바꾸기 라우터 도구, 시트 보기 사본의 서명 URL(이음오피스 호스트 변경 필요)
