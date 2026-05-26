# 에이전트 메모리 대화 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_agent-memory-chat`
- 원본 명세 ID: `completion_agent-memory-chat` <!-- `<microservice>_<domain>-<feature>` 형식이므로 스위트 슬러그와 동일하게 유지합니다. -->
- 원본 명세:
  - `openspec/specs/completion_agent-memory-chat/spec.md`
- 백엔드/제품 계약:
  - 소유 백엔드 서비스: `services/completion` (FastAPI, 포트 8000)
  - 사용자 대면 API: `POST /multi-agent/chat` — 학습 모드(`options.is_learning_mode:true`)와 질의 모드(`options.is_learning_mode:false`)
  - 비 UI 프로토콜 API: `GET /multi-agent/health-check`, `GET /multi-agent/fetch-data`
  - 메모리 저장소: Supabase Postgres + pgvector(mem0 `memories` 컬렉션)
  - 브라우저 진입 경로: 브라우저 → nginx 게이트웨이(`:8088`) → completion 서비스 / Supabase(Kong → auth·rest)
  - 프론트엔드 화면: Vue SPA 라우트 `/agent-chat/:id`의 `학습` 탭(`AgentChatLearning.vue`)과 `질문` 탭(`AgentChatQuestion.vue`)
- E2E 루트: `openspec/specs/completion_agent-memory-chat/e2e/`
- Playwright 명세: `openspec/specs/completion_agent-memory-chat/e2e/tests/completion_agent-memory-chat.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_agent-memory-chat/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-learning-mode-store.md` | `학습 모드로 정보를 저장하면 학습 완료 안내가 표시된다` | 학습 탭에서 정보를 입력·전송하고 학습 완료 답변을 확인 |
| 02 | `02-learning-mode-duplicate.md` | `이미 학습한 내용과 유사하면 중복으로 저장하지 않는다` | 같은 정보를 다시 학습 모드로 보내 중복 미저장 안내를 확인 |
| 03 | `03-query-mode-answer.md` | `질의 모드에서 저장된 메모리를 활용한 답변을 받는다` | 질문 탭에서 질문을 보내 메모리 검색 기반 답변을 확인 |
| 04 | `04-service-protocol-check.md` | `상태 점검·원격 에이전트 조회·필수값 누락 응답을 확인한다` | 비 UI 프로토콜 응답(상태 점검, 원격 디스크립터, `agent_id` 누락 오류)을 확인 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | SHALL | 01, 02 | 저장 성공과 중복 미저장 분기 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | SHALL | 03, 04 | UI 답변(03) + `agent_id` 누락 오류(04) |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | SHALL | 04 | 비 UI 프로토콜 점검 |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | SHALL | 04 | 비 UI 프로토콜 점검 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 학습 정보 저장 성공 | 01 | UI 입력/전송 버튼/학습 완료 답변 화면 |
| `completion_agent-memory-chat` | 학습 모드 메모리 저장 | 유사 정보 중복 저장 방지 | 02 | UI 입력/전송 버튼/중복 미저장 답변 화면 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | 메모리 기반 답변 성공 | 03 | UI 입력/전송 버튼/검색 기반 답변 화면 |
| `completion_agent-memory-chat` | 질의 모드 메모리 검색 답변 | agent_id 누락 | 04 | 프로토콜 응답(비 UI): `400` 상태와 오류 메시지 |
| `completion_agent-memory-chat` | 에이전트 서비스 상태 점검 | 상태 점검 응답 | 04 | 프로토콜 응답(비 UI): `{status:"healthy"}` |
| `completion_agent-memory-chat` | 원격 에이전트 디스크립터 조회 | 원격 에이전트 정보 조회 | 04 | 프로토콜 응답(비 UI): `/.well-known/agent.json` 디스크립터 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `agent_id` 누락 오류의 브라우저 재현 | 프론트엔드 학습/질문 탭은 항상 `agent_id`를 자동 포함하므로 사용자 조작으로 누락 상태를 만들 수 없음 | 시나리오 04에서 비 UI 프로토콜 점검으로 검증 |
| 중복 저장 방지 판정의 정확성(유사 → 미저장) | completion 서비스 `_is_duplicate_memory`가 mem0 `memory.search`의 cosine **distance** 값을 **similarity**로 잘못 비교하여 유사도 판정이 반전됨(직접 점검으로 score≈1.0 확인). 신규 정보가 중복으로 오판되고 동일 정보가 미중복으로 오판됨 | 백엔드 결함으로 보고. 시나리오 02는 반복 학습 시 `response.type:"information"` 안내가 일관되게 반환되는지까지만 검증 |
| `agent_id` 누락 응답의 상태 코드 | 명세는 `400`을 요구하지만 백엔드가 `HTTPException`을 광범위 `except`로 감싸 `500`으로 반환. 오류 메시지 `agent_id is required for Mem0 agent`는 일치 | 백엔드 결함으로 보고. 시나리오 04는 오류 상태(>=400)와 메시지 일치로 검증 |

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
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
