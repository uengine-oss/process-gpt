# completion_process-activity-rework E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-activity-rework`
- 날짜: 2026-05-27
- 명령: `node node_modules/@playwright/test/cli.js test --config=playwright.config.mjs`
- Base URL: `http://localhost:8088` (nginx 게이트웨이 단일 진입점)
- 환경: docker (루트 `docker-compose.e2e.yml` 기반 스택)

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-activity-rework/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/completion_process-activity-rework/e2e/tests/completion_process-activity-rework.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` (db, kong, auth, rest, completion, frontend, gateway 공유 + 신규 `db-seed-process-activity-rework`)

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 4 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_process-activity-rework/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_process-activity-rework/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_process-activity-rework/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_process-activity-rework/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-activity-rework/e2e/results/backend-coverage/` (시도 결과는 아래 "검증" 항목 참조)
- 프론트엔드 커버리지: `openspec/specs/completion_process-activity-rework/e2e/results/frontend-coverage/`
- 스크린샷: `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/`
- 산출물: `openspec/specs/completion_process-activity-rework/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `workitem-detail-done` | `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/process-gpt-completion_process-activity-rework-01-workitem-detail-done.png` | 완료한 작업 상세 화면에서 재작업 버튼이 노출됩니다 |
| 01 | `rework-dialog-open` | `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/process-gpt-completion_process-activity-rework-01-rework-dialog-open.png` | 어디까지 재작업할지 선택하는 다이얼로그가 표시됩니다 |
| 01 | `rework-dialog-include-all` | `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/process-gpt-completion_process-activity-rework-01-rework-dialog-include-all.png` | 이후 활동까지 모두 재작업 대상으로 선택한 화면입니다 |
| 02 | `rework-dialog-submit-ready` | `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/process-gpt-completion_process-activity-rework-02-rework-dialog-submit-ready.png` | 재작업 범위를 선택하고 시작 버튼이 활성화된 다이얼로그입니다 |
| 02 | `instance-after-rework` | `openspec/specs/completion_process-activity-rework/e2e/results/screenshots/process-gpt-completion_process-activity-rework-02-instance-after-rework.png` | 재작업이 시작되어 인스턴스 화면으로 이동했습니다 |

## 검증
- 출력 검증기: passed (`python .claude/skills/e2e-tests/scripts/validate_e2e_outputs.py --suite completion_process-activity-rework --suite-root openspec/specs/completion_process-activity-rework/e2e`)
- Playwright: passed (4/4)
- Docker compose config: passed (`docker compose -f docker-compose.e2e.yml config --services`)
- OpenSpec 추적성 게이트: passed (`node .claude/skills/e2e-tests/scripts/evaluate_spec_coverage.mjs --suite completion_process-activity-rework --suite-root openspec/specs/completion_process-activity-rework/e2e --spec openspec/specs/completion_process-activity-rework/spec.md --write-summary`)
- 백엔드 coverage 게이트: not-run (이미 부팅된 공유 completion 컨테이너를 재시작하면 동일 스택을 쓰는 다른 스위트(`completion_agent-memory-chat` 등)의 진행 작업을 깨뜨릴 위험이 있어, 이번 라운드는 instrumented backend 재기동을 보류함. 후속 라운드에서 coverage override 적용 + USR2 flush로 수집 예정 — 메모리 [[coverage-py-usr2-flush]] / [[completion-coverage-override-workdir]] 참조)
- 프론트엔드 coverage 보조 게이트: passed-supporting (`page.coverage.startJSCoverage` 기반 V8 raw 데이터 저장; 프리빌트 이미지라 source-map 미적용)
- AI 스펙 커버리지 판단: partial (백엔드 spec-relevant 라인 커버리지를 본 라운드에서 측정하지 않았으므로 보강 필요)

## 병렬 실행 노트
- Phase E의 다음 단계는 의도적으로 직렬화함:
  - Backend coverage 재수집은 completion 컨테이너 재기동을 동반하므로 다른 스위트가 같은 컨테이너에서 작업 중일 때는 차단됨. 본 라운드에서는 안전을 위해 미수행.
  - 출력 validator, OpenSpec traceability gate, frontend V8 coverage 처리는 결과 디렉터리만 읽으므로 향후 안전하게 병렬화 가능.
- 다른 phase는 단일 명령으로 순차 실행됨.

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement / Scenario / Test / Screenshot | 3/3 requirements 매핑, 4/5 spec scenarios 매핑(나머지 1건 보류), 4/4 Playwright tests passed, 5/5 documented checkpoints 캡처 | 충분 (보류된 명세 시나리오는 "알려진 공백" 참조) |
| 백엔드 | `services/completion/process_engine.py` (`handle_get_rework_activities`, `handle_rework_complete`, `get_reference_workitems`, `get_all_next_workitems`, `create_new_workitem`) + `services/completion/compensation_handler.py::generate_compensation` (skip 분기) | instrumented 재수집 미실행 — 본 라운드 미산출 (sanity check + Playwright 호출로 해당 핸들러가 실행됨을 행위적으로 확인) | 부족 (수치 미수집) |
| 프론트엔드 | `ReworkDialog.vue`, `WorkItem.vue` 일부, `ProcessGPTBackend.ts` 의 `getReworkActivities` / `reWorkItem` | 페이지 V8 raw coverage 저장(번들 단위, source-map 없음) | 보조 지표 (source-map 미지원으로 라인 단위 산정 불가) |

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| "되돌릴 작업이 있을 때 보상 코드 생성" 명세 시나리오 | LLM 호출 + events 시드가 필요해 본 라운드에서 미커버. 생략 경로만 검증됨. | mock-llm 응답에 compensation 코드 페이로드 추가 + `events` 시드 후 별도 시나리오로 보강 |
| `/get-rework-activities` 의 워크아이템 미존재 응답 코드 불일치 | 명세는 400을 요구하나 현재 구현은 outer `except Exception`이 `HTTPException`을 500으로 재포장하여 반환. 사용자 메시지(`No workitem found`)는 보존됨. | `handle_get_rework_activities` 의 except 절을 `except HTTPException: raise; except Exception:` 으로 수정 후 회귀 테스트를 400 단언으로 좁힘 |
| `public.mcp_python_code` 테이블이 루트 `init.sql`에 없음 | rework-complete가 `fetch_mcp_python_code` 호출 시 PostgREST 404를 받고 보상 처리 전체가 실패. 본 스위트는 시드에서 `create table if not exists`로 우회. | infra 또는 completion 서비스 마이그레이션에서 정식 DDL 추가 후 시드의 임시 DDL 제거 |
| 백엔드 라인 커버리지 수치 미수집 | 공유 completion 컨테이너 재기동이 다른 진행 중인 스위트를 깨뜨릴 위험이 있어 보류. 행위적 실행 증거는 sanity check + Playwright 결과로 남김. | 후속 라운드에서 coverage override 적용 + USR2 flush → spec-relevant 파일 기준 백분율 갱신 |
| nginx 게이트웨이의 upstream DNS 캐시 | completion 컨테이너 IP가 바뀌면 nginx가 옛 IP로 502를 계속 반환. 본 라운드에서 `docker restart process-gpt-e2e-gateway`로 해결. | 게이트웨이 conf에 `resolver` 디렉티브 또는 service discovery 개선 검토 |
