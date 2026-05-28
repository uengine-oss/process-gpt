# E2E 시나리오 02: 정리 대상 없음

## 메타데이터
- 스위트 슬러그: `completion_process-instance-file-cleanup`
- 원본 명세 ID: `completion_process-instance-file-cleanup`
- 시나리오 ID: `02`
- 분류: **Category B — 백엔드/폴링 전용 계약 (스크린샷 면제)**
- Playwright 테스트 제목: `정리 대상 인스턴스가 없으면 폴링 주기는 삭제 없이 다음 주기를 기다린다`
- 원본 명세:
  - `openspec/specs/completion_process-instance-file-cleanup/spec.md`

## 목적
완료되었고 정리되지 않은 프로세스 인스턴스가 더 이상 없을 때 폴링 주기가 도래하더라도 시스템이 무관한 파일을 건드리지 않고 다음 주기를 기다리는 안전성(파괴적 부작용 없음)을 보장한다.

## Real-Frontend Rule 면제 사유
시나리오 01 과 동일한 사유로 본 시나리오도 Category B 로 분류됩니다. 폴링이 "아무 것도 하지 않음"을 표현하는 결정적 UI 전이가 실제 프런트엔드에 존재하지 않으므로 (`InstanceSource.vue` 는 어떠한 폴링 결과도 사용자에게 시각적으로 통지하지 않습니다) 합성 tester 페이지 우회는 금지되며 스크린샷 면제가 적용됩니다.

## 사전 조건
- 시나리오 01 이 먼저 실행되어 유일한 COMPLETED+미정리 인스턴스의 소스 파일이 이미 삭제되어 있다.
- 보존 객체 `pifc/keep.txt` 가 스토리지에 그대로 존재한다.
- 폴링 워커가 계속 실행 중이며 짧은 주기(3초) 로 cleanup_completed_process_files 를 호출한다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `pifc/keep.txt` | storage object | 버킷 `files`, 키 `pifc/keep.txt` | 폴링이 함부로 건드리지 않는 것을 확인할 보존 객체 |
| 추가 시드 없음 | - | - | 시나리오 01 이후 상태를 그대로 사용 |

## 절차 (Playwright `request` protocol-level)
1. 초기 상태 검증: `GET /storage/v1/object/public/files/pifc/keep.txt` 가 `200` 응답이며 본문에 `pifc-keep-content` 가 포함된다.
2. 폴링 사이클 대기: 폴링 주기(3초) 가 최소 4회 도래하도록 12초를 대기한다.
3. 재조회 검증: 동일 GET 이 다시 `200` 응답이며 본문이 동일하다.
4. 스토리지 list 검증: `POST /storage/v1/object/list/files` body `{prefix:"pifc"}` 응답에 `keep.txt` 가 여전히 존재한다 (`02-storage-listing-no-target.json` 산출).

## 기대 결과
- 두 차례 모두 `pifc/keep.txt` 가 `200` 응답으로 동일 본문을 반환한다.
- 스토리지 list 결과에 `keep.txt` 가 여전히 존재하며 추가 삭제가 일어나지 않음.

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_process-instance-file-cleanup` | 완료 인스턴스 첨부 파일 정리 | 정리 대상 없음 |

## 산출물
- 응답 캡처 JSON (스크린샷 대체 증거):
  | 산출물 | 의미 |
  | --- | --- |
  | `e2e/results/artifacts/02-storage-listing-no-target.json` | 폴링 사이클 다수 도래 후 prefix 스토리지 list — `keep.txt` 유지 증거 |
- 스크린샷 체크포인트: 본 시나리오는 Category B 분류로 스크린샷 면제이며, UI 캡처 산출물은 정의하지 않습니다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_process-instance-file-cleanup/e2e/results/results.json`
