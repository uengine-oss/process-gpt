# E2E Documentation Templates

Use these templates exactly. Write section headings, scenario titles, table headers, checklist text, scenario descriptions, steps, and expected results in Korean. Keep technical identifiers such as file paths, OpenSpec requirement titles, API paths, event names, and code field names exact when they are part of the verified contract.

Keep headings stable so reports remain comparable across suites and the validator can check Korean documentation consistently.

## `00-coverage-matrix.md`

```markdown
# <스위트 이름> E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `<suite-slug>`
- 원본 명세:
  - `openspec/specs/<spec-name>/spec.md`
- Playwright 명세: `<frontend-folder>/e2e/<suite-slug>/<suite-slug>.spec.mjs`
- 결과 디렉터리: `e2e/<suite-slug>/e2e-results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-<scenario-slug>.md` | `<정확한 테스트 제목>` | <짧은 동작 설명> |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `<spec-name>` | <요구사항 제목> | SHALL/MUST/SHOULD | 01 | <비워두거나 짧은 메모> |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `<spec-name>` | <요구사항 제목> | <시나리오 제목> | 01 | UI 입력/버튼/진행 상태/결과 화면/오류 화면 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 없음 | - | - |

## 체크리스트
- [ ] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [ ] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [ ] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다.
- [ ] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [ ] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
```

## `NN-<scenario-slug>.md`

```markdown
# E2E 시나리오 NN: <시나리오 제목>

## 메타데이터
- 스위트 슬러그: `<suite-slug>`
- 시나리오 ID: `NN`
- Playwright 테스트 제목: `<정확한 테스트 제목>`
- 원본 명세:
  - `openspec/specs/<spec-name>/spec.md`

## 목적
<사용자에게 보이는 동작과 계약 리스크를 설명하는 한 문단>

## 사전 조건
- <서비스, fixture, seed 또는 route stub 조건>
- <인증 또는 환경 조건이 있으면 작성>

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| <이름> | fixture/route/seed | `<path-or-route>` | <필요한 이유> |

## 절차
1. <사용자가 화면에 진입합니다>
2. <사용자가 입력창에 값을 입력하거나 옵션을 선택합니다>
3. <사용자가 버튼을 눌러 작업을 실행합니다>
4. <사용자가 화면 변화, 추가 입력 요청, 결과, 오류, 취소, 피드백 등 다음 동작을 수행합니다>

## 기대 결과
- <사용자가 화면에서 관찰할 수 있는 진행 상태, 결과, 오류, 빈 결과, 추가 입력 요청, 취소 상태, 피드백 완료 상태>
- <필요한 경우 브라우저 UI를 통해 발생한 요청/stream/report 또는 저장 상태 검증>

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `<spec-name>` | <요구사항 제목> | <시나리오 제목 또는 "-"> |

## 산출물
- 스크린샷 체크포인트:
  | 체크포인트 | 캡처할 UI 상태 | 예상 파일 | 매뉴얼용 캡션 |
  | --- | --- | --- | --- |
  | `<checkpoint-name>` | <사용자가 이해할 수 있는 화면 상태> | `<project>-<suite-slug>-NN-<checkpoint-name>.png` | <짧은 한국어 캡션> |
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `e2e/<suite-slug>/e2e-results/results.json`
```

## `execution-summary.md`

```markdown
# <스위트 이름> E2E 실행 요약

## 실행 메타데이터
- 스위트 슬러그: `<suite-slug>`
- 날짜: YYYY-MM-DD
- 명령: `<정확한 명령>`
- Base URL: `<base URL 또는 Docker service URL>`
- 환경: local/docker/CI

## 입력
- 커버리지 매트릭스: `e2e/<suite-slug>/e2e_senarios/<suite-slug>/00-coverage-matrix.md`
- Playwright 명세: `<frontend-folder>/e2e/<suite-slug>/<suite-slug>.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` 또는 `N/A`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed/failed/not-run |
| 통과 테스트 | <number> |
| 실패 테스트 | <number> |
| 건너뛴 테스트 | <number> |

## 산출물
- JSON 리포트: `e2e/<suite-slug>/e2e-results/results.json`
- HTML 리포트: `e2e/<suite-slug>/e2e-results/html-report/index.html`
- 스크린샷: `e2e/<suite-slug>/e2e-results/screenshots/`
- 산출물: `e2e/<suite-slug>/e2e-results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `<checkpoint-name>` | `e2e/<suite-slug>/e2e-results/screenshots/<file>.png` | <짧은 한국어 캡션> |

## 검증
- 출력 검증기: passed/failed/not-run
- Playwright: passed/failed/not-run
- Docker compose config: passed/failed/not-applicable

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 없음 | - | - |
```
