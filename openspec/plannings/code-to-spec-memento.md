# Code To Spec 계획: memento 마이크로서비스

## 입력 범위
- 소스 폴더:
  - `services/memento` (FastAPI 기반 멀티테넌트 문서 처리/검색(RAG) 서비스, 기본 포트 `8005`)
- 제외 범위:
  - `services/memento/benchmark/`: 검색 품질 측정용 개발 벤치마크 스크립트. 외부 클라이언트 계약이 아니므로 제외한다.
  - `services/memento/scripts/inspect_chroma.py`: 운영자/개발자용 일회성 Chroma 점검 CLI. 공개 계약이 아니므로 제외한다.
  - `services/memento/vendor/extract_hwp`: 외부에서 가져온 HWP 추출 라이브러리. 제품 계약이 아니라 의존성이므로 제외한다.
  - `GET /debug/memory`: 운영자 진단용 메모리 스냅샷 엔드포인트. 제품 사용자/클라이언트 계약이 아니므로 스펙으로 만들지 않고 열린 질문으로만 남긴다.
  - `app/converters/*`, `app/plugins/*` 내부 파서/청커/리트리버 구현: 사용자가 직접 호출하지 않는 구현 세부이므로 스펙 대상이 아니다. 단 관찰 가능한 결과(지원 파일 형식, 검색 전략 설정)는 관련 피쳐 스펙에 행위 계약으로 반영한다.

## 분석 기준
- 스펙은 구현 요약이 아니라 외부에서 관측 가능한 행위 계약으로 작성한다.
- 내부 함수명, 클래스명, private helper, 모듈 경로, 파일 경로, 라인 번호는 스펙에 쓰지 않는다.
- Purpose, Requirement 제목, Requirement 본문, Scenario 제목, Scenario 단계는 한국어로 작성한다.
- `### Requirement:`와 `#### Scenario:` 접두어는 유지하되, 그 뒤의 이름은 한국어로 작성한다.
- 공개 API 경로, HTTP method, 요청/응답 필드명, 이벤트명, 설정 키, enum 값은 계약인 경우에만 원문을 유지한다.
- main spec은 마이크로서비스 전체가 아니라 하나의 피쳐 단위로 작성한다.
- `services/memento` 입력이므로 모든 스펙 ID는 `memento` 접두어로 시작한다.
- 이 서비스는 "문서 처리/지식 검색(RAG)"이라는 단일 업무 도메인에 집중되어 있고 서비스명이 별도 도메인을 분기하지 않으므로 `<microservice>_<domain>-<feature>`가 아니라 `<microservice>-<feature>` 형식을 사용한다.
- 서비스 내부에서 발견한 외부 시스템명(Google Drive, Supabase, Chroma, litellm, robo 용어집 등)이나 프로토콜명은 `memento` 접두어를 대체하지 않는다.
- `frontend`, `ui`, `react`, `page`, `component`는 서비스 접두어 또는 도메인 구분자로 쓰지 않는다.

## 제안 스펙 분할

### `memento-drive-folder-indexing`
- Service prefix: `memento` (`services/memento` 마이크로서비스 폴더명)
- Domain discriminator: 없음 (서비스가 단일 도메인이므로 도메인 구분자 생략)
- Naming 결정 근거: `services/memento` 마이크로서비스 입력이므로 접두어를 `memento`로 고정하고, Drive 폴더 일괄 인덱싱 피쳐를 `drive-folder-indexing`으로 둔다.
- Feature: `drive-folder-indexing` (테넌트 Google Drive 폴더의 문서를 비동기 잡으로 일괄 인덱싱)
- 목적: 운영자/클라이언트가 테넌트의 Google Drive 폴더 전체를 검색 인덱스로 가져오고, 신규 파일만 처리하며, 진행 상태를 폴링으로 확인하는 피쳐.
- E2E 단위 판단: 인덱싱 시작 요청(`202` + `job_id`) → 상태 폴링(`running` → `completed`)을 하나의 사용자 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /process` (`storage_type=drive`): 폴더 모드는 `202`와 `{job_id, message}`, 인증 실패 시 `401`과 로그인 URL 응답
  - `POST /process` (`storage_type=drive`, `file_path` 지정): 단일 Drive 파일 동기 처리
  - `GET /process/drive/status?tenant_id=`: `{job_id, status, total, processed, failed, results, error}` 또는 `{status: "idle"}`
  - 영속화: 발견 파일은 `knowledge_files`에 `index_status` 단계(`pending`/`processing`/`indexed`/`failed`)로 동기화, 성공 파일은 `processed_files`에 기록
- 포함 유즈 케이스:
  - Drive 폴더 재귀 나열 후 미처리 신규 파일만 비동기 인덱싱
  - 인덱싱 잡 진행률(총계/처리/실패/파일별 결과) 폴링
  - 이미 처리된 파일은 재처리 없이 `indexed` 상태로 보정
  - 단일 Drive 파일 ID 지정 처리와 중복 처리 회피
- 주요 관측 계약:
  - 인증 미보유 시 `401` + `auth_url` 포함 표준 인증 오류 응답
  - 신규 파일이 없으면 처리 없이 안내 메시지 반환
  - 잡 상태는 완료/실패 후 일정 시간 동안만 조회 가능(TTL)하고 그 뒤 `idle`로 응답
  - 테넌트별 활성 잡은 최대 1개로 추적
- 다른 spec으로 분리할 범위:
  - `memento-document-ingestion`: 로컬/스토리지/DB 소스의 동기 인제스트는 별도 피쳐
  - `memento-google-drive-integration`: Drive OAuth 인증 자체는 별도 피쳐
- 제외할 구현 세부:
  - in-memory 잡 딕셔너리 구조, 백그라운드 태스크 생성 방식
- frontend evidence:
  - Drive 동기화 시작 버튼, 인덱싱 진행률 표시, 파일별 성공/실패 목록 화면
- 근거 유형:
  - routes, README API 예시, `knowledge_files`/`processed_files` 영속화, 잡 상태 응답
- 위험 또는 열린 질문:
  - 잡 상태가 in-memory라서 서비스 재시작 시 유실되는 동작이 의도된 계약인지 불명확

### `memento-document-ingestion`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 다양한 소스의 문서를 동기적으로 추출·청킹·임베딩해 검색 인덱스에 적재하는 피쳐.
- Feature: `document-ingestion` (파일/스토리지/DB 레코드를 검색 가능한 청크로 인제스트)
- 목적: 클라이언트가 파일을 업로드하거나 기존 스토리지 파일·DB 레코드를 지정하면, 시스템이 콘텐츠를 추출·청킹·임베딩해 검색 인덱스와 원문 저장소에 적재하는 피쳐.
- E2E 단위 판단: 파일 업로드(`/save-to-storage`) → 처리 성공 응답 → 이후 검색에서 청크 조회 가능을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /save-to-storage` (multipart): 업로드 + 추출 + 저장, `{message, file_path, file_name, public_url, processed}`
  - `POST /process` (`storage_type=local|storage`): 로컬 디렉토리/스토리지 파일 처리
  - `POST /process/database`: `todolist` 레코드를 문서로 변환해 적재
  - 영속화: 원문 청크는 Supabase `documents`, 검색 인덱스는 Chroma, 처리 완료 파일은 `processed_files`
- 포함 유즈 케이스:
  - PDF/DOCX/PPTX/XLSX/TXT/HWP/HWPX 텍스트 추출과 청킹
  - 이미지 파일(JPG/PNG/GIF/BMP/WEBP) 단일 이미지 문서 처리
  - 문서 내 이미지 추출 및 Vision 분석 텍스트 병합
  - `proc_inst_id`/`room_id` 옵션에 따른 `knowledge_scope`(`room`/`global`) 메타 부여
  - 콘텐츠가 추출되지 않은 경우의 부분 성공/실패 응답
- 주요 관측 계약:
  - 지원하지 않는 파일이거나 콘텐츠가 없으면 `processed=false`로 업로드 결과만 반환
  - 문서 적재 성공 시에만 `processed_files`에 기록
  - 입력 디렉토리 부재 시 `404`
  - 임베딩 차원/스키마 제약 우회 동작은 설정(`SUPABASE_WRITE_EMBEDDING`, `SUPABASE_DUMMY_EMBEDDING_DIMENSIONS`)으로 제어
- 다른 spec으로 분리할 범위:
  - `memento-drive-folder-indexing`: Drive 폴더 비동기 인덱싱
  - `memento-knowledge-file-management`: 설정 페이지의 내부 지식공간 파일 관리(폴더/권한/목록)
  - `memento-similarity-search`: 적재된 청크의 검색/조회
- 제외할 구현 세부:
  - 청커/파서 플러그인 선택 로직, 임시 파일 처리, 배치 크기 상수
- frontend evidence:
  - 파일 업로드 버튼, 업로드 진행/완료 표시, 처리 실패 안내
- 근거 유형:
  - routes, README 지원 파일 형식 표, `documents`/`processed_files` 영속화, 응답 메시지
- 위험 또는 열린 질문:
  - `/process` `storage_type=local`은 서버 파일 시스템 경로를 받으므로 외부 클라이언트용 계약인지 운영자용인지 불명확

### `memento-knowledge-file-management`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 설정 페이지에서 테넌트의 내부 지식공간 파일과 폴더를 직접 관리하는 피쳐.
- Feature: `knowledge-file-management` (내부 지식공간 파일/폴더 업로드·조회·삭제·이동)
- 목적: 사용자/관리자가 설정 화면에서 지식공간 파일을 직접 업로드하고, 목록·중복을 확인하고, 폴더를 만들고 이름을 바꾸고, 권한에 따라 파일/폴더를 삭제하는 피쳐.
- E2E 단위 판단: 해시 사전 확인 → 업로드 → 목록 조회 → 폴더 생성/이름변경 → 권한별 삭제를 하나의 관리 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /knowledge/files/upload` (multipart): `{source_type, source_ref, file_name, size_bytes, public_url, indexed, error}`
  - `GET /knowledge/files/check-hash`: `{exists, existing}`
  - `GET /knowledge/files/url`: 보기/다운로드 URL 반환
  - `DELETE /knowledge/files`: 권한 검사 후 인덱스+스토리지+메타 완전 제거
  - `GET/POST /knowledge/folders`, `POST /knowledge/folders/rename`, `DELETE /knowledge/folders`
  - `GET /documents/list`: 테넌트 파일 목록(`files`, `file_details`, `total`)
  - 영속화: `knowledge_files`(파일 메타/인덱싱 상태), `knowledge_folders`(빈 폴더 포함)
- 포함 유즈 케이스:
  - 업로드 직전 SHA-256 해시로 동일 테넌트 내 중복 파일 감지
  - 업로드 후 RAG 인덱싱과 인덱싱 상태(`indexed`/`failed`) 표시
  - 빈 폴더 생성, 폴더 이름 변경 시 하위 경로 일괄 갱신
  - 파일/폴더 삭제 시 관리자/소유자 권한 검사
  - picker용 파일 목록과 확장 메타(소스 타입, 인덱싱 상태, 업로더) 제공
- 주요 관측 계약:
  - 일반 사용자는 본인이 업로드한 `upload` 파일만 삭제 가능, `drive` 항목과 타인 파일은 `403`
  - 폴더 이름변경/삭제는 관리자만 가능(`is_admin=false`이면 `403`)
  - 클라이언트가 보낸 해시는 신뢰하지 않고 서버에서 재계산해 저장
  - 잘못된 `source_type`/빈 `folder_path`는 `400`
- 다른 spec으로 분리할 범위:
  - `memento-document-ingestion`: 콘텐츠 추출·청킹·임베딩 메커니즘 자체
  - `memento-drive-folder-indexing`: Drive 소스 파일의 인덱싱 상태 생성
- 제외할 구현 세부:
  - storage 경로 sanitize 알고리즘, 테이블 upsert 2단계 처리
- frontend evidence:
  - 설정 페이지 파일 업로드/목록/삭제 UI, 폴더 트리, 중복 업로드 경고
- 근거 유형:
  - routes, `knowledge_files`/`knowledge_folders` 영속화, 권한 분기, 응답 필드
- 위험 또는 열린 질문:
  - 권한이 `is_admin`/`requester_uid` 쿼리 파라미터로만 전달되어 서버측 인증과 분리된 점이 의도된 계약인지 불명확

### `memento-similarity-search`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 적재된 문서 청크를 유사도 검색하거나 직접 조회하는 피쳐.
- Feature: `similarity-search` (벡터 유사도 검색 및 청크 조회)
- 목적: 클라이언트가 질의로 관련 청크를 검색하거나, 파일/인덱스 기준으로 청크를 직접 조회해 컨텍스트를 확보하는 피쳐.
- E2E 단위 판단: 문서 적재 후 `/search`/`/retrieve`로 청크를 찾고, `/documents/chunks-*`로 특정 청크를 조회하는 흐름을 하나의 suite로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /search`: 엄격한 top_k 벡터 검색, `{response: [...]}`
  - `GET /retrieve`: 파일/방/프로세스 범위 분기 + 용어집 병합 검색
  - `GET /retrieve-images`: 캡션 기반 이미지 검색, `{images: [...]}`
  - `POST /retrieve-by-indices`: `chunk_index` 목록으로 청크 직접 조회
  - `GET /documents/chunks-metadata`, `/documents/chunks-by-file-path`, `/documents/chunks-by-file-name`, `/documents/chunks-with-embeddings`
- 포함 유즈 케이스:
  - 테넌트 격리된 top_k 유사도 검색과 파일 ID 좁힘(`$in`)
  - 이미 본 청크 제외(`exclude_chunk_ids`) 후 top_k 보장
  - 작은 문서는 전체 청크 통째 반환, 큰 문서는 RAG top_k
  - 방(`room_id`)/프로세스(`proc_inst_id`)/전체 범위 검색과 글로벌 지식 우선 병합
  - 다운스트림 에이전트용 청크 + 임베딩 동시 반환
- 주요 관측 계약:
  - `query`/`tenant_id` 누락 시 `400`
  - `top_k`는 엔드포인트별 허용 범위로 제한
  - `image_analysis` 타입 청크는 일반 청크 조회에서 제외
  - 검색 전략(`plain`/`multi_query`/`hyde`/`rag_fusion`/`rewrite`)은 설정으로 전환 가능
- 다른 spec으로 분리할 범위:
  - `memento-rag-query-answering`: LLM이 최종 답변을 생성하는 질의응답
  - `memento-document-ingestion`: 검색 대상 청크의 적재
- 제외할 구현 세부:
  - Chroma where 절 변환, NFC 정규화, dedup 키 구성
- frontend evidence:
  - 검색 입력창, 결과 청크/이미지 목록, 파일 선택 picker
- 근거 유형:
  - routes, 코드 주석에 명시된 검색 시맨틱, 응답 필드
- 위험 또는 열린 질문:
  - `/retrieve`의 file_ids 미지정·room 미지정 시 기본 필터가 `source_type=process_output`로 좁혀지는 동작이 일반 검색 기대와 다를 수 있음

### `memento-rag-query-answering`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 검색 컨텍스트로 LLM 답변을 생성하는 질의응답 피쳐.
- Feature: `rag-query-answering` (RAG 기반 질문 답변과 출처 반환)
- 목적: 클라이언트가 자연어 질문을 보내면 시스템이 관련 문서를 검색해 LLM으로 답변을 생성하고, 답변과 출처 메타데이터를 함께 반환하는 피쳐.
- E2E 단위 판단: 문서 적재 후 `/query`로 질문 → 답변 + 출처 반환을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /query?query=&tenant_id=`: `{response, metadata}` — `metadata`는 `파일명#청크인덱스` 키별 출처 메타
  - 검색은 테넌트 격리(`tenant_id` 필터)
- 포함 유즈 케이스:
  - 질문 언어 감지에 따른 한국어/영어 답변
  - 관련 문서가 없을 때의 "정보 없음" 안내 답변
  - 답변과 함께 출처 문서 메타데이터 반환
- 주요 관측 계약:
  - 검색 결과가 비면 답변을 지어내지 않고 정보 부족 안내를 반환
  - 처리 중 오류 시 오류 안내 답변 또는 `500`
  - 답변은 테넌트 범위 문서만 컨텍스트로 사용
- 다른 spec으로 분리할 범위:
  - `memento-similarity-search`: 청크만 반환하는 검색
- 제외할 구현 세부:
  - 프롬프트 템플릿 문자열, 컨텍스트 포맷팅 방식
- frontend evidence:
  - 질문 입력창, 답변 표시, 출처 문서 링크
- 근거 유형:
  - routes, README 질의 예시, 응답 필드
- 위험 또는 열린 질문:
  - 없음

### `memento-google-drive-integration`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 테넌트 단위 Google Drive OAuth 인증과 Drive 업로드 피쳐.
- Feature: `google-drive-integration` (테넌트 Google OAuth 인증과 Drive 파일 업로드)
- 목적: 테넌트가 Google OAuth로 Drive 접근을 인가하고, 인가된 자격으로 파일을 Drive에 업로드하는 피쳐.
- E2E 단위 판단: 인가 URL 발급 → 콜백으로 토큰 교환·저장 → 인증 상태 확인 → Drive 업로드를 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /auth/google/url?tenant_id=`: `{auth_url, state}`
  - `GET /auth/google/status?tenant_id=`: `{authenticated, ...}`
  - `POST /auth/google/save-token`, `POST /auth/google/callback`
  - `POST /save-to-drive` (multipart): Drive 업로드, 인증 미보유 시 `401` + 로그인 URL
  - 영속화: `tenant_oauth`(`google_credentials`, `google_credentials_updated_at`)
- 포함 유즈 케이스:
  - 테넌트 OAuth 설정 기반 인가 URL 생성
  - 인가 코드 → 토큰 교환 후 테넌트 자격 저장
  - 토큰 만료 여부 포함 인증 상태 조회
  - 인가된 자격으로 지정 폴더에 파일 업로드
- 주요 관측 계약:
  - 테넌트 OAuth 설정이 없으면 `404`
  - 토큰이 만료되면 `authenticated=false`
  - 코드 교환 실패 시 `400`
  - 인증 미보유 상태로 업로드 시 `401` + `auth_url` 포함 응답
- 다른 spec으로 분리할 범위:
  - `memento-drive-folder-indexing`: 인증 후 Drive 폴더 인덱싱
  - `memento-workitem-output-publishing`: 산출물 생성 후 Drive 업로드는 별도 피쳐
- 제외할 구현 세부:
  - 토큰 JSON 직렬화 형태, OAuth scope 상수 목록
- frontend evidence:
  - "Google 연결" 버튼, 인증 상태 배지, Drive 업로드 동작
- 근거 유형:
  - routes, README 인증 API, `tenant_oauth` 영속화, 표준 인증 오류 응답
- 위험 또는 열린 질문:
  - 없음

### `memento-workitem-output-publishing`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, 워크아이템 산출물을 문서로 생성·발행하는 피쳐.
- Feature: `workitem-output-publishing` (워크아이템 폼 산출물 DOCX 생성·Drive 업로드·RAG 적재)
- 목적: 클라이언트가 워크아이템을 지정하면 시스템이 폼 산출물을 DOCX로 변환해 Google Drive에 업로드하고, 같은 산출물을 검색 인덱스에도 적재하는 피쳐.
- E2E 단위 판단: 워크아이템 지정 → DOCX 생성·업로드 → 업로드 결과 + 검색 적재 확인을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `POST /process-output`: `{message, uploaded, folder_path}` — `uploaded`는 Drive 업로드 메타 목록
  - 입력 데이터: `todolist`(워크아이템 산출물), `form_def`(폼 정의)
  - 영속화: `todolist.output_url` 갱신, RAG 인덱스 적재 후 `processed_files` 기록
- 포함 유즈 케이스:
  - 폼 정의의 `report`/`slide` 필드를 마크다운 → DOCX로 변환
  - report/slide 필드가 없으면 폼 HTML 전체를 DOCX로 변환
  - 생성 문서를 날짜/프로세스 기준 폴더 경로에 업로드
  - 업로드한 산출물을 청킹·임베딩해 검색 인덱스에 적재
- 주요 관측 계약:
  - 워크아이템이 없으면 `404`
  - 업로드된 문서의 web view link를 `todolist.output_url`로 기록
  - 산출물 청크 메타에 `source_type=process_output`, `workitem_id`, `activity_name` 부여
  - 처리 실패 시 `500`
- 다른 spec으로 분리할 범위:
  - `memento-google-drive-integration`: Drive 인증 자체
  - `memento-document-ingestion`: 일반 파일 인제스트
- 제외할 구현 세부:
  - 마크다운→DOCX 변환기 내부, 폼 필드 순회 로직
- frontend evidence:
  - 워크아이템 완료/산출물 생성 버튼, 생성된 문서 링크
- 근거 유형:
  - routes, README API, `todolist`/`form_def` 데이터 계약, 응답 필드
- 위험 또는 열린 질문:
  - report/slide 산출물이 여러 개일 때 `output_url`이 갱신되지 않는 동작이 의도된 것인지 불명확

### `memento-pdf-highlight-preview`
- Service prefix: `memento`
- Domain discriminator: 없음
- Naming 결정 근거: `services/memento` 입력, PDF 페이지의 특정 영역을 하이라이트한 미리보기 이미지를 제공하는 피쳐.
- Feature: `pdf-highlight-preview` (PDF 페이지 bbox 하이라이트 PNG 렌더링·캐시)
- 목적: 클라이언트가 PDF 파일·페이지·영역(bbox)을 지정하면 시스템이 해당 페이지를 하이라이트한 PNG로 렌더링하고, 캐시된 공개 URL을 반환하는 피쳐.
- E2E 단위 판단: 하이라이트 요청 → PNG URL(`cached=false`) → 동일 요청 재호출 시 캐시 응답(`cached=true`)을 하나의 흐름으로 검증할 수 있다.
- 백엔드/제품 계약 연결:
  - `GET /preview/pdf-highlight?tenant_id=&file_id=&page=&bbox=&dpi=`: `{url, cache_key, page, width, height, cached}`
  - 영속화: 렌더링 결과 PNG를 스토리지에 캐시
- 포함 유즈 케이스:
  - 지정 페이지에 bbox 영역 하이라이트 후 PNG 렌더링
  - 동일 입력에 대한 캐시 적중 시 재렌더링 없이 URL 반환
- 주요 관측 계약:
  - 잘못된 `bbox` 형식이나 빈 `file_id`는 `400`
  - 스토리지에 PDF가 없으면 `404`
  - 페이지 범위를 벗어나면 `400`
  - 캐시 키는 파일/페이지/bbox/dpi 조합으로 결정
- 다른 spec으로 분리할 범위:
  - 없음
- 제외할 구현 세부:
  - PNG 렌더링 라이브러리, 캐시 키 해시 알고리즘
- frontend evidence:
  - 검색 결과의 출처 미리보기, 하이라이트된 PDF 영역 이미지
- 근거 유형:
  - routes, 응답 필드, 스토리지 캐시 동작
- 위험 또는 열린 질문:
  - 없음

## 추적표

| 소스 범위 | 관측된 외부 행위 | 백엔드/제품 계약 | Service prefix | Domain discriminator | Feature | 제안 스펙 폴더 | E2E 단위 | 처리 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `POST /process`(drive), `GET /process/drive/status` | Drive 폴더 비동기 인덱싱과 진행 폴링 | 인덱싱 잡 상태 API, `knowledge_files`/`processed_files` | `memento` | 없음 | `drive-folder-indexing` | `memento-drive-folder-indexing` | 적절 | 포함 |
| `POST /save-to-storage`, `POST /process`(local/storage), `POST /process/database` | 파일/스토리지/DB 콘텐츠 추출·청킹·임베딩 적재 | 인제스트 API, `documents`/`processed_files` | `memento` | 없음 | `document-ingestion` | `memento-document-ingestion` | 적절 | 포함 |
| `/knowledge/files/*`, `/knowledge/folders/*`, `GET /documents/list` | 지식공간 파일/폴더 업로드·조회·삭제·권한 | 지식공간 관리 API, `knowledge_files`/`knowledge_folders` | `memento` | 없음 | `knowledge-file-management` | `memento-knowledge-file-management` | 적절 | 포함 |
| `GET /search`, `/retrieve`, `/retrieve-images`, `POST /retrieve-by-indices`, `/documents/chunks-*` | 벡터 유사도 검색 및 청크 조회 | 검색/조회 API | `memento` | 없음 | `similarity-search` | `memento-similarity-search` | 적절 | 포함 |
| `GET /query` | RAG 기반 답변 + 출처 반환 | 질의응답 API | `memento` | 없음 | `rag-query-answering` | `memento-rag-query-answering` | 적절 | 포함 |
| `/auth/google/*`, `POST /save-to-drive` | Google OAuth 인증과 Drive 업로드 | 인증/업로드 API, `tenant_oauth` | `memento` | 없음 | `google-drive-integration` | `memento-google-drive-integration` | 적절 | 포함 |
| `POST /process-output` | 워크아이템 산출물 DOCX 생성·발행 | 산출물 발행 API, `todolist`/`form_def` | `memento` | 없음 | `workitem-output-publishing` | `memento-workitem-output-publishing` | 적절 | 포함 |
| `GET /preview/pdf-highlight` | PDF 페이지 하이라이트 PNG 렌더링·캐시 | 미리보기 API, 스토리지 캐시 | `memento` | 없음 | `pdf-highlight-preview` | `memento-pdf-highlight-preview` | 적절 | 포함 |
| `GET /debug/memory` | 운영자 메모리 진단 스냅샷 | 진단 API | `memento` | 없음 | - | - | - | 제외(운영자 진단, 제품 계약 아님) |
| `benchmark/`, `scripts/`, `vendor/` | 개발 벤치마크·점검 CLI·외부 라이브러리 | 없음 | - | - | - | - | - | 제외(공개 계약 아님) |

## 진행 체크리스트
- [x] 모든 입력 폴더가 확인되었다.
- [x] 각 스펙 폴더가 `<microservice>_<domain>-<feature>` 또는 `<microservice>-<feature>` 형식을 따른다.
- [x] 마이크로서비스/서비스 폴더 입력에서 생성된 모든 스펙 ID가 해당 서비스 폴더명(`memento`)으로 시작한다.
- [x] 단일 도메인 서비스이므로 도메인 구분자를 중복 추가하지 않았다.
- [x] 서비스 접두어가 백엔드/제품 기능 경계이며 `frontend`, `ui`, `react`, `page`, `component`가 아니다.
- [x] 스펙 폴더가 구현 구조가 아니라 피쳐 기준으로 나뉘었다.
- [x] 프론트엔드 입력은 없으며, 프론트엔드 단독 스펙을 생성하지 않았다.
- [x] 어떤 스펙도 마이크로서비스 전체, route inventory, controller/service/repository 계층을 요약하지 않는다.
- [x] 각 스펙 폴더의 유즈 케이스가 하나의 E2E suite로 자연스럽게 검증 가능한 범위다.
- [x] 불확실한 행위가 요구사항으로 단정되지 않고 열린 질문으로 남았다.
- [x] `openspec/specs` 작성 전에 이 계획이 저장되었다.
