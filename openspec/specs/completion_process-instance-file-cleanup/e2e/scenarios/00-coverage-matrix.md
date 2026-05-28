# 프로세스 인스턴스 파일 정리 E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_process-instance-file-cleanup`
- 원본 명세 ID: `completion_process-instance-file-cleanup`
- 원본 명세:
  - `openspec/specs/completion_process-instance-file-cleanup/spec.md`
- 백엔드/제품 계약:
  - 폴링 워커 엔트리포인트: `services/completion/polling_service/file_cleanup_service.py` 의 `file_cleanup_polling_task`, `cleanup_completed_process_files`
  - 파일 정리 유틸: `parse_storage_url`, `fetch_completed_process_instances`, `fetch_proc_inst_sources`, `check_file_exists_in_storage`, `delete_file_from_storage`, `update_proc_inst_cleanup_status`
  - 데이터 계약: `public.bpm_proc_inst(proc_inst_id, status, is_clean_up, tenant_id)`, `public.proc_inst_source(id, proc_inst_id, file_path)`
  - 외부 boundary: Supabase Storage REST (`/storage/v1/object/list/{bucket}`, `/storage/v1/object/{bucket}`) — E2E는 실제 `supabase/storage-api` 컨테이너 사용. LLM 의존성 없음.
- **분류: Category B — 백엔드/폴링 전용 계약 (스크린샷 면제)**. 본 명세는 사용자가 직접 트리거하는 UI 액션이 없는 백그라운드 폴링 워커 계약입니다. 실제 프런트엔드에는 `services/frontend/src/components/apps/todolist/InstanceSource.vue` (라우트 `/instancelist/:instId` 의 "소스" 탭) 가 `proc_inst_source` 카드를 표시하지만, 현재 워커(`file_cleanup_service.py:223-224`)는 `update_proc_inst_cleanup_status` 의 실제 UPDATE 가 주석 처리되어 있고 `proc_inst_source` 행도 삭제하지 않으므로 정리 사이클 전·후의 화면이 동일합니다. 사용자가 인지할 수 있는 결정적 UI 전이가 존재하지 않아 Real-Frontend Rule 의 "no real frontend path" 조항에 따라 합성 tester 페이지 우회는 금지되며 스크린샷이 면제됩니다. 사용자 가치 검증은 스토리지 객체의 200→404 전환과 list 응답 변화를 protocol-level `request` 로 확인하는 것으로 대체됩니다.
- E2E 루트: `openspec/specs/completion_process-instance-file-cleanup/e2e/`
- Playwright 명세: `openspec/specs/completion_process-instance-file-cleanup/e2e/tests/completion_process-instance-file-cleanup.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/`

## 재사용 산출물
- `docker-compose.e2e.yml`: 기존 `db`, `kong`, `rest` 인프라 재사용. 본 스위트용으로 (a) `storage` + `imgproxy` (Supabase 스토리지), (b) `completion-polling-pifc` (file_cleanup 만 짧은 주기로 실행하는 폴링 워커, coverage instrumented), (c) `db-seed-pifc` (인스턴스/소스/스토리지 객체 시드) 를 추가한다.
- 메모리 [[coverage-py-usr2-flush]]: file_cleanup_polling_task 도 장기 실행 asyncio 루프이므로 동일 패턴(SIGTERM trap + coverage combine/xml/html)을 적용한다.
- 메모리 [[compose-override-relative-paths]]: spec-local volume 마운트는 repo 루트 기준 상대 경로(`./openspec/specs/...`)를 사용한다.
- 알림 푸시 스위트(`completion_notification-push-delivery`)의 Dockerfile.fcm-coverage 패턴을 참고해 본 스위트용 `Dockerfile.pifc-coverage` 를 작성한다.

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-completed-instance-file-deletion.md` | `완료된 프로세스 인스턴스의 스토리지 파일은 폴링 주기 후 삭제된다` | 시드 → 스토리지 GET 200 → 폴링 → 스토리지 GET 400/404 + list 에서 `completed.txt` 제거 (`keep.txt` 유지) |
| 02 | `02-no-cleanup-targets.md` | `정리 대상 인스턴스가 없으면 폴링 주기는 삭제 없이 다음 주기를 기다린다` | 시나리오 01 종료 상태에서 12초 대기 → `keep.txt` GET 이 200 유지, list 에 `keep.txt` 유지 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_process-instance-file-cleanup` | 완료 인스턴스 첨부 파일 정리 | SHALL | 01, 02 | 01 은 삭제 happy path, 02 는 no-op 분기 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_process-instance-file-cleanup` | 완료 인스턴스 첨부 파일 정리 | 완료 인스턴스 파일 삭제 | 01 | 스토리지 객체 GET 200→400/404 전환 + list 응답에서 객체 제거 (protocol-only, Category B) |
| `completion_process-instance-file-cleanup` | 완료 인스턴스 첨부 파일 정리 | 정리 대상 없음 | 02 | 폴링 다수 사이클 도래 후에도 `keep.txt` GET 200 유지 + list 유지 (protocol-only, Category B) |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/polling_service/file_cleanup_service.py` | `file_cleanup_polling_task`, `cleanup_completed_process_files`, `fetch_completed_process_instances`, `fetch_proc_inst_sources`, `parse_storage_url`, `check_file_exists_in_storage`, `delete_file_from_storage`, `update_proc_inst_cleanup_status` | 완료 인스턴스 첨부 파일 정리 | line >= 70%, function >= 80% | 명세가 정의하는 모든 행위(주기 폴링, 인스턴스 조회, 소스 조회, URL 파싱, 스토리지 존재 확인, 스토리지 삭제, 상태 업데이트)를 1:1 로 구현하는 단일 파일 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/frontend/src/components/apps/todolist/InstanceSource.vue` | 라우트 `/instancelist/:instId` 의 "소스" 탭이 `proc_inst_source` 행을 카드로 표시 | 완료 인스턴스 첨부 파일 정리 | N/A (Category B 스크린샷 면제) | 사용자에게 첨부 파일이 노출되는 단 하나의 표면이지만, 워커가 현재 `proc_inst_source` 행을 삭제하지 않고 `is_clean_up` UPDATE 도 주석 처리되어 있어 정리 사이클 전·후 화면이 동일하게 표시된다. 결정적 UI 전이가 없으므로 Real-Frontend Rule 에 따라 합성 tester 페이지 우회는 금지되며 스크린샷이 면제된다. |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| `is_clean_up=true` 업데이트의 실제 DB 반영 | `update_proc_inst_cleanup_status` 의 실제 `supabase.update` 호출이 주석 처리되어 있고 `response = True` 로 단락된다. 시나리오는 함수가 호출되는 사실까지만 검증하며 DB 컬럼 변경은 검증하지 않는다. | 코드에서 주석 처리 해제 후 본 스위트의 DB 검증을 활성화하거나 별도 후속 변경에서 다루어야 한다. |
| 멀티 테넌트 동시 정리 | `subdomain_var` 가 `localhost` 가 아닐 때만 tenant_id 로 필터링하며 본 스위트는 단일 테넌트만 시드한다. | 테넌트 격리 회귀가 필요해지면 별도 시나리오로 분리. |
| 스토리지 삭제 실패 재시도 | `all_files_deleted=False` 분기는 실제 스토리지 오류 주입이 필요하다. | 실패 주입은 단위 테스트나 mock storage 가 추가될 때 별도 케이스로 보강. |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐(완료 인스턴스 파일 정리) 범위입니다.
- [x] 원본 명세의 서비스 접두어(`completion`) 와 도메인 구분자(`process-instance-file-cleanup`) 는 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다 (`completion-polling-pifc` 워커 + Supabase storage + bpm_proc_inst/proc_inst_source).
- [x] 스위트 슬러그가 원본 명세 ID 와 동일합니다.
- [x] E2E 시나리오/테스트/seed/결과는 `openspec/specs/completion_process-instance-file-cleanup/e2e/` 아래에 응집되어 있습니다.
- [x] 본 명세는 Category B (백엔드/폴링 전용 계약) 로 분류되어 사용자-facing UI 액션이 없으며, 검증은 protocol-level `request` 호출로 수행됩니다. Real-Frontend Rule 면제 사유는 각 시나리오 문서 및 위 "분류" 항목에 기록되어 있습니다.
- [x] Category B 분류로 스크린샷 체크포인트가 정의되지 않습니다. 매뉴얼 재사용 증거는 `e2e/results/artifacts/*.json` 응답 캡처로 제공됩니다.
- [x] 스펙 관련 백엔드 파일/함수가 코드 표면 표에 기록되어 있습니다. 프론트엔드 표면 없음 사유를 명시했습니다.
- [x] 커버리지 기준이 스펙 관련 `file_cleanup_service.py` 에 한정되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
