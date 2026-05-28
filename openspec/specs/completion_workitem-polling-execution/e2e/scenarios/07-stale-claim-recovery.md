# E2E 시나리오 07: 정체된 처리 클레임 회수

## 메타데이터
- 스위트 슬러그: `completion_workitem-polling-execution`
- 원본 명세 ID: `completion_workitem-polling-execution`
- 시나리오 ID: `07`
- Playwright 테스트 제목: `30분 이상 갱신되지 않은 SUBMITTED 워크아이템의 클레임이 정리 주기에 의해 해제된다`
- 원본 명세:
  - `openspec/specs/completion_workitem-polling-execution/spec.md`
- 상태: **보류** (`cleanup_task` 5분 주기 + 시계 시드 의존)

## 목적
`cleanup_task` (polling_service.py:177–190) 가 5분 주기로 `cleanup_stale_consumers` (database.py:935–964) 를 호출해 `status='SUBMITTED'` 이면서 `consumer IS NOT NULL` 이고 `updated_at < now() - interval '30 minutes'` 인 워크아이템의 `consumer` 를 NULL 로 해제한다. 사용자 화면에서는 정체되어 있던 워크아이템이 다시 SUBMITTED 컬럼에 노출되는 것으로 검증된다.

## 사전 조건
- 본 스위트 고유 시드:
  - `todolist` 행: `status='SUBMITTED'`, `consumer='stuck-pod-x'`, `updated_at = now() - interval '31 minutes'` 로 직접 주입.
- 다음 중 하나의 단축 경로가 필요합니다:
  - 옵션 A: 폴링 워커 코드에 환경변수 기반 cleanup 주기 단축(`CLEANUP_INTERVAL_SECONDS` 등)을 추가하거나 본 스위트 전용 image override 로 5분 → 30초 변경.
  - 옵션 B: `docker exec` 로 `cleanup_stale_consumers` 를 직접 트리거하는 Python REPL 호출.
  - 옵션 C: 5분 이상 대기 후 검증 (E2E 결정성 저하).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `e2e_seed.sql` | seed | `openspec/specs/completion_workitem-polling-execution/e2e/seed_files/e2e_seed.sql` | 정체 워크아이템 시드 (`updated_at = now() - interval '31 minutes'`) |
| 폴링 워커 환경변수 또는 docker exec 트리거 | infra | `docker-compose.e2e.yml` override 또는 Playwright `spawnSync('docker', ['exec', ...])` | cleanup 주기 단축 또는 즉시 트리거 |

## 절차
1. 사용자가 로그인 후 `/todolist` 에 진입합니다.
2. 정체 워크아이템이 KanbanBoard 의 SUBMITTED 컬럼에 노출되나 폴링 워커는 `consumer != NULL` 이므로 즉시 처리하지 않습니다.
3. Cleanup 트리거 (옵션 A/B/C 중 하나) 가 발생합니다.
4. 사용자가 새로고침해 워크아이템의 `consumer` 가 해제되고 다음 폴링 사이클에 다시 픽업됨을 확인합니다.

## 기대 결과
- Cleanup 실행 직후 DB 의 `todolist.consumer IS NULL` 로 갱신됩니다.
- 폴링 워커가 다음 사이클(5초)에 워크아이템을 재픽업해 처리합니다 (카드가 IN_PROGRESS 또는 DONE 컬럼으로 이동).
- 폴링 워커 로그에 `[INFO] Cleaned up N stale consumers` 메시지가 기록됩니다.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_workitem-polling-execution` | 정체된 처리 클레임 회수 | 정체 워크아이템 회수 |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `07-stale-initial` | 정체 워크아이템이 SUBMITTED 컬럼에 보이지만 처리되지 않은 상태 | `process-gpt-completion_workitem-polling-execution-07-stale-initial.png` | 정체된 워크아이템 초기 상태 |
  | `07-after-cleanup` | cleanup 실행 후 워크아이템이 다시 처리되어 IN_PROGRESS/DONE 컬럼으로 이동한 상태 | `process-gpt-completion_workitem-polling-execution-07-after-cleanup.png` | 정체 클레임 회수 후 재처리된 상태 |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_workitem-polling-execution/e2e/results/results.json`.

## 보류 사유
`cleanup_task` 의 5분 주기와 30분 stale 기준은 E2E 의 결정성·실행 시간 측면에서 불리하다. 옵션 A 는 production 코드 변경을, 옵션 B 는 폴링 워커 내부 함수의 외부 트리거를 요구하므로 둘 다 침습적이다. 옵션 C 는 결정성을 해친다. 본 시나리오는 단위/통합 테스트(`tests/test_cleanup_stale_consumers.py` 등) 에서 `cleanup_stale_consumers` 를 직접 호출하는 형태가 더 적합할 가능성이 있다. E2E 활성화 시에는 옵션 A 또는 B 의 침습성을 받아들이는 결정이 선행되어야 한다.
