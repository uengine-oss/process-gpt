# E2E 시나리오 04: 테넌트별 데이터 조회 제한 (백엔드 계약 전용)

## 메타데이터
- 스위트 슬러그: `completion_process-data-query`
- 원본 명세 ID: `completion_process-data-query`
- 시나리오 ID: `04`
- Playwright 테스트 제목: `04 프로세스 데이터 조회는 요청 테넌트 범위로 한정된다 (protocol-only)`
- 원본 명세:
  - `openspec/specs/completion_process-data-query/spec.md`
- 분류: **백엔드 계약 전용 / 사용자-액션 면제**

## 목적
`X-Forwarded-Host` 헤더로 결정되는 테넌트 컨텍스트가 `localhost`일 때 `subdomain_var`이 `localhost`로 설정되고, mock-LLM이 받는 마지막 prompt 본문에 localhost 테넌트의 proc_def(`vacation_request_process`)만 포함되며 타 테넌트(`altten`)의 proc_def(`altten_only_secret_process`)는 포함되지 않음을 보장한다.

## 사용자-액션 면제 근거
- 테넌트 컨텍스트는 게이트웨이가 결정하는 `Host`/`X-Forwarded-Host`로 정의되며, 브라우저는 임의 Host 헤더를 사용자 액션으로 설정할 수 없다.
- 본 스펙의 사용자-가시 표면은 시나리오 03이며, 03이 디자이너에서 동작하는 동안 같은 게이트웨이 origin의 테넌트 컨텍스트가 이미 적용된다. 본 시나리오는 그 격리가 데이터 결합 지점(LLM prompt)까지 전달되는지를 백엔드 직접 호출로 검증한다.
- 동일한 패턴이 `completion_process-definition-search` 스위트에서 이미 채택되어 있다 (`COMPLETION_DIRECT_URL` + `X-Forwarded-Host` 보조 프로토콜 시나리오).

## 사전 조건
- 01과 동일한 스택 사용.
- DB seed: `localhost` 테넌트에 `vacation_request_process`, `altten` 테넌트에 `altten_only_secret_process` 각각 시드됨.
- mock-llm-pdq는 마지막 chat-completion prompt 본문을 `/control/last-prompt` GET 엔드포인트로 반환한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| altten seed | seed | `openspec/specs/completion_process-data-query/e2e/seed_files/e2e_seed.sql` | 두 번째 테넌트(`altten`)와 그 안에서만 보이는 proc_def 시드 |
| `/control/last-prompt` | stub control | `openspec/specs/completion_process-data-query/e2e/scripts/mock_llm.py` | 마지막 prompt 캡처를 외부에서 조회 |
| Playwright `request` 컨텍스트 | fixture | `COMPLETION_DIRECT_URL=http://127.0.0.1:8000`, `MOCK_LLM_URL=http://127.0.0.1:8081` | 백엔드 직접 호출 + mock-LLM 상태 조회 |

## 절차
1. Playwright `request` 컨텍스트를 `COMPLETION_DIRECT_URL` 기반으로 생성한다.
2. `POST /process-data-query`를 다음 조건으로 호출한다:
   - 헤더: `Content-Type: application/json`, `X-Forwarded-Host: localhost:8088`
   - 본문: `{"input": {"query": "내 진행 중인 프로세스 인스턴스 목록", "user_id": "e2e@uengine.org", "chat_room_id": "e2e-room-04"}}`
3. 응답이 200으로 떨어지는지 확인한다.
4. `GET {MOCK_LLM_URL}/control/last-prompt`을 호출해 mock-LLM이 마지막으로 받은 prompt 본문을 가져온다.
5. prompt 본문에 `vacation_request_process` 가 포함되고 `altten_only_secret_process` 가 포함되지 않음을 검증한다.

## 기대 결과
- `/process-data-query` 응답이 HTTP 200으로 반환된다.
- 마지막 prompt 본문에 `vacation_request_process` 문자열이 존재한다.
- 동일 prompt 본문에 `altten_only_secret_process` 문자열이 존재하지 않는다.
- 본 시나리오는 사용자 화면 표면이 없으므로 스크린샷을 생성하지 않는다 (보조 프로토콜 시나리오 / 면제).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-data-query` | 조회 범위의 테넌트 격리 | 테넌트별 데이터 조회 제한 |

## 산출물
- 스크린샷 체크포인트: **해당 없음 (사용자-액션 면제, 프로토콜 전용)**.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-data-query/e2e/results/results.json`
