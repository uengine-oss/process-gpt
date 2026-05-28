# E2E 시나리오 02: 유사한 학습 정보를 다시 입력하면 중복으로 인식되어 저장되지 않는다

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `유사한 학습 정보를 다시 입력하면 중복으로 인식되어 저장되지 않는다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
이미 저장된 학습 정보와 유사한 메시지를 학습 모드로 다시 전송했을 때, mem0 유사도 임계값(0.92) 기반의 중복 회피 로직이 동작하여 새 메모리가 저장되지 않고, 화면에는 중복임을 알리는 응답이 표시되는지 검증합니다.

## 사전 조건
- 시나리오 01 과 동일한 인프라/시드.
- mock-llm 임베딩은 동일 키워드(예: `휴가`/`연차`/`vacation`) 를 포함한 문장에 대해 동일 벡터를 반환하여 유사도가 임계값을 넘도록 결정성 있게 설계되어 있습니다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| mock-llm 임베딩 | stub | `POST http://mock-llm:8080/v1/embeddings` | 키워드별 결정적 벡터 반환 |
| mock-llm 챗 | stub | `POST http://mock-llm:8080/v1/chat/completions` | "비슷한 내용" 응답 결정성 |

## 절차
1. 사용자가 로그인 후 `/agent-chat/<agent_id>` 에 진입하고 학습 탭을 클릭합니다.
2. 사용자가 첫 번째 학습 메시지(예: `우리 회사 휴가 정책은 연 15일이다`) 를 입력하고 전송하여 메모리에 저장합니다.
3. 사용자가 같은 주제(키워드 `휴가` 포함) 의 두 번째 학습 메시지(예: `우리 회사 연차는 15일로 운영한다`) 를 입력합니다.
4. 사용자가 Enter 로 두 번째 메시지를 전송합니다.
5. 사용자가 에이전트의 응답이 "비슷한 내용이 이미 있어 새로 저장하지 않았다" 는 의미의 메시지인지 확인합니다.

## 기대 결과
- 두 번째 `POST /completion/multi-agent/chat` 응답이 200 이며, `response.type` 이 `information` 입니다.
- 응답 텍스트에 "비슷한", "이미", "저장하지" 와 같은 중복 회피 자연어가 포함되어 있습니다.
- 첫 번째 메시지는 저장됨을 알리는 응답, 두 번째 메시지는 중복 회피 응답으로 명확히 구분됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 유사 정보 중복 저장 방지 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `02-learning-first-stored` | 첫 번째 학습이 저장되어 응답이 표시된 상태 | `process-gpt-completion_agent-memory-chat-02-learning-first-stored.png` | 첫 학습 정보 저장 완료 |
  | `02-learning-duplicate-input` | 두 번째 유사 메시지를 입력한 상태 | `process-gpt-completion_agent-memory-chat-02-learning-duplicate-input.png` | 유사한 학습 정보 재입력 |
  | `02-learning-duplicate-skip` | 중복 회피 응답이 표시된 상태 | `process-gpt-completion_agent-memory-chat-02-learning-duplicate-skip.png` | 중복 학습 회피 응답 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
