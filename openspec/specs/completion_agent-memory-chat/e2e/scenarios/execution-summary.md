# 에이전트 메모리 대화 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_agent-memory-chat`
- 날짜: 2026-05-22
- 명령: `npx playwright test --config=../../openspec/specs/completion_agent-memory-chat/e2e/tests/playwright.config.mjs` (작업 디렉터리 `services/frontend`)
- Base URL: `http://localhost:8088` (nginx 게이트웨이)
- 환경: docker (`docker-compose.e2e.yml`)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_agent-memory-chat/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_agent-memory-chat/e2e/tests/completion_agent-memory-chat.spec.mjs`
- Docker compose: `docker-compose.e2e.yml`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 4 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_agent-memory-chat/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_agent-memory-chat/e2e/results/html-report/index.html`
- 스크린샷: `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_agent-memory-chat/e2e/results/artifacts/`

## 워크플로 실행 절차
1. Docker compose 검증: `docker compose -f docker-compose.e2e.yml config --quiet` → 통과
2. 스택 기동: `docker compose -f docker-compose.e2e.yml up -d --build` → completion 이미지 빌드, 전 서비스 기동
3. Sanity Check (게이트웨이 경유 실제 요청 경로):
   - 컨테이너 상태: db/auth/kong/completion/mock-llm/mock-external-agent healthy, gateway/frontend running
   - db-seed 적용 완료 (로그인 사용자·에이전트 프로필 시드)
   - `GET http://localhost:8088/completion/multi-agent/health-check` → `{"status":"healthy"}`
   - `POST http://localhost:8088/completion/multi-agent/chat` 학습 모드 → `task_id` + `response.type:"information"`
   - `POST http://localhost:8088/completion/multi-agent/chat` 질의 모드 → `task_id` + `response.type:"query"`
   - `GET http://localhost:8088/completion/multi-agent/fetch-data` → 원격 에이전트 디스크립터 반환
   - 브라우저 → 게이트웨이 → completion → mem0/pgvector·mock-llm 경로 정상 확인
4. Playwright 4개 시나리오 실행 → 4개 통과

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `learning-initial` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-initial.png` | 학습 탭 첫 화면 |
| 01 | `learning-input` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-input.png` | 학습할 정보 입력 완료 |
| 01 | `learning-result` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-01-learning-result.png` | 학습 완료 안내 확인 |
| 02 | `duplicate-first` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-02-duplicate-first.png` | 첫 학습 결과 안내 |
| 02 | `duplicate-second` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-02-duplicate-second.png` | 동일 정보 재전송 결과 안내 |
| 03 | `query-input` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-input.png` | 질문 입력 완료 |
| 03 | `query-running` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-running.png` | 답변 생성 진행 중 |
| 03 | `query-answer` | `openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/process-gpt-completion_agent-memory-chat-03-query-answer.png` | 메모리 검색 기반 답변 확인 |
| 04 | 해당 없음 | - | 비 UI 프로토콜 점검 (스크린샷 없음) |

## 검증
- 출력 검증기: passed (`python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_agent-memory-chat --suite-root openspec/specs/completion_agent-memory-chat/e2e`)
- Playwright: passed (4/4)
- Docker compose config: passed

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 중복 저장 방지 판정 반전 결함 | completion `_is_duplicate_memory`가 mem0 `memory.search` 의 cosine **distance**(미관련 시 ≈1.0)를 **similarity** 임계값 0.92와 비교. 신규 정보를 중복으로 오판하고 동일 정보를 미중복으로 오판하여 명세의 `유사 정보 중복 저장 방지`가 정확히 동작하지 않음(직접 점검 시 동일 메모리가 2회 저장된 것을 확인) | 백엔드 결함으로 보고. 시나리오 02는 반복 학습 시 `response.type:"information"` 안내 일관성까지만 검증 |
| `agent_id` 누락 응답 상태 코드 | 명세는 `400` 요구, 구현은 `HTTPException`을 광범위 `except`로 감싸 `500` 반환. 오류 메시지는 명세와 일치 | 백엔드 결함으로 보고. 시나리오 04는 오류 상태(>=400) + 메시지 일치로 검증 |
| Supabase realtime WebSocket 503 | 브라우저 콘솔에 realtime 연결 503 경고 발생. 학습/질의 응답은 컴포넌트가 메시지를 직접 렌더링하므로 검증에 영향 없음 | 영향 없음. 실시간 채팅 동기화가 필요한 후속 시나리오에서만 realtime 서비스 보강 검토 |
| Playwright 의존성 해석 | 스위트 테스트가 `openspec/specs/.../e2e/tests/` 에 있어 `@playwright/test` 를 해석하려면 `e2e/node_modules` → `services/frontend/node_modules` 디렉터리 정션이 필요(정션은 `.gitignore` 처리됨) | 실행 전 정션 생성 필요. 재현: `New-Item -ItemType Junction -Path openspec/specs/completion_agent-memory-chat/e2e/node_modules -Target services/frontend/node_modules` |
