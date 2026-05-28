# 에이전트 메모리 대화 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat`
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`
- 백엔드/제품 계약:
  - `services/completion` FastAPI 라우터: `POST /multi-agent/chat`, `GET /multi-agent/health-check`, `GET /multi-agent/fetch-data`
  - 메모리 저장소: Postgres + pgvector (`vecs.memories`)
  - 인증/세션: Supabase GoTrue 로그인, `users`/`tenants` 행 기반
  - LLM 외부 경계: OpenAI 호환 프록시 (E2E에서는 `mock-llm` 으로 결정성 확보)
  - 외부 에이전트 디스크립터 boundary: `mock-external-agent` `/.well-known/agent.json`
- E2E 루트: `openspec/specs/completion_agent-memory-chat/e2e/`
- Playwright 명세: `openspec/specs/completion_agent-memory-chat/e2e/tests/completion_agent-memory-chat.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_agent-memory-chat/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-learning-mode-store.md` | `학습 모드에서 정보를 입력하면 메모리에 저장된다` | UI: agent-chat → learning 탭 → 메시지 입력 → 저장 응답 확인 |
| 02 | `02-learning-duplicate-skip.md` | `유사한 학습 정보를 다시 입력하면 중복으로 인식되어 저장되지 않는다` | UI: learning 탭에서 동일 주제 재입력 → 중복 응답 확인 |
| 03 | `03-query-mode-answer.md` | `질의 모드에서 학습한 정보를 검색해 답변을 받는다` | UI: question 탭 → 질문 → 검색 결과 + HTML 답변 |
| 04 | `04-agent-id-missing.md` | `agent_id 누락 요청에 400 오류를 반환한다` | 보조 프로토콜: Playwright `request` 로 검증 |
| 05 | `05-health-check.md` | `GET /multi-agent/health-check 가 healthy 상태를 반환한다` | 보조 프로토콜: 헬스체크 |
| 06 | `06-fetch-data.md` | `GET /multi-agent/fetch-data 가 외부 에이전트 디스크립터를 반환한다` | 보조 프로토콜: 외부 디스크립터 프록시 |

> 시나리오 04/05/06 은 UI 표면이 없는 백엔드 프로토콜 계약(보조 프로토콜 검증)으로, 스크린샷 매뉴얼 증거가 요구되지 않습니다. 사용자-facing 시나리오는 01/02/03 입니다.

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | SHALL | 01, 02 | 저장 성공/중복 회피 모두 검증 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | SHALL | 03, 04 | UI 답변 + agent_id 누락 400 |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | SHALL | 05 | 보조 프로토콜 |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | SHALL | 06 | 보조 프로토콜 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 학습 정보 저장 성공 | 01 | learning 탭 입력 → 저장 응답 메시지 |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 유사 정보 중복 저장 방지 | 02 | learning 탭 재입력 → 중복 응답 메시지 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | 메모리 기반 답변 성공 | 03 | question 탭 질문 → htmlContent + searchResults |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | agent_id 누락 | 04 | 보조 프로토콜 검증 (UI 표면 없음) |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | 상태 점검 응답 | 05 | 보조 프로토콜 검증 (UI 표면 없음) |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | 원격 에이전트 정보 조회 | 06 | 보조 프로토콜 검증 (UI 표면 없음) |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/agent_chat.py` | `chat_message` (`POST /multi-agent/chat`) | 학습/질의 모드, agent_id 누락 | line/function >= 80% | 진입 라우트 및 검증 |
| `services/completion/agent_chat.py` | `health_check` (`GET /multi-agent/health-check`) | 상태 점검 | function = 100% | 단일 진입 라우트 |
| `services/completion/agent_chat.py` | `fetch_data` (`GET /multi-agent/fetch-data`) | 원격 디스크립터 조회 | function = 100% | 단일 진입 라우트 |
| `services/completion/mem0_agent_client.py` | `process_mem0_message` | 학습/질의 모드 분기 | line >= 80% | 모드별 분기 핵심 |
| `services/completion/mem0_agent_client.py` | `generate_learning_response` | 학습 저장/중복 응답 | line >= 70% | 학습 응답 생성 체인 |
| `services/completion/mem0_agent_client.py` | `generate_response` | 질의 모드 답변 | line >= 70% | 질의 응답 생성 체인 |
| `services/completion/mem0_agent_client.py` | `search_memories` | 학습/질의 모두 | function 호출 검증 | 메모리 검색 |
| `services/completion/mem0_agent_client.py` | `store_in_memory` | 학습 저장 | function 호출 검증 | 메모리 적재 |
| `services/completion/mem0_agent_client.py` | `_is_duplicate_memory` | 학습 중복 회피 | branch >= 80% | 임계값 분기 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/ai/AgentChatGenerator.js` | `generate`, `createModelJson` | 학습 및 질의 모드 응답 처리 | line >= 60% | `/completion/multi-agent/chat` 직접 호출 클라이언트 |
| `services/frontend/src/components/AgentChatLearning.vue` | `beforeSendMessage`, `afterGenerationFinished` | 학습 모드 UI | line >= 60% | learning 탭 입력/응답 |
| `services/frontend/src/components/AgentChatQuestion.vue` | `beforeSendMessage`, `afterGenerationFinished` | 질의 모드 UI | line >= 60% | question 탭 입력/응답 |
| `services/frontend/src/components/ui/Chat.vue` | `sendMessage`, `receiveMessage` | 채팅 입력/표시 공통 UI | line >= 30% | AgentChat* 가 공유하는 채팅 컴포넌트 |

> 프론트엔드는 `services/frontend/Dockerfile.coverage-prebuilt` 와 호스트 사전 빌드(`npx vite build --minify=false`) 조합으로 Vite 소스맵을 포함한 정적 산출물을 서빙합니다. Monocart 가 V8 coverage 를 원본 `.vue/.ts/.js` 라인으로 매핑하여 line 평균 74.33% 의 source-mapped 커버리지를 1차 증거로 사용합니다.

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `services/frontend/src/components/ui/Chat.vue` 미커버 분기 | 첨부/모바일/특수 메시지 처리 분기는 본 스펙 시나리오에서 미실행 (source-mapped line 38.07%) | 첨부/모바일 시나리오 추가 또는 임계값을 30% 로 명시 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_agent-memory-chat/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다.
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
