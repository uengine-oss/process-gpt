# E2E 시나리오 01: 자연어 프로세스 데이터 조회 성공 (백엔드 계약 전용)

## 메타데이터
- 스위트 슬러그: `completion_process-data-query`
- 원본 명세 ID: `completion_process-data-query`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `01 자연어 프로세스 데이터 조회가 HTML table 문자열을 반환한다 (protocol-only)`
- 원본 명세:
  - `openspec/specs/completion_process-data-query/spec.md`
- 분류: **백엔드 계약 전용 / 사용자-액션 면제**

## 목적
`POST /process-data-query`가 `{input:{query, user_id, chat_room_id}}` 입력에 대해 HTML `<table>` 문자열 본문을 반환하는 백엔드 계약을 보장한다. 본 시나리오는 사용자가 직접 화면에서 같은 결과를 보는 경로를 검증하지는 않으며, 그에 대한 면제 사유는 아래 "사용자-액션 면제 근거" 참고.

## 사용자-액션 면제 근거
- 본 라우트의 자연어 `{query, user_id, chat_room_id}` 형태를 트리거하는 유일한 실 프런트엔드 경로는 [services/frontend/src/views/apps/chat/Chats.vue:1359](services/frontend/src/views/apps/chat/Chats.vue#L1359)으로, **시스템 채팅 룸**에서 채팅 백엔드(chat orchestrator)가 `responseObj.work === 'CompanyQuery'` 인텐트를 반환할 때만 호출된다.
- 이 경로를 결정적으로 도달하려면 (a) 시스템 챗 룸 생성 + (b) 채팅 오케스트레이션 백엔드 가동 + (c) intent 분류 LLM의 결정적 응답 mocking이 모두 필요하며, 본 스펙 범위 바깥의 서비스 다수를 끌어들이게 된다.
- [services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue:194](services/frontend/src/components/designer/bpmnModeling/bpmn/mapper/ProcessVariable.vue#L194) `testSql()` 도 `/completion/process-data-query/invoke`를 호출하나, `{var_name}` 만 보내고 본 요구사항이 정의하는 `{query, user_id, chat_room_id}` 입력을 형성하지 않아 자연어 조회 계약을 실증할 수 없다.
- 사용자가 명시적으로 "실제 UI 경로가 없으면 백엔드 계약 전용으로 분류 후 면제 표기"를 지시했으므로, 본 시나리오는 protocol-only로 분류하고 직접 HTTP 호출로 라우트 계약만 검증한다.
- **승격 조건**: 향후 자연어 조회를 노출하는 전용 UI 표면(예: 채팅 인텐트와 무관하게 표를 그릴 수 있는 위젯)이 추가되면, 본 시나리오를 사용자-액션 시나리오로 다시 승격해야 한다.

## 사전 조건
- frontend(SPA 이미지) + gateway(nginx :8088) + completion(FastAPI :8000) + Supabase(db, kong, auth, rest) + mock-llm-pdq 컨테이너 정상 기동
- DB seed: `localhost` 테넌트, `e2e@uengine.org` 사용자, `vacation_request_process` proc_def + form_def + bpm_proc_inst + todolist 1건
- mock-llm-pdq의 `/v1/chat/completions`는 prompt 내 표 생성 마커를 인식해 ```html<table>...</table>``` 코드 블록을 반환한다.
- 호출 경로: 테스트는 `COMPLETION_DIRECT_URL`(기본 `http://127.0.0.1:8000`)로 직접 POST하여 `X-Forwarded-Host: localhost:8088`로 localhost 테넌트 컨텍스트를 만든다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| e2e_seed.sql | seed | `openspec/specs/completion_process-data-query/e2e/seed_files/e2e_seed.sql` | 테넌트·사용자·proc_def·form_def·bpm_proc_inst·todolist 시드 |
| mock_llm.py (`/v1/chat/completions`) | stub | `openspec/specs/completion_process-data-query/e2e/scripts/mock_llm.py` | LLM 응답을 ```html``` 코드 블록으로 결정적 생성 |
| Playwright `request` 컨텍스트 | fixture | `COMPLETION_DIRECT_URL=http://127.0.0.1:8000` | 사용자 액션 없이 백엔드 계약만 호출 |

## 절차
1. Playwright `request` 컨텍스트를 `COMPLETION_DIRECT_URL` 기반으로 생성한다.
2. `POST /process-data-query`를 다음 헤더/본문으로 호출한다:
   - 헤더: `Content-Type: application/json`, `X-Forwarded-Host: localhost:8088`
   - 본문: `{"input": {"query": "내 휴가 신청 목록", "user_id": "e2e@uengine.org", "chat_room_id": "e2e-room-01"}}`
3. 응답을 받고 본문을 검증한다.

## 기대 결과
- HTTP 상태 코드는 200이다.
- 응답 본문은 HTML 표 문자열이다. `<table` 마커를 포함하고 `clean_html_string` 후처리 결과로 `\n`이 제거된 깨끗한 문자열이다.
- 본 시나리오는 사용자 화면 표면이 없으므로 스크린샷을 생성하지 않는다 (보조 프로토콜 시나리오 / 면제).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-data-query` | 자연어 프로세스 데이터 조회 | 데이터 조회 성공 |

## 산출물
- 스크린샷 체크포인트: **해당 없음 (사용자-액션 면제, 프로토콜 전용)**.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-data-query/e2e/results/results.json`
