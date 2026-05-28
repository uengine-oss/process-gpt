# E2E 시나리오 01: 학습 모드에서 정보를 입력하면 메모리에 저장된다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `01`
- Playwright 테스트 제목: `학습 모드에서 정보를 입력하면 메모리에 저장된다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
사용자가 에이전트 채팅 화면에서 학습 탭을 열고 정보를 입력하면, 실제 `POST /completion/multi-agent/chat` 요청이 `is_learning_mode:true` 로 전송되어 메모리에 저장되고, 화면에 저장 완료를 알리는 응답 메시지가 표시되는지 검증합니다.

## 사전 조건
- `docker-compose.e2e.yml` 스택이 기동되어 nginx 게이트웨이(8088), completion, mock-llm, supabase(db/auth/rest/kong) 가 정상 동작합니다.
- 시드 SQL 로 `e2e@uengine.org` 사용자(`localhost` 테넌트) 와 메모리 에이전트 프로필(`agent_id = 00000000-0000-0000-0000-0000000000aa`) 이 등록되어 있습니다.
- mem0 의 `memories` 테이블은 빈 상태에서 시작합니다(이전 실행 잔존을 시드에서 정리).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 로그인 사용자 | seed | `auth.users` / `public.users` | 브라우저 로그인 |
| 메모리 에이전트 | seed | `public.users` (`agent_type='agent'`) | `agent_id` 대상 |
| mock-llm | stub | `http://mock-llm:8080/v1/{embeddings,chat/completions}` | 임베딩/응답 결정성 |

## 절차
1. 사용자가 `/auth/login` 페이지에서 이메일과 비밀번호로 로그인합니다.
2. 사용자가 `/agent-chat/<agent_id>` 로 이동하여 메모리 에이전트 화면에 진입합니다.
3. 사용자가 좌측 탭 영역에서 "학습" 탭을 클릭해 학습 모드로 전환합니다.
4. 사용자가 채팅 입력창에 학습 메시지(예: `우리 회사 휴가 정책은 연 15일이다`)를 입력합니다.
5. 사용자가 Enter 를 눌러 메시지를 전송합니다.
6. 사용자가 에이전트로부터 저장 완료를 알리는 응답 메시지를 확인합니다.

## 기대 결과
- `/completion/multi-agent/chat` 응답이 200 이며, 본문의 `response.type` 이 `information` 입니다.
- UI 상에는 사용자 메시지가 먼저 표시되고, 이어서 에이전트의 저장 완료 응답 메시지가 표시됩니다.
- 응답 텍스트에는 학습/기억/저장 의미의 자연어가 포함되어 있습니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 학습 정보 저장 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `01-learning-initial` | 학습 탭이 활성화되고 채팅 입력창이 비어 있는 초기 상태 | `process-gpt-completion_agent-memory-chat-01-learning-initial.png` | 학습 모드 초기 화면 |
  | `01-learning-input` | 학습 메시지를 입력한 직후 입력창 상태 | `process-gpt-completion_agent-memory-chat-01-learning-input.png` | 학습 정보 입력 직후 |
  | `01-learning-result` | 에이전트의 저장 완료 응답 메시지가 표시된 상태 | `process-gpt-completion_agent-memory-chat-01-learning-result.png` | 저장 완료 응답 확인 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
