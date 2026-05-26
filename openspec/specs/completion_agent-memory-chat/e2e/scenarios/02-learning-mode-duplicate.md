# E2E 시나리오 02: 동일 정보 반복 학습과 중복 저장 방지 정책 확인

## 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `이미 학습한 내용과 유사하면 중복으로 저장하지 않는다`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`

## 목적
사용자가 같은 정보를 학습 모드로 반복해서 보낼 때 시스템이 안정적으로 학습 결과 안내를 돌려주는지 확인한다. 명세의 `유사 정보 중복 저장 방지` 시나리오는 "충분히 유사한 정보가 이미 있으면 새로 저장하지 않는다"를 요구한다. 본 시나리오는 동일 정보를 두 번 학습 제출하여 두 번 모두 `response.type:"information"` 응답과 학습 결과 안내가 표시되는지를 사용자 관점에서 검증한다. 단, 중복 판정의 정확성(유사 → 미저장) 자체는 completion 서비스의 유사도 판정 로직 결함으로 현재 보장되지 않으며, 이 결함은 커버리지 매트릭스의 미검증 및 보류 항목과 실행 요약의 알려진 공백에 기록한다.

## 사전 조건
- 시나리오 01과 동일한 게이트웨이·completion·Supabase·mem0·`mock-llm` 환경이 필요하다.
- `mock-llm` 임베딩 스텁은 동일 문장에 대해 동일한 벡터를 반환하여 반복 학습이 결정적으로 재현되도록 한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_agent-memory-chat/e2e/seed_files/e2e_seed.sql` | 로그인 사용자·에이전트 프로필 생성 |
| `mock-llm` | route stub | `http://mock-llm:8080/v1` | 동일 문장에 동일 임베딩·결정적 학습 응답을 반환 |
| 반복 학습 문장 | fixture | 테스트 코드 상수 `dupText` | 1차·2차 학습에 동일하게 사용하는 문장 |

## 절차
1. 사용자가 `http://localhost:8088`에 로그인하고 에이전트 대화 화면으로 이동한다.
2. 사용자가 `학습 모드` 탭을 선택한다.
3. 사용자가 채팅 입력창에 정보 문장을 입력하고 전송한 뒤, 첫 번째 학습 결과 안내를 확인한다.
4. 사용자가 같은 문장을 다시 입력창에 입력하고 전송한다.
5. 사용자가 두 번째 응답이 도착할 때까지 기다린 뒤 학습 결과 안내를 확인한다.

## 기대 결과
- 1차 전송과 2차 전송 모두 진행 상태 메시지가 잠시 표시된 뒤 학습 결과 안내 메시지가 대화 영역에 표시된다.
- 두 번의 UI 조작으로 발생한 `POST /completion/multi-agent/chat` 요청 모두 `task_id`와 `response.type:"information"`을 포함한 응답을 반환한다.
- 두 번의 응답 모두 대화 영역에 사용자·에이전트 메시지 쌍으로 남는다.
- (참고) 명세가 요구하는 "유사 → 미저장" 판정 정확성은 본 환경에서 보장되지 않으며 미검증 및 보류 항목에 기록한다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 유사 정보 중복 저장 방지 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `duplicate-first` | 1차 학습 결과 안내가 표시된 상태 | `process-gpt-completion_agent-memory-chat-02-duplicate-first.png` | 첫 학습 결과 안내 |
  | `duplicate-second` | 동일 정보 재전송 후 학습 결과 안내 상태 | `process-gpt-completion_agent-memory-chat-02-duplicate-second.png` | 동일 정보 재전송 결과 안내 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
