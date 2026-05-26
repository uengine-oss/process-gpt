# E2E 시나리오 01: 학습 모드로 정보 저장하기

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `학습 모드로 정보를 저장하면 학습 완료 안내가 표시된다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
사용자가 에이전트 화면의 `학습` 탭에서 새로운 정보를 입력해 전송하면, 그 정보가 해당 에이전트의 메모리에 저장되고 화면에 학습 완료 안내가 표시되어야 한다. 학습 모드 요청(`POST /multi-agent/chat`, `options.is_learning_mode:true`)이 `response.type:"information"` 응답을 돌려주는 계약을 사용자 관점에서 검증한다. 메모리에 저장되지 않으면 이후 질의 모드 답변 품질이 떨어지므로 이 흐름은 핵심 위험 지점이다.

## 사전 조건
- 브라우저 진입점 nginx 게이트웨이(`http://localhost:8088`)가 떠 있어야 한다.
- 게이트웨이가 프론트엔드 SPA와 completion 서비스(`/completion/multi-agent/*`)로 요청을 전달해야 한다.
- Supabase(Kong → auth·rest)와 Postgres+pgvector(mem0 `memories` 컬렉션)가 정상 동작해야 한다.
- LLM·임베딩 외부 경계는 결정적 동작을 위해 `mock-llm` 스텁으로 대체한다.
- 시드 데이터로 로그인 사용자 1명과 에이전트(타입 `agent`) 1명이 미리 생성되어 있어야 한다.
- 학습 대상 정보는 시드 메모리에 존재하지 않는 새 문장이어야 한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | 로그인 사용자·에이전트 프로필 생성 |
| `mock-llm` | route stub | `http://mock-llm:8080/v1` | OpenAI 호환 임베딩·채팅 응답을 결정적으로 반환 |
| 학습 문장 | fixture | 테스트 코드 상수 `LEARN_TEXT` | 신규 저장 대상이 되는 고유 정보 문장 |

## 절차
1. 사용자가 브라우저로 `http://localhost:8088`에 접속해 로그인 화면으로 이동한다.
2. 사용자가 시드 계정의 이메일과 비밀번호를 입력하고 동의 체크박스를 선택한 뒤 로그인 버튼을 누른다.
3. 로그인 후 사용자가 에이전트 대화 화면(`/agent-chat/<agent-id>`)으로 이동한다.
4. 사용자가 좌측 탭에서 `학습` 탭을 선택한다.
5. 사용자가 채팅 입력창에 학습할 정보 문장을 입력하고 전송 버튼을 누른다.
6. 사용자가 응답이 도착할 때까지 기다린 뒤 학습 완료 안내 메시지를 확인한다.

## 기대 결과
- 전송 직후 "답변을 생성 중입니다..." 형태의 진행 상태 메시지가 잠시 표시된다.
- 잠시 후 에이전트가 입력 정보를 기억/학습했음을 알리는 답변 메시지가 대화 영역에 표시된다.
- 입력한 문장이 사용자 메시지 버블로, 학습 완료 안내가 에이전트 메시지 버블로 함께 남는다.
- 브라우저 UI 조작으로 발생한 `POST /completion/multi-agent/chat` 요청이 `task_id`와 `response.type:"information"`을 포함한 응답을 반환한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 학습 정보 저장 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `learning-initial` | 학습 탭 최초 화면(입력창 비어 있음) | `process-gpt-completion_agent-memory-chat-01-learning-initial.png` | 학습 탭 첫 화면 |
  | `learning-input` | 학습 정보를 입력창에 입력한 상태 | `process-gpt-completion_agent-memory-chat-01-learning-input.png` | 학습할 정보 입력 완료 |
  | `learning-result` | 학습 완료 안내 답변이 표시된 상태 | `process-gpt-completion_agent-memory-chat-01-learning-result.png` | 학습 완료 안내 확인 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
