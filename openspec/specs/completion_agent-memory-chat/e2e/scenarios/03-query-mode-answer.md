# E2E 시나리오 03: 질의 모드로 저장된 메모리 활용 답변 받기

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `질의 모드에서 저장된 메모리를 활용한 답변을 받는다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
사용자가 에이전트 화면의 `질문` 탭에서 질문을 입력해 전송하면, 시스템은 해당 에이전트 메모리를 검색하여 검색 결과를 활용한 답변을 돌려주어야 한다. 질의 모드 요청(`POST /multi-agent/chat`, `options.is_learning_mode:false`)이 `response.type:"query"` 응답을 반환하는 계약을 사용자 관점에서 검증한다. 메모리 검색이 답변에 반영되지 않으면 학습 기능 전체가 무의미해지므로 핵심 위험 지점이다.

## 사전 조건
- 시나리오 01과 동일한 게이트웨이·completion·Supabase·mem0·`mock-llm` 환경이 필요하다.
- 같은 에이전트 메모리에 질문과 관련된 정보가 미리 저장되어 있어야 한다(시드 메모리 또는 절차 내 선행 학습으로 준비한다).
- `mock-llm` 채팅 스텁은 질의 모드 프롬프트에 대해 검색 결과를 반영한 결정적 답변을 반환한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | 로그인 사용자·에이전트 프로필 생성 |
| `mock-llm` | route stub | `http://mock-llm:8080/v1` | 검색 결과를 반영한 결정적 질의 답변 반환 |
| 질문 문장 | fixture | 테스트 코드 상수 `QUERY_TEXT` | 선행 학습 정보와 연관된 질문 문장 |

## 절차
1. 사용자가 `http://localhost:8088`에 로그인하고 에이전트 대화 화면으로 이동한다.
2. 사용자가 `학습` 탭에서 답변 근거가 될 정보 문장을 먼저 입력·전송해 메모리에 저장한다.
3. 사용자가 좌측 탭에서 `질문` 탭으로 전환한다.
4. 사용자가 채팅 입력창에 앞서 저장한 정보와 관련된 질문을 입력하고 전송한다.
5. 사용자가 응답이 도착할 때까지 기다린 뒤 답변 메시지를 확인한다.

## 기대 결과
- 전송 직후 진행 상태 메시지가 잠시 표시된다.
- 잠시 후 메모리 검색 결과를 반영한 답변 메시지가 대화 영역에 표시된다.
- 답변에는 질문과 관련된 내용이 포함되며, 입력한 질문은 사용자 메시지 버블로 남는다.
- 브라우저 UI 조작으로 발생한 `POST /completion/multi-agent/chat` 요청이 `task_id`와 `response.type:"query"`를 포함한 응답을 반환한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | 메모리 기반 답변 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `query-input` | 질문 탭에 질문을 입력한 상태 | `process-gpt-completion_agent-memory-chat-03-query-input.png` | 질문 입력 완료 |
  | `query-running` | 질문 전송 후 답변 생성 진행 상태 | `process-gpt-completion_agent-memory-chat-03-query-running.png` | 답변 생성 진행 중 |
  | `query-answer` | 메모리 기반 답변이 표시된 상태 | `process-gpt-completion_agent-memory-chat-03-query-answer.png` | 메모리 검색 기반 답변 확인 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
