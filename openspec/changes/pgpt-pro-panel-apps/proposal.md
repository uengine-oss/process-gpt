## Why
- hark pro 의 "새 패널 만들기" 는 "할 일 목록을 관리하고 싶다" 같은 말 한마디로 데이터 원본(구글 시트)을 만들고, 그 시트를 등록·조회하는 패널을 Home 에 올린다. 시트를 열면 같은 데이터가 보이고, 채팅으로 항목을 더할 수도 있다(참고 영상 `iBIgoC7dxAo`).
- 중소기업에서는 리드 관리, 휴가 일수 관리, 비품 대여 대장처럼 "엑셀 한 장 + 함께 쓰는 입력 화면" 정도의 작은 업무 앱이 많이 필요하다. 지금 pgpt-pro 패널은 개인용이고(`pro_panels.user_id`), 데이터가 패널 JSON(`pro_panels.data`) 안에 갇혀 있어 다른 사람과 나눌 수도, 스프레드시트로 열 수도 없다.
- 공유 폴더(`pgpt-pro-shared-folders`)가 생겨 "여럿이 쓰는 파일 공간 + 구성원 권한 + git 이력" 이 있고, 이음오피스 시트 편집기로 xlsx 를 원래 형식 그대로 열 수 있다. 구글 시트 대신 이 둘을 데이터 원본으로 쓰면 외부 계정 없이 같은 장면을 만들 수 있다.

## What Changes
- **패널 앱**: 채팅("휴가 일수 관리 패널 만들어줘") 또는 Home 의 "새 패널 만들기" 로 작은 데이터 앱을 만든다. 에이전트가 항목(필드·형식·필수·선택지), 계산 열(예: 남은 휴가 = 부여 − 사용), 목록·요약 보기, 입력 폼을 설계한다.
- **데이터 원본 = 공유 폴더의 xlsx**: 앱마다 공유 폴더에 `apps/<앱 이름>.xlsx`(데이터)와 `apps/<앱 이름>.panel.json`(앱 정의)을 둔다. 시트 첫 행은 항목 이름, 맨 앞 숨은 열은 행 ID, 계산 열은 엑셀 수식이다.
- **Home 패널**: 앱은 생성 코드(iframe) 없이 정의를 읽어 그리는 고정 컴포넌트로 보인다. 목록·요약·추가·고치기·지우기, "시트 열기"(이음오피스 시트 편집기), 공유하기.
- **시트와 양방향**: 패널에서 고친 행은 서버가 행 단위로 읽고-고치고-쓰며(행 내용 해시 확인, 다르면 409), 바뀔 때마다 폴더 이력에 작성자와 함께 커밋한다. 이음오피스에서 고쳐 저장하면 그 편집본을 폴더 원본으로 되돌려 쓰고 커밋하며, 패널은 다음 읽기에 그 내용을 보여 준다.
- **공유·권한**: 앱의 권한은 그 폴더의 구성원 권한 그대로다. 구성원은 Home 에 앱이 보이고(`viewer` 보기, `editor` 이상 입력), 구성원이 아니면 목록·행 API 모두 403 이다.
- **에이전트 도구**: 채팅 라우터의 `create_panel` 을 넓혀 데이터 앱을 만들고, `panel_record` 로 채팅에서 행을 더하거나 고친다. 같은 기능을 MCP 게이트웨이 `/mcp/panelapps` 로 낸다(`panel_app_list`, `panel_app_create`, `panel_app_rows`, `panel_app_add_row`, `panel_app_update_row`).

- **2단계 (같은 변경에 추가)**: 공유 앱에 행 단위 규칙(누가 무엇을)이나 숨길 항목이 있으면 데이터를 Supabase 의 앱 전용 표(`panel_data`)에 두고 RLS·열 권한·가린 보기로 **데이터베이스가** 지킨다. 규칙은 정해진 어휘로만 쓰고 서버가 고정 템플릿으로 컴파일한다(모델이 SQL 을 쓰지 않음).
- **이벤트 소싱**: 쌓이고 빠지는 앱(휴가·재고·포인트·예산·승인)은 기록(부여·신청·취소…)을 추가만 하고, 요약·현황은 replay 로 계산한다. 시트에는 이벤트 탭과 SUMIFS 요약 탭.
- **기본 보안·개인정보**: 항목 민감도 자동 분류(하한 적용), 본인·관리자만 보는 기본값, k-익명 합계, 외부인 무접근, 생성 직후 기본값 확인 카드, 모든 통로(API·채팅·MCP·시트·스냅샷·검색) 같은 규칙, 감사 기록.

## Capabilities
### New Capabilities
- `pgpt-pro_panel-apps`: 데이터 패널 앱 설계·생성, 공유 폴더 xlsx 데이터 원본, Home 패널 등록·편집, 시트 편집기 왕복, 폴더 권한 기반 공유, 채팅·MCP 도구

### Modified Capabilities
없음. 기존 생성형 패널(`pro_panels`, 주식·날씨 같은 실시간 위젯)은 그대로 두고, 설계 단계에서 "실시간 위젯" 으로 판단되면 기존 경로로 보낸다. 공유 폴더 기능의 요구사항은 바꾸지 않고 그 서비스 함수를 쓴다.

## Impact
- **pgpt-pro 서버**: `lib/panelApps/`(설계·xlsx 읽기쓰기·서비스), `routes/panelApps.js`, `mcp/panelapps.js`, `lib/agent.js` 의 `create_panel` 확장과 `panel_record`, 폴더 서비스(`lib/folders/service.js`)의 `access`·`createFolder`·`commitMain` 과 색인 `reindex` 사용. 의존성 `exceljs`.
- **pgpt-pro 화면**: `components/panelApps/PanelAppCard.vue`(Home 패널), `HomeDock.vue`, `stores/app.js`, `OfficeSheet.vue`(저장 시 앱 원본으로 되돌려 쓰기), 공유는 `folders/ShareSheet.vue` 재사용.
- **pgpt-pro DB**: `pro_panel_apps`, `pro_panel_app_prefs`(sql/008).
- **process-gpt**: 바꾸지 않는다. 테넌트 MCP 목록에 `pgpt-panelapps` 한 줄과 mcp-hub 서버 등록만 더한다.
