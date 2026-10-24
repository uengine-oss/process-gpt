# 패널 앱 설계 — 공유 폴더의 xlsx 를 데이터 원본으로 쓰는 작은 업무 앱

## 1. 참고 장면 (hark pro, 영상 `iBIgoC7dxAo` "harkpro part2", 16분, 음성 없음)
화면에서 확인한 흐름만 적는다(개인 정보는 옮기지 않는다).
1. Home 왼쪽 패널 열 맨 아래 "+ 새 패널 만들기" 를 누르면 채팅 입력창이 패널 설명 모드가 되고, 첫 말풍선이 "새 패널 만들기" 로 시작한다.
2. 사용자가 "내 할 일 목록 — 이런 것들을 모아서 여기에 등록되도록" 처럼 쓴다. 에이전트는 데이터 원본을 묻는다("Google Tasks 에 모아 두고 패널로 보여 드릴까요, 메일에서 따로 쓰시는 라벨이 있나요?").
3. 사용자가 "그냥 직접 만들어서 넣어줘" 라고 하면 에이전트가 구글 시트를 직접 만들고 "'내 할일' 패널이 Home 에 올라갔어요", "남은 할 일 목록과 '시트 열기' 버튼이 있고, 한 시간마다 새로 불러와요" 라고 답한다.
4. Home 패널: 제목 "내 할일", 요약 한 줄("남은 할일 2건"), 항목 카드(제목·부제·날짜·항목별 버튼), 맨 아래 "시트 열기" 버튼.
5. 채팅으로 "내일 ○○랑 스크린 골프치기" 라고 하면 에이전트가 시트에 행을 더하고("할일 목록에 넣었어요: 10월 18일(일)…"), 패널 목록이 2건으로 늘어난다.
6. 이후 영상은 카카오 알림 연동(개발자 콘솔 브라우저 작업)으로, 패널 기능과는 별개다.

우리 판에서 바꾸는 것: 구글 시트 → **공유 폴더의 xlsx**(외부 계정 불필요, 사내 보관, git 이력), 시트 열기 → **이음오피스 시트 편집기**, 개인 패널 → **폴더 구성원이 함께 쓰는 패널**, 생성형 HTML 패널 → **정의(JSON)를 읽어 그리는 고정 컴포넌트**(입력 폼·검증·권한을 서버가 보장해야 하므로).

## 2. 지금 상태 (코드 확인)
- 패널: `server/lib/panels.js` 의 `generatePanel` 이 LLM 으로 HTML+스크립트를 만들어 `pro_panels(user_id, title, icon, spec{html,script}, data)` 에 넣고, `PanelFrame.vue` 가 sandbox iframe 으로 돌린다. 데이터는 `pro_panels.data` JSON 하나, 소유자 한 명. 라우터 도구 `create_panel`(agent.js)이 이 경로를 부른다.
- 공유 폴더: 폴더 = git 저장소, 작업 트리가 곧 `main`(`lib/folders/service.js`). 구성원 `owner ⊃ editor ⊃ runner ⊃ viewer`(`access(slug,user,need)`), 사람 편집은 `commitMain(folder, author, msg)` 로 작성자 커밋, 파일 색인 `reindex(folder)`. 폴더 파일은 `POST /folders/:slug/publish` 로 스토리지에 내용 주소 사본을 올려 이음오피스로 연다(읽기 전용 미리보기).
- 이음오피스: `OfficeEditorFrame.vue` 가 `/office/sheets/?src=<스토리지 URL>` 을 iframe 으로 열고, 편집기에서 저장하면 `edited-…` 사본을 스토리지에 올린 뒤 `postMessage({type:'saved', url})` 를 보낸다. 원본 파일은 바뀌지 않는다.
- xlsx 라이브러리: 서버 node_modules 에 없음 → `exceljs@4.4.0` 추가(수식·숨은 열·열 너비·데이터 유효성 지원). 파이썬 openpyxl 은 있으나 서버가 노드라 쓰지 않는다.

## 3. 결정

### 3.1 앱 정의 (`apps/<앱 이름>.panel.json`)
```json
{
  "version": 1,
  "title": "휴가 일수 관리", "icon": "🌴",
  "description": "팀원별 연차 부여·사용 일수와 남은 일수",
  "sheet": "휴가",
  "fields": [
    {"key": "name",    "label": "이름",     "type": "text",   "required": true},
    {"key": "team",    "label": "팀",       "type": "choice", "choices": ["영업", "개발", "경영지원"]},
    {"key": "granted", "label": "부여 일수", "type": "number", "required": true, "default": 15},
    {"key": "used",    "label": "사용 일수", "type": "number", "default": 0},
    {"key": "note",    "label": "메모",     "type": "longtext"}
  ],
  "computed": [{"key": "left", "label": "남은 일수", "expr": "granted - used", "type": "number"}],
  "views": {
    "list": {"title": "name", "subtitle": ["team"], "value": "left", "valueSuffix": "일", "sort": {"key": "left", "dir": "asc"}},
    "summary": [{"label": "인원", "agg": "count"}, {"label": "남은 일수 합계", "agg": "sum", "field": "left"}]
  },
  "form": ["name", "team", "granted", "used", "note"]
}
```
- 형식: `text`, `longtext`, `number`, `date`(YYYY-MM-DD), `choice`(choices 중 하나), `checkbox`, `email`, `phone`, `person`(이름 문자열).
- 계산 열 `expr` 은 필드 key·숫자·`+ - * /`·괄호만 허용하는 작은 계산기로 서버와 화면이 같은 규칙으로 계산한다(`eval` 금지). 시트에는 같은 식을 엑셀 수식(`=D2-E2`)으로 쓰고 계산값을 함께 넣는다. 읽을 때 계산 열 값은 무시하고 다시 계산한다.
- 설계는 LLM 한 번(JSON 응답). 서버가 검증·보정한다: key 는 영문 소문자 고정, label 중복 제거, 필드 2~12개, 계산 식의 미지 key 거절, 보기·폼이 없는 key 를 가리키면 제거. 설계 결과가 "실시간 외부 데이터 위젯"(주가·날씨·환율)이면 `{"kind":"live"}` 를 돌려주고 기존 `generatePanel` 로 보낸다.
- 요청에 처음 데이터가 있으면(“김민지 15일, 이준호 15일 3일 사용”) 설계 응답의 `rows` 로 받아 첫 행으로 넣는다.

### 3.2 저장 위치 — 파일이 원본, DB 는 색인
- 정의와 데이터는 폴더 파일: `apps/<앱 이름>.panel.json`, `apps/<앱 이름>.xlsx`. 폴더를 열면 사람이 바로 찾고, 이력·인계·반영이 파일 그대로 따라간다.
- DB `pro_panel_apps(id, folder_id, title, icon, def_path, sheet_path, def, def_sha, created_by, …)` 는 Home 목록을 빠르게 그리기 위한 색인이다. 정의 파일의 blob sha 가 바뀌면 다시 읽어 `def` 를 갱신한다.
- `pro_panel_app_prefs(user_id, app_id, hidden, sort)`: 사람마다 Home 에서 숨기기·순서.
- 폴더 선택: 요청이 사용자가 `editor` 이상인 폴더 이름을 말하면("영업팀 폴더에 리드 관리 패널") 그 폴더, 아니면 앱 이름으로 새 관리형 폴더를 만든다(이름이 겹치면 " 2"). 만든 사람이 `owner`.

### 3.3 시트 배치
- 시트 이름 = 정의의 `sheet`(기본 "데이터"). 1행 = 머리글(필드 label, 굵게, 고정), A열 = `ID`(숨김, 너비 4, 값은 `r_` + 8자), B열부터 정의 순서의 필드, 그 뒤 계산 열(수식).
- 선택형은 데이터 유효성(목록), 숫자·날짜는 셀 형식으로 쓴다. 날짜는 `YYYY-MM-DD` 문자열로 저장한다(편집기·지역 설정 차이 회피).
- 읽기: 머리글 label 로 열을 찾고(사람이 열 순서를 바꿔도 됨), 못 찾은 필드는 정의 순서의 위치로 대신한다. 빈 행은 건너뛴다. ID 가 없는 행(시트에서 사람이 직접 더한 행)은 `row:<행 번호>` 임시 ID 로 보이고, 다음 쓰기 때 서버가 ID 를 채워 넣는다.

### 3.4 동시 편집
- 모든 패널 쓰기는 서버를 거친다. 앱마다 서버 안 직렬화 큐(한 번에 하나), 그 안에서 **행 단위 읽기-고치기-쓰기**: 파일을 다시 읽어 대상 행을 ID 로 찾고, 클라이언트가 읽었던 행 내용 해시(`_v`)와 지금 해시가 다르면 409("다른 사람이 먼저 고쳤어요")로 거절, 같으면 그 행만 바꿔 쓴다. 추가는 충돌이 없다.
- 쓰기 뒤 `commitMain(folder, 작성자, "패널: <앱> 행 추가 — <제목 필드 값>")` 으로 폴더 이력에 남기고 `reindex(folder,{cards:false})` 로 파일 목록 색인만 갱신한다(카드 LLM 호출을 행마다 하지 않음).
- 시트 편집기 저장: 편집기가 올린 `edited-…` 사본 URL 을 받아(우리 스토리지 주소만 허용) 내려받고, xlsx 로 읽히는지 확인한 뒤 폴더 원본에 덮어쓰고 커밋한다("시트에서 고침"). 그 사이 패널 쓰기가 있었으면(편집기를 연 시점의 파일 sha 와 지금 sha 가 다르면) 덮어쓰지 않고 409 와 함께 "다시 열어 주세요" 를 알린다.
- 폴더 화면의 올리기·작업실 편집처럼 다른 경로로 바뀐 경우도 다음 읽기에 그대로 반영된다(파일이 원본).
- 바뀔 때마다 그 폴더 구성원 모두에게 `panelapp` 이벤트를 보내 Home 패널이 다시 읽는다.

### 3.5 공유와 권한
- 앱의 권한 = 폴더 구성원 권한(`service.access`). `viewer` 이상: Home 에 보이고 목록·시트 보기. `editor` 이상: 행 추가·고치기·지우기, 시트 편집기 저장. `owner`: 앱 삭제, 구성원 관리.
- 패널 메뉴의 "공유하기" 는 공유 폴더의 `ShareSheet` 를 그대로 띄운다(초대 기본 권한만 `editor` 로). 구성원이 아니면 `GET /api/panel-apps` 에 나오지 않고 `GET /api/panel-apps/:id/rows` 는 403 이다.
- 시트 편집기는 `editor` 미만에게 읽기 전용으로 연다.

### 3.6 에이전트가 앱을 만들고 바꾸는 길
- 채팅 라우터 `create_panel` 을 그대로 쓰되 설명을 넓힌다(“데이터를 등록·관리하는 앱(리드 관리, 휴가 일수 관리, 비품 대장…)도 여기”). 처리: `designPanelApp` → kind 가 `live` 면 기존 `generatePanel`, 아니면 `createPanelApp`. 진행 상태 알약은 '패널 설계하는 중' → '시트 만드는 중' → (끝) `null`.
- 새 라우터 도구 `panel_record {app, action: add|update|list, values, match, ack}`: "휴가 일수 관리에 김민지 15일 부여로 추가해줘". 시스템 메시지에 사용자가 쓸 수 있는 앱 이름과 항목 label 을 넣는다.
- 공유 폴더 채팅 경로(`folderFor`)보다 먼저: 말에 사용자가 쓸 수 있는 앱 이름이 들어 있으면 폴더 변형 작업으로 보내지 않는다(앱 폴더 이름이 앱 이름과 같기 때문).
- MCP `/mcp/panelapps`(호출자 JWT 기준): `panel_app_list`, `panel_app_create{description, folder?}`, `panel_app_rows{app}`, `panel_app_add_row{app, values}`, `panel_app_update_row{app, id, values}`. 테넌트 MCP `pgpt-panelapps` 로 등록해 deepagents·프로세스 단계가 같은 앱을 쓴다.

## 4. API
| 메서드 | 경로 | 권한 | 내용 |
| --- | --- | --- | --- |
| GET | `/api/panel-apps` | 로그인 | 내가 구성원인 폴더의 앱(숨김 제외), 각 앱의 내 권한 |
| POST | `/api/panel-apps` | 로그인 | `{description, folder?}` 설계·생성 |
| GET | `/api/panel-apps/:id/rows` | viewer | `{def, rows:[{_id,_v,…}], sha, role}` |
| POST | `/api/panel-apps/:id/rows` | editor | 행 추가 |
| PUT | `/api/panel-apps/:id/rows/:rid` | editor | `{values, _v}` 행 고치기(409) |
| DELETE | `/api/panel-apps/:id/rows/:rid` | editor | `?_v=` 행 지우기(409) |
| POST | `/api/panel-apps/:id/sheet` | viewer | 시트 편집기용 스토리지 사본 URL, 열 때 sha |
| POST | `/api/panel-apps/:id/sheet-saved` | editor | `{url, sha}` 편집본을 원본으로 |
| POST | `/api/panel-apps/:id/hide` | viewer | Home 에서 숨기기 |
| DELETE | `/api/panel-apps/:id` | owner | 앱 삭제(파일 지우기 커밋) |

## 5. 위험과 남은 것
- 이음오피스 시트 편집기가 저장할 때 숨은 열·데이터 유효성·수식을 보존하는지는 편집기 구현에 달려 있다. ID 열이 보이게 되어도 읽기는 머리글로 하므로 동작은 같다. 검증 결과는 tasks.md 에 적는다.
- 편집기를 연 채 패널에서 행을 더하면 편집기 저장이 409 로 거절된다(덮어쓰기로 행을 잃지 않기 위해). 셀 단위 병합은 다음 단계.
- 행 수 수천 개 이상, 여러 시트(관계형 테이블)는 범위 밖. 정의 형식(`sheet` 하나)만 열어 둔다.

---

# 2단계 — 저장 단계(tier)·이벤트 소싱·기본 보안 (2026-10-24 추가)

사용자 요구 세 가지를 한 모델로 묶었다.
1. 공유 앱에서 "누가 무엇을 건드릴 수 있나"(RLS)가 필요하면 Supabase 에 앱 전용 표를 만들고, 인증(JWT) 기반으로 **데이터베이스가** 권한을 지킨다.
2. 데이터는 엎어쓰지 않고 **이벤트로 쌓고**(휴가 부여·신청·취소), 요약은 replay 로 계산한다. 시트에는 이벤트 탭과 요약 탭.
3. 앱을 만들 때 **상식적인 보안·개인정보 기본값**이 저절로 들어간다(민감도 분류, 본인·관리자만, 외부인은 아무것도).

## 6. 두 종류(kind) × 두 저장 단계(tier)
| | sheet (공유 폴더 xlsx) | db (panel_data 스키마 + RLS) |
| --- | --- | --- |
| list (행) | 1단계 그대로: 구성원 = 전체 권한 | 행 단위 규칙 + 열 가림, 시트는 보는 사람별 사본 |
| events (기록) | 이벤트 탭(추가만) + 요약 탭(SUMIFS), 서버가 규칙 확인 | 추가만 되는 기록 표 + 가린 보기, replay 는 서버 |
- **단계 선택 규칙(안전한 쪽)**: 어떤 필드든 personal/sensitive 이거나 행 단위 규칙이 있으면 **db**. 공유 xlsx 는 그 파일을 열 수 있는 구성원에게 열을 숨길 수 없기 때문이다. 숨길 것이 없는 단순 앱(내 할일, 비품 입출고)만 sheet.
- db 앱의 정의 파일(`apps/<앱>.panel.json`)은 서버가 쓰는 버전 사본이다. 폴더에서 고쳐 올려도 규칙은 바뀌지 않는다(편집 권한자가 파일로 규칙을 느슨하게 만드는 길을 막음). 규칙은 소유자만 "권한 규칙" 시트·API 로 바꾼다.

## 7. 규칙 어휘와 컴파일
- 모델은 SQL 을 쓰지 않는다. 정의에 선언형 규칙만 쓴다: `access {read, create, update, delete}`, `fieldRules {key: {update}}`, 이벤트 종류별 `who`.
- 어휘(목록 = 또는, 모든 규칙은 폴더 구성원일 때만): `member`, `role>=viewer|runner|editor|owner`, `owner_of_row`(만든 사람; 이벤트는 by), `subject_is_me`(기록의 대상이 본인), `owner_of_ref`(이벤트: 원래 기록의 주인), `nobody`, `{field_is_me}`, `{field_equals: {field, value}}`, `{all: [...]}`(한 단계).
- 서버(`lib/panelApps/rules.js`)가 검증하고 고정 템플릿으로 컴파일한다: 표 이름은 앱 id 에서(`panel_data.app_<16hex>`), 열은 `c_<key>`(key 는 `^[a-z][a-z0-9_]{0,30}$`, 아니면 거절), 상수는 형식 검사 뒤 따옴표를 두 번 쓴 리터럴(`standard_conforming_strings`), 폴더 id 는 uuid 검사. 모델 출력은 관대하게(틀린 목록 → 기본값), 소유자 편집은 엄격하게(하나라도 틀리면 거절).
- 생성물: 표(표준 열 id·created_by·created_at·updated_at·updated_by + 형식별 열, choice 는 CHECK), RLS 정책 4개(`pa_read/create/update/delete`), 가드 트리거(작성자·시각 위조 불가, fieldRules 위반 시 `42501 panel_field_denied:<key>`), 열 권한(제한 열은 표에서 select 권한 없음), **가린 보기** `app_<id>_v`(읽기 규칙을 다시 적용하고 제한 값은 읽을 수 있는 사람에게만, `_hidden` 에 가린 열 이름).
- `panel_data.folder_role(folder)`(security definer)가 pgpt-pro 폴더 구성원 표를 읽어 등급(0~4)을 돌려준다. `authenticated` 에 실행만 허용, anon 은 스키마 사용도 없음.
- 사람의 읽기·쓰기는 서버 pg 연결에서 `set local role authenticated` + `request.jwt.claims`(검증된 그 사람의 JWT 클레임)로 실행한다 — PostgREST 와 같은 방식이라 RLS 가 그대로 적용된다. 표 생성·변경, 시트→db 첫 가져오기만 소유자 연결.
- PostgREST 노출: 로컬 Supabase(PostgREST v12)에 `alter role authenticator set pgrst.db_schemas = 'public,storage,graphql_public,panel_data'` + `notify pgrst, 'reload config'`(설정 파일·컨테이너는 그대로). DDL 뒤에는 `notify pgrst, 'reload schema'`. 앱 표를 사용자 JWT 로 바로 불러도 같은 규칙이 적용됨을 통합 시험으로 확인.

## 8. 이벤트 소싱
- 정의: `entity`(기록의 대상, person|text), `fields`(내용 항목 목록), `events[{type, label, fields, required, who, ref{types, mode: cancel|close, inherit}}]`, `projections`, `views.main`.
- 봉투(envelope): `id, seq, at, by, type, entity, ref` + 내용. 추가만 된다 — 수정·삭제는 없고, 바로잡기는 `ref` 로 원래 기록을 가리키는 새 기록(취소·정정). 취소는 원래 기록의 `entity` 와 `inherit` 항목(예: 일수)을 물려받는다.
- 투영(projection) 어휘(코드 없음): `balance`(대상별 `sum|count|min|max` × 부호, 계산 열 식), `open`(닫히지 않은 기록 목록, closedBy 종류), `latest`(대상별 마지막 값). replay 는 seq 순서로 결정적이며, 취소는 별도 제외 없이 부호로 계산한다(사용 = Σ신청 − Σ취소) — 시트의 SUMIFS 와 같은 식.
- sheet 단계: xlsx 에 `이벤트` 탭(머리글 = 봉투 + 내용, 사람은 이름으로) + 투영마다 탭. balance 탭은 `SUMIFS('이벤트'!G:G,'이벤트'!D:D,"휴가 신청",'이벤트'!E:E,$A2)-SUMIFS(…"휴가 취소"…)` 수식과 계산값을 함께 써서, 이음오피스에서 줄을 더해도 숫자가 맞는다. 서버 replay 가 원본이고 저장 때마다 탭을 다시 만든다.
- 이음오피스 저장: `이벤트` 탭을 id 로 비교 — 맨 아래 새 줄은 저장한 사람의 기록으로 추가(같은 권한 검사), **기존 줄을 고치거나 지운 것은 적용하지 않고 거절 목록으로 알린다**(자동 보정 기록을 만들지 않음 — 의도가 모호하므로). sheet 단계는 서버가 파일을 기록에서 다시 써서 되돌린다.
- db 단계: 기록 표에는 INSERT 정책만(종류별 `who`), UPDATE/DELETE 는 정책·권한이 없고 트리거도 `panel_append_only` 로 거절(소유자 연결 포함). 트리거(security definer)가 id·at·by 를 채우고, ref 의 종류·닫힘(`panel_ref_closed`)을 검사하고 물려받기를 복사한다. 투영은 그 사람의 가린 보기 기록을 서버가 replay(읽기 규칙이 자동 적용).
- 쓰기 기본값: 대상에 관한 기록은 본인만(`subject_is_me`) 또는 편집 권한 이상, 관리자 기록(부여·승인, `manager`)은 편집 권한 이상, 취소·정정은 원래 기록의 주인 또는 폴더 소유자.
- 목록 앱 → 기록 앱 전환: 선언형 대응표 `{entity, events[{type, from{payload: oldKey}}]}` 로 행마다 기록을 만들고(0·빈 값은 건너뜀), 작성자는 행의 작성자(없으면 앱 소유자), `_migrated` 표시.

## 9. 기본 보안·개인정보
- **민감도**: 필드마다 `public | internal | personal | sensitive`. 모델이 제안하고 서버가 결정적 하한을 적용(낮출 수 없음): 급여·연봉·평가·건강·병가·사유·주민·계좌·가족·징계 → sensitive, 연락처·이메일·주소·생년월일·사번·email/phone 형식·대상이 아닌 person → personal, 대상이 있는 기록의 메모·사유·긴 글 → 최소 personal. 기록의 대상(person 항목/entity) 자체는 internal(누구의 기록인지는 팀 앱이 보여야 함).
- **읽기 기본값**: public/internal = 구성원 모두, personal = 대상 본인·기록한 사람·폴더 소유자, sensitive = 대상 본인·폴더 소유자(대상이 없으면 기록한 사람). 다른 구성원에게는 행은 보이고 그 값은 '비공개'.
- **합계(k-익명)**: 제한 항목을 더하는 balance 열은 대상별 값을 본인·소유자에게만, 팀 합계는 서버가 전체 기록으로 계산해 대상이 3명 이상일 때만 보인다.
- **외부인**: 앱 목록·데이터·건수·MCP 결과 모두 없음(폴더 권한 403 + RLS 0행).
- **생성 직후 검토**: 앱은 `privacy_ack=false` 로 만들어지고, 소유자 Home 패널 위에 "보안·개인정보 기본값" 카드(누가 무엇을, 어떤 항목이 누구에게 왜 가려지는지)가 뜬다. 확인 전에는 패널에서 공유를 열 수 없다. "조정" = 권한 규칙 시트. 민감도를 낮추면(personal/sensitive → 아래) 확인을 받고 감사 기록에 남긴다.
- **모든 통로 같은 규칙**: 패널 API·채팅 답·MCP 도구는 그 사람 권한으로만(서비스 키 아님), 시트 보기는 그 사람이 읽을 수 있는 것만 담긴 사본(추측 불가 키), 폴더 스냅샷은 "평범한 구성원이 볼 수 있는 행 + 제한 값은 '비공개'" 만 폴더에 쓰므로 폴더 색인(문서 카드)·검색에 민감 값이 들어가지 않는다. 알림은 이번 범위에서 보내지 않는다.
- **감사**: `pro_panel_app_audit` — 규칙 변경(rules), 민감도 낮춤(loosen)·변경, 관리자의 민감 항목 열람(read_sensitive, 사람·앱별 10분에 한 번), 스냅샷, 기본값 확인, 전환.

## 10. 남은 것·위험
- 시트 보기 사본은 공개 버킷에 추측 불가 키로 올라간다(이음오피스가 스토리지 URL 로만 연다). 서명 URL 로 바꾸는 것은 이음오피스 호스트 쪽 변경이 필요.
- 폴더 소유자도 다른 사람의 비공개 행(읽기 규칙 밖)은 볼 수 없다 — 의도한 동작이지만 "관리자는 모두 본다"를 원하면 read 에 `role>=owner` 를 더하면 된다.
- 채팅으로 규칙을 바꾸는 길("이제 각자 자기 것만 고치게")은 화면(권한 규칙 시트 → 행 단위 권한 켜기)과 API 로 구현했고, 채팅 라우터 도구는 다음 단계.
- sheet 단계 이벤트 앱의 권한은 서버 코드가 확인한다(폴더 파일은 편집 권한자가 직접 고칠 수 있으므로, 숨길 것이 없는 앱에만 허용).
