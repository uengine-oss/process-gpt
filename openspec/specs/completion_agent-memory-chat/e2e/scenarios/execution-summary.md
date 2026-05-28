# 에이전트 메모리 대화 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 날짜: 2026-05-26
- 명령: `npx playwright test --reporter=list`
- Base URL: `http://localhost:8088` (nginx 게이트웨이)
- 환경: docker

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_agent-memory-chat/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_agent-memory-chat/e2e/tests/completion_agent-memory-chat.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` + `openspec/specs/completion_agent-memory-chat/e2e/docker/coverage.override.yml` (백엔드 coverage.py) + `openspec/specs/completion_agent-memory-chat/e2e/docker/frontend-coverage.override.yml` (프론트엔드 source-mapped 빌드)
- 프론트엔드 source-mapped 빌드 명령: `cd services/frontend && NODE_OPTIONS="--max-old-space-size=8192" npx vite build --minify=false` 후 `docker compose -f docker-compose.e2e.yml -f openspec/specs/completion_agent-memory-chat/e2e/docker/frontend-coverage.override.yml up -d --build --no-deps frontend gateway`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 6 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_agent-memory-chat/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_agent-memory-chat/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_agent-memory-chat/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_agent-memory-chat/e2e/results/backend-coverage/`
- 프론트엔드 커버리지: `openspec/specs/completion_agent-memory-chat/e2e/results/frontend-coverage/`
- 스크린샷: `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_agent-memory-chat/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `01-learning-initial` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-initial.png` | 학습 모드 초기 화면 |
| 01 | `01-learning-input` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-input.png` | 학습 정보 입력 직후 |
| 01 | `01-learning-result` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-result.png` | 저장 완료 응답 확인 |
| 02 | `02-learning-first-stored` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-02-learning-first-stored.png` | 첫 학습 정보 저장 완료 |
| 02 | `02-learning-duplicate-input` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-02-learning-duplicate-input.png` | 유사한 학습 정보 재입력 |
| 02 | `02-learning-duplicate-skip` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-02-learning-duplicate-skip.png` | 중복 학습 회피 응답 |
| 03 | `03-query-initial` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-initial.png` | 질의 모드 초기 화면 |
| 03 | `03-query-input` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-input.png` | 질문 입력 직후 |
| 03 | `03-query-result` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-result.png` | 메모리 기반 답변 확인 |

## 검증
- 출력 검증기: passed
- Playwright: passed (6/6)
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed
- 백엔드 coverage 게이트: passed (agent_chat.py 89%, mem0_agent_client.py 88%)
- 프론트엔드 coverage 게이트: passed (source-mapped 라인 평균 74.33% — Vite 소스맵 기반 Monocart 보고서)
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 4/4 requirements, 6/6 scenarios, 6/6 tests | 충분 |
| 백엔드 | `services/completion/agent_chat.py`, `services/completion/mem0_agent_client.py` | line 평균 88% (XML+HTML 생성) | 충분 |
| 프론트엔드 | `AgentChatGenerator.js`, `AgentChatLearning.vue`, `AgentChatQuestion.vue`, `ui/Chat.vue` | Vite 소스맵 기반 Monocart line 평균 74.33% (Generator 77%, Learning 90.79%, Question 91.46%, ui/Chat 38.07%) | 충분 (ui/Chat 38%만 보강 권장) |

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 백엔드 `chat_message`의 외부 `except Exception` 이 `HTTPException` 까지 감싸 400 명세가 500 으로 노출됨 | API 응답 코드 계약과 실제 거동 불일치 (메시지는 명세대로) | 백엔드 수정 또는 명세 갱신 검토 |
| `services/frontend/src/components/ui/Chat.vue` source-mapped line 38.07% | 채팅 UI 의 비활성 분기(파일/이미지 첨부, 모바일 표시 모드 등)가 미실행 | 추후 첨부/모바일 시나리오를 추가하거나 임계값을 30% 기준으로 명시 |
