# E2E 시나리오 01: 완료 인스턴스 첨부 파일 삭제

## 메타데이터
- 스위트 슬러그: `completion_process-instance-file-cleanup`
- 원본 명세 ID: `completion_process-instance-file-cleanup`
- 시나리오 ID: `01`
- 분류: **Category B — 백엔드/폴링 전용 계약 (스크린샷 면제)**
- Playwright 테스트 제목: `완료된 프로세스 인스턴스의 스토리지 파일은 폴링 주기 후 삭제된다`
- 원본 명세:
  - `openspec/specs/completion_process-instance-file-cleanup/spec.md`

## 목적
COMPLETED 상태이고 아직 정리되지 않은 프로세스 인스턴스에 첨부된 Supabase Storage 파일이 폴링 주기 도래 후 실제 스토리지에서 삭제되는 백엔드 계약을 보장한다.

## Real-Frontend Rule 면제 사유
본 명세는 사용자가 직접 트리거하는 UI 액션이 없습니다. 백그라운드 `file_cleanup_polling_task` 가 자체 일정으로 실행되며 사용자 입력을 받지 않습니다.

실제 프런트엔드에는 `proc_inst_source` 행을 카드로 보여주는 표면 `services/frontend/src/components/apps/todolist/InstanceSource.vue` (라우트 `/instancelist/:instId` 의 "소스" 탭) 가 존재하지만, 현재 워커 구현(`services/completion/polling_service/file_cleanup_service.py:223-224`)은 `update_proc_inst_cleanup_status` 의 실제 `supabase.update` 호출이 주석 처리되어 있고 `proc_inst_source` 행 자체도 삭제하지 않습니다. 그 결과 정리 사이클 전·후에 InstanceSource.vue 가 표시하는 카드 목록은 동일하며, 사용자가 화면에서 인지할 수 있는 UI 전이가 존재하지 않습니다 (다운로드 버튼을 클릭해 새 탭을 열어야만 200→404 차이를 확인할 수 있는데, 이는 정리 사이클과 결합된 결정적 UI 전이가 아닙니다).

`.claude/skills/e2e-tests/SKILL.md` 의 Real-Frontend Rule 에 따라 인공 tester 페이지를 주입해 합성 화면을 만드는 우회는 금지되며, 사용자-인지 가능한 UI 표현이 부재할 때는 백엔드/폴링 전용 계약 + 스크린샷 면제로 분류하도록 명시되어 있습니다. 본 시나리오는 그 분류에 해당합니다.

따라서 본 시나리오는 protocol-level `request` 검증만 수행하며, UI 스크린샷 체크포인트를 정의하지 않습니다. 매뉴얼에서 해당 백엔드 동작을 설명할 때 사용할 수 있는 산출물은 결과 디렉터리의 JSON 응답 캡처입니다.

## 사전 조건
- `db`(Supabase Postgres), `kong`, `rest`, `storage-pifc`(supabase/storage-api), `imgproxy-pifc` 컨테이너가 healthy 상태.
- `db-seed-pifc` 시드가 완료되어 (a) 테넌트 `localhost`, (b) 버킷 `files` 와 두 개의 시드 객체 `pifc/completed.txt`(COMPLETED 인스턴스 첨부), `pifc/keep.txt`(미사용 - 시나리오 02 의 비교용), (c) `bpm_proc_inst` 에 `status=COMPLETED, is_clean_up=false` 인스턴스 1건과 `proc_inst_source` 에 그 파일을 가리키는 URL 1건이 삽입되어 있어야 한다. 본 테스트는 매 실행마다 이 상태를 명시적으로 재시드한다.
- `completion-polling-pifc` 워커가 `file_cleanup_polling_task(polling_interval=3)` 를 실행 중이며 coverage instrumented.
- 게이트웨이 `gateway-pifc` 가 :8091 에서 접근 가능 (스토리지 REST 동일 출처 프록시 용도).

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `pifc/completed.txt` | storage object | 버킷 `files`, 키 `pifc/completed.txt` | 폴링이 삭제해야 하는 첨부 파일 |
| `proc_inst_source` 시드 행 | DB seed | `public.proc_inst_source` | file_path 가 `http://kong:8000/storage/v1/object/public/files/pifc/completed.txt` |
| `bpm_proc_inst` 시드 행 | DB seed | `public.bpm_proc_inst` | `status=COMPLETED, is_clean_up=false, tenant_id=localhost` |
| 게이트웨이 nginx | reverse proxy | `:8091` → `frontend` + `/storage/v1/* → kong:8000` | 동일 출처 스토리지 REST 호출 |

외부 boundary 에 대한 stub 은 없습니다. 모든 호출은 실제 in-repo 인프라(`db`, `kong`, `storage-pifc`, `completion-polling-pifc`)로 흘러갑니다.

## 절차 (Playwright `request` protocol-level)
1. 시드 리셋: storage REST 로 `pifc/completed.txt` 객체를 다시 업로드하고, Supabase REST 로 `bpm_proc_inst.is_clean_up=false`/`status=COMPLETED`/`tenant_id=localhost` 로 되돌리며, `proc_inst_source` 행을 다시 삽입한다.
2. 정리 전 검증: `GET /storage/v1/object/public/files/pifc/completed.txt` 가 `200` 응답이고 본문에 `pifc-completed-content` 가 포함된다.
3. 폴링 사이클 대기: 동일 URL 을 2초 간격으로 폴링하며 최대 90초 안에 `400` 또는 `404` 가 반환되는 시점을 기록한다 (`01-completed-file-final-response.json` 산출).
4. 정리 후 스토리지 list 검증: `POST /storage/v1/object/list/files` body `{prefix:"pifc"}` 응답에서 `completed.txt` 가 사라지고 `keep.txt` 는 여전히 존재한다 (`01-storage-listing-after-cleanup.json` 산출).

## 기대 결과
- 1차 GET 응답이 `200` + 본문 `pifc-completed-content`.
- 폴링 사이클 이후 동일 GET 이 `400` 또는 `404` (Supabase storage 는 객체 부재 시 `400` 을 반환할 수 있어 두 값 모두 허용).
- 스토리지 list 응답에 `completed.txt` 가 사라지고 `keep.txt` 는 존재.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-instance-file-cleanup` | 완료 인스턴스 첨부 파일 정리 | 완료 인스턴스 파일 삭제 |

## 산출물
- 응답 캡처 JSON (스크린샷 대체 증거):
  | 산출물 | 의미 |
  | --- | --- |
  | `e2e/results/artifacts/01-completed-file-final-response.json` | 정리 후 최종 GET 응답 상태/본문 — 매뉴얼에서 "삭제됨" 증거로 인용 |
  | `e2e/results/artifacts/01-storage-listing-after-cleanup.json` | 정리 후 prefix 스토리지 list — `completed.txt` 부재, `keep.txt` 유지 증거 |
- 스크린샷 체크포인트: 본 시나리오는 Category B 분류로 스크린샷 면제이며, UI 캡처 산출물은 정의하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/results.json`
