# E2E 시나리오 02: 표로 만들 결과가 없는 경우 (백엔드 계약 전용)

## 메타데이터
- 스위트 슬러그: `completion_process-data-query`
- 원본 명세 ID: `completion_process-data-query`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `02 표로 만들 결과가 없으면 빈 본문이 반환된다 (protocol-only)`
- 원본 명세:
  - `openspec/specs/completion_process-data-query/spec.md`
- 분류: **백엔드 계약 전용 / 사용자-액션 면제**

## 목적
LLM이 표를 구성하지 못한다고 응답한 경우 `/process-data-query` 응답 본문이 빈 문자열/사실상 `null`에 해당하는 결과로 떨어지는 계약을 보장한다.

## 사용자-액션 면제 근거
- 본 라우트의 자연어 입력 경로는 [01-process-data-query-success.md](01-process-data-query-success.md)와 동일하게 채팅 인텐트 우회를 요구하므로 직접 도달이 불가능하다.
- 명세 시나리오는 "표를 만들 수 없을 때 빈 결과(`null`)"를 기술하지만, 현재 구현(`table_chain = ... | StrOutputParser() | extract_html_table | clean_html_string`)은 `StrOutputParser`가 항상 문자열을 반환하여 `null` 분기가 실제로는 빈 문자열로 떨어진다. 본 시나리오는 빈 본문이 안정적으로 반환되는지를 검증한다.
- **승격 조건**: 자연어 조회용 전용 UI 표면이 추가되거나, `process_data_query_chain`(현재 미사용) 경로가 활성화되어 `None` 응답이 가능해지면 본 시나리오는 사용자-액션 시나리오로 승격되어야 한다.

## 사전 조건
- 01과 동일한 스택과 seed 사용.
- mock-llm-pdq는 prompt에 `_EMPTY_` 마커가 보이면 빈 ```html``` 코드 블록을 반환하여 후처리 이후 빈 문자열이 떨어지도록 한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| mock_llm.py `_EMPTY_` 분기 | stub | `openspec/specs/completion_process-data-query/e2e/scripts/mock_llm.py` | prompt에 `_EMPTY_` 마커가 있으면 빈 ```html``` 블록 반환 |
| Playwright `request` 컨텍스트 | fixture | `COMPLETION_DIRECT_URL=http://127.0.0.1:8000` | 사용자 액션 없이 백엔드 계약만 호출 |

## 절차
1. Playwright `request` 컨텍스트를 `COMPLETION_DIRECT_URL` 기반으로 생성한다.
2. `POST /process-data-query`를 다음 헤더/본문으로 호출한다:
   - 헤더: `Content-Type: application/json`, `X-Forwarded-Host: localhost:8088`
   - 본문: `{"input": {"query": "_EMPTY_ 표를 만들 수 없는 질의", "user_id": "e2e@uengine.org", "chat_room_id": "e2e-room-02"}}`
3. 응답을 받고 본문이 빈 문자열에 해당하는 결과인지 검증한다.

## 기대 결과
- HTTP 상태 코드는 200이다.
- 응답 본문은 빈 문자열(`""`)이거나 공백만 포함하여 `<table` 마커를 포함하지 않는다 (사실상 "표를 그릴 수 없음" 상태).
- 본 시나리오는 사용자 화면 표면이 없으므로 스크린샷을 생성하지 않는다 (보조 프로토콜 시나리오 / 면제).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-data-query` | 자연어 프로세스 데이터 조회 | 표로 만들 결과가 없음 |

## 산출물
- 스크린샷 체크포인트: **해당 없음 (사용자-액션 면제, 프로토콜 전용)**.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-data-query/e2e/results/results.json`
