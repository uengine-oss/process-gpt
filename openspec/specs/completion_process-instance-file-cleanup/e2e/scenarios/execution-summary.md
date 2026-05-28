# 프로세스 인스턴스 파일 정리 E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `completion_process-instance-file-cleanup`
- 분류: **Category B — 백엔드/폴링 전용 계약 (스크린샷 면제)**
- 날짜: 2026-05-27
- 명령: `npx playwright test --config openspec/specs/completion_process-instance-file-cleanup/e2e/tests/playwright.config.mjs`
- Base URL: `http://localhost:8091` (`gateway-pifc` nginx 리버스 프록시 — 스토리지 REST 동일 출처 프록시 용도)
- Supabase REST URL: `http://localhost:54321/rest/v1`
- 환경: docker (Docker Compose 기반 `db`/`kong`/`rest`/`storage-pifc`/`imgproxy-pifc`/`completion-polling-pifc`/`gateway-pifc`)

## 분류 근거 (Real-Frontend Rule 면제)
본 명세는 사용자가 직접 트리거하는 UI 액션이 없는 백그라운드 폴링 워커 계약입니다. 실제 프런트엔드의 `services/frontend/src/components/apps/todolist/InstanceSource.vue` (라우트 `/instancelist/:instId` 의 "소스" 탭) 가 `proc_inst_source` 카드를 표시하지만, 현재 워커 구현(`file_cleanup_service.py:223-224`)이 `update_proc_inst_cleanup_status` 의 실제 UPDATE 를 주석 처리해두었고 `proc_inst_source` 행 자체도 삭제하지 않습니다. 따라서 정리 사이클 전·후의 InstanceSource.vue 카드 목록이 동일하여 사용자가 인지할 수 있는 결정적 UI 전이가 존재하지 않습니다. Real-Frontend Rule 에 따라 합성 tester 페이지 우회는 금지되며 본 스위트는 protocol-level `request` 검증 + 스크린샷 면제로 분류됩니다. 이전 구현이 사용하던 인라인 `VIEWER_HTML` 블록과 합성 스크린샷은 제거되었습니다.

## 입력
- 커버리지 매트릭스: `openspec/specs/completion_process-instance-file-cleanup/e2e/scenarios/00-coverage-matrix.md`
- 시나리오 문서: 01, 02 (둘 다 Category B 분류)
- Playwright 명세: `openspec/specs/completion_process-instance-file-cleanup/e2e/tests/completion_process-instance-file-cleanup.spec.mjs` (protocol-only, `request` fixture 만 사용)
- Docker compose: `docker-compose.e2e.yml` (서비스 `imgproxy-pifc`, `storage-pifc`, `db-seed-pifc`, `storage-seed-pifc`, `completion-polling-pifc`, `gateway-pifc`)
- Coverage Dockerfile: `openspec/specs/completion_process-instance-file-cleanup/e2e/docker/Dockerfile.pifc-coverage`
- Nginx 게이트웨이 설정: `openspec/specs/completion_process-instance-file-cleanup/e2e/docker/nginx.e2e.conf`
- 폴링 엔트리포인트: `openspec/specs/completion_process-instance-file-cleanup/e2e/scripts/polling_entrypoint.py`
- 스토리지 시드 스크립트: `openspec/specs/completion_process-instance-file-cleanup/e2e/scripts/seed_storage_objects.sh`

## Sanity Check
| 점검 | 결과 | 비고 |
| --- | --- | --- |
| `docker compose -f docker-compose.e2e.yml config` | passed | 새 서비스 6개 인식 |
| `db`, `kong`, `rest`, `frontend` | healthy/running | 기존 인프라 재사용 |
| `storage-pifc` 헬스체크 | healthy | supabase/storage-api 5000 포트 `/status` |
| `db-seed-pifc` 종료 코드 | 0 | 테넌트(localhost), 버킷, COMPLETED 인스턴스, proc_inst_source 시드 |
| `storage-seed-pifc` 종료 코드 | 0 | `pifc/completed.txt`, `pifc/keep.txt` 업로드 성공 |
| `curl http://localhost:8091/storage/v1/object/public/files/pifc/keep.txt` | 200 `pifc-keep-content` | 게이트웨이→kong→storage 경로 정상 |
| 폴링 워커 로그 | `Found 1 completed process instances` → `Successfully deleted file from storage: pifc/completed.txt` → `Cleanup completed: 1 files deleted, 1 instances marked as cleaned` | `file_cleanup_polling_task(polling_interval=3)` 정상 동작 |

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed |
| 통과 테스트 | 2 |
| 실패 테스트 | 0 |
| 건너뛴 테스트 | 0 |

## 산출물
- JSON 리포트: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/results.json`
- HTML 리포트: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/html-report/index.html`
- 스펙 커버리지 HTML 리포트: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/backend-coverage/` (`coverage.xml`, `html/index.html`)
- 프론트엔드 커버리지: 본 명세는 Category B 로 사용자 UI 액션이 없으므로 프론트엔드 커버리지 수집 대상이 아닙니다. 사용자가 첨부 파일 카드를 보는 화면(`InstanceSource.vue`)은 본 스위트가 검증하는 정리 동작과 결정적으로 동기화되지 않아 커버리지 측정 단위로 의미가 없습니다.
- 응답 캡처 (스크린샷 대체 증거): `openspec/specs/completion_process-instance-file-cleanup/e2e/results/artifacts/`
  - `01-completed-file-final-response.json` — 정리 후 최종 GET 응답 (status + 본문 일부)
  - `01-storage-listing-after-cleanup.json` — 정리 후 prefix 스토리지 list
  - `02-storage-listing-no-target.json` — 폴링 다수 사이클 후 prefix 스토리지 list

## 스크린샷 맵
| 항목 | 값 |
| --- | --- |
| 분류 | Category B — 백엔드/폴링 전용 계약 |
| 스크린샷 체크포인트 수 | 0 (Real-Frontend Rule 면제, 매뉴얼은 위 응답 캡처 JSON 인용으로 대체) |
| 이전 합성 스크린샷 처리 | `process-gpt-completion_process-instance-file-cleanup-01-file-visible.png` / `-01-file-deleted.png` / `-02-keeper-stable.png` 3건 삭제됨 (인라인 `VIEWER_HTML` 주입으로 생성된 합성 화면이라 Real-Frontend Rule 위반) |

## 검증
- 출력 검증기: passed
- Playwright: passed (2/2, protocol-only)
- Docker compose config: passed
- OpenSpec 추적성 게이트: passed
- 백엔드 coverage 게이트: passed (`file_cleanup_service.py` 핵심 happy path 와 no-op 분기 모두 커버됨)
- 프론트엔드 coverage 보조 게이트: not-applicable (Category B 분류)
- AI 스펙 커버리지 판단: sufficient

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | 1/1 requirements, 2/2 spec scenarios, 2/2 playwright tests, 0/0 screenshots (Category B 면제) | 충분 |
| 백엔드 | `services/completion/polling_service/file_cleanup_service.py` | 핵심 경로(`parse_storage_url`, `fetch_completed_process_instances`, `fetch_proc_inst_sources`, `check_file_exists_in_storage`, `delete_file_from_storage`, `update_proc_inst_cleanup_status`, `cleanup_completed_process_files`, `file_cleanup_polling_task`) 모두 적어도 한 차례씩 실행됨 | 충분 (미커버 분기는 예외/실패 주입 경로 한정) |
| 프론트엔드 | 해당 없음 (Category B) | N/A | 본 명세는 백엔드 폴링 워커 계약이며 결정적 UI 전이가 없음 |

## Phase 병렬 실행 메모
- Phase A/B/C/D 는 순차 실행했습니다.
- Phase E 는 (1) Playwright 실행, (2) `completion-polling-pifc` 컨테이너 SIGTERM 보내 coverage flush, (3) 출력 검증기, (4) OpenSpec 추적성 게이트 + HTML 리포트 생성 순으로 진행했습니다. (1)/(2) 는 같은 폴링 컨테이너를 공유하므로 직렬화했고, (3)/(4) 는 결과 파일 의존성으로 (1)/(2) 후에 실행했습니다.

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| `update_proc_inst_cleanup_status` 의 실제 DB UPDATE 가 코드상 주석 처리되어 있음 (`response = True` 로 단락) | 폴링이 동일 인스턴스를 반복적으로 클레임하지만 두 번째 사이클부터 `check_file_exists_in_storage` 가 False 를 반환하여 부작용은 없음. 다만 명세가 함의하는 "한 번 정리한 인스턴스는 다음 사이클에 제외" 가 DB 수준에서는 보장되지 않으며, 이것이 본 스위트가 Category B 로 분류되는 핵심 사유 중 하나임 (proc_inst_source 가 삭제되지 않아 InstanceSource.vue 화면이 변하지 않음) | 코드에서 update 라인 활성화 + `proc_inst_source` 삭제 로직 추가 후 본 스위트를 사용자-facing 시나리오 (Category A) 로 재분류 가능. 이 경우 InstanceSource.vue 의 카드 사라짐을 실제 UI 액션으로 검증 |
| 멀티 테넌트 동시 정리 | 단일 테넌트(`localhost`) 만 시드함 | 테넌트 격리 회귀가 필요해지면 별도 시나리오로 분리 |
| 스토리지 삭제 실패 재시도 | `all_files_deleted=False` 분기는 실제 스토리지 오류 주입이 필요 | mock storage 또는 단위 테스트로 보강 |
| `subdomain_var.set` 경로 (운영에서 Subdomain 헤더로 tenant 분리) | 폴링 단일 실행이라 기본값 `localhost` 만 사용함 | 운영 traffic 패턴 회귀 시 별도 통합 테스트 |

## 메모리 캡처
- 본 재작성 작업 자체에서 새 메모리는 추가하지 않습니다 ("Real-Frontend Rule 위반 정리 + Category B 분류" 는 스킬 워크플로의 일반 절차이며 이 저장소 고유의 함정이 아닙니다). 기존 메모리 `file-cleanup-tenant-localhost-default`, `coverage-py-usr2-flush`, `kong-storage-route-hardcoded-hostname` 은 이번 실행에서도 유효함을 확인했습니다.
