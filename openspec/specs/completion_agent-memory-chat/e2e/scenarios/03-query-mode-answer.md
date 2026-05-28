# E2E 시나리오 03: 질의 모드에서 학습한 정보를 검색해 답변을 받는다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `03`
- Playwright 테스트 제목: `질의 모드에서 학습한 정보를 검색해 답변을 받는다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
사용자가 질의 탭에서 질문을 입력하면, completion 서비스가 mem0 검색을 호출하고 LLM 응답을 JSON(`content`/`html_content`/`search_results`) 으로 받아 UI 에 표시하는지 검증합니다.

## 사전 조건
- 시나리오 01 의 학습 정보가 메모리에 저장되어 있거나, 본 시나리오 시작 시 동일한 학습 메시지를 먼저 전송해 메모리를 채웁니다.
- mock-llm 챗 응답은 질의 프롬프트(`검색 결과:` 키워드 포함) 를 받으면 `{content, html_content, search_results}` 형태의 결정성 JSON 을 OpenAI chat-completion 응답 안에 담아 반환합니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| 사전 학습 | UI 단계 | learning 탭 → 메시지 전송 | 질의 대상 메모리 적재 |
| mock-llm 챗 | stub | `POST http://mock-llm:8080/v1/chat/completions` | JSON 응답 결정성 |

## 절차
1. 사용자가 로그인 후 `/agent-chat/<agent_id>` 에 진입합니다.
2. 사용자가 학습 탭에서 휴가 정책 학습 메시지를 한 차례 전송하여 메모리를 채웁니다.
3. 사용자가 좌측 탭에서 "질문" 탭을 클릭하여 질의 모드로 전환합니다.
4. 사용자가 질문(예: `우리 회사 휴가는 며칠인가요?`) 을 입력하고 Enter 로 전송합니다.
5. 사용자가 에이전트의 답변 메시지에 검색 기반 텍스트가 표시되는지 확인합니다.

## 기대 결과
- 질의용 `/completion/multi-agent/chat` 응답이 200 이며, `response.type` 이 `query` 입니다.
- 응답에는 `content` 텍스트가 포함되고, `html_content` 또는 `search_results` 가 함께 반환됩니다.
- UI 에 에이전트 답변 메시지가 새 버블로 추가되어 사용자가 검색 기반 답변을 확인할 수 있습니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | 메모리 기반 답변 성공 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `03-query-initial` | 질문 탭이 활성화된 초기 상태 | `process-gpt-completion_agent-memory-chat-03-query-initial.png` | 질의 모드 초기 화면 |
  | `03-query-input` | 질문 메시지를 입력한 상태 | `process-gpt-completion_agent-memory-chat-03-query-input.png` | 질문 입력 직후 |
  | `03-query-result` | 검색 기반 답변 메시지가 표시된 상태 | `process-gpt-completion_agent-memory-chat-03-query-result.png` | 메모리 기반 답변 확인 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
