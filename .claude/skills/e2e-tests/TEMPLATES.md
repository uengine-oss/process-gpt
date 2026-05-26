# E2E Documentation Templates

Use these templates exactly. Write section headings, scenario titles, table headers, checklist text, scenario descriptions, steps, expected results, execution notes, and copied OpenSpec meaning in Korean. Translate human-readable OpenSpec requirement/scenario names into Korean unless they are stable technical identifiers. Keep only technical identifiers such as file paths, requirement IDs, API paths, event names, enum values, SQL keywords, and code field names exact when they are part of the verified contract.

Keep headings stable so reports remain comparable across suites and the validator can check Korean documentation consistently.

## `00-coverage-matrix.md`

```markdown
# <스위트 이름> E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `<suite-slug>`
- 원본 명세 ID: `<spec-name>` <!-- `<microservice>_<domain>-<feature>` 또는 `<microservice>_<feature>` 형식이면 스위트 슬러그와 동일하게 유지합니다. 예: `completion_agent-memory-chat`, `billing_invoice-search` -->
- 원본 명세:
  - `openspec/specs/<spec-name>/spec.md`
- 백엔드/제품 계약:
  - <owning backend service, API/gateway route, stream/event, persistence, auth, job, or data contract>
- E2E 루트: `openspec/specs/<spec-name>/e2e/`
- Playwright 명세: `openspec/specs/<spec-name>/e2e/tests/<suite-slug>.spec.mjs`
- 결과 디렉터리: `openspec/specs/<spec-name>/e2e/results/`

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
- [ ] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [ ] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [ ] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [ ] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [ ] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [ ] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [ ] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/<spec-name>/e2e/` 아래에 응집되어 있습니다.
- [ ] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다.
- [ ] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다.
- [ ] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
```

## `NN-<scenario-slug>.md`

```markdown
# E2E 시나리오 NN: <시나리오 제목>

## 메타데이터
- 스위트 슬러그: `<suite-slug>`
- 원본 명세 ID: `<spec-name>`
- 시나리오 ID: `NN`
- Playwright 테스트 제목: `<정확한 테스트 제목>`
- 원본 명세:
  - `openspec/specs/<spec-name>/spec.md`

## 목적
<사용자에게 보이는 동작과 계약 리스크를 설명하는 한 문단>

## 사전 조건
- <frontend, gateway/reverse proxy, owning backend service, database/graph/cache/queue, fixture, seed 또는 외부 boundary stub 조건>
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
- 결과 JSON: `openspec/specs/<spec-name>/e2e/results/results.json`
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
- 커버리지 매트릭스: `openspec/specs/<spec-name>/e2e/scenarios/00-coverage-matrix.md`
- Playwright 명세: `openspec/specs/<spec-name>/e2e/tests/<suite-slug>.spec.mjs`
- Docker compose: `docker-compose.e2e.yml` 또는 `N/A`

## 결과
| 지표 | 값 |
| --- | --- |
| 상태 | passed/failed/not-run |
| 통과 테스트 | <number> |
| 실패 테스트 | <number> |
| 건너뛴 테스트 | <number> |

## 산출물
- JSON 리포트: `openspec/specs/<spec-name>/e2e/results/results.json`
- HTML 리포트: `openspec/specs/<spec-name>/e2e/results/html-report/index.html`
- 스크린샷: `openspec/specs/<spec-name>/e2e/results/screenshots/`
- 산출물: `openspec/specs/<spec-name>/e2e/results/artifacts/`

## 스크린샷 맵
| 시나리오 | 체크포인트 | 스크린샷 파일 | 매뉴얼용 캡션 |
| --- | --- | --- | --- |
| 01 | `<checkpoint-name>` | `openspec/specs/<spec-name>/e2e/results/screenshots/<file>.png` | <짧은 한국어 캡션> |

## 검증
- 출력 검증기: passed/failed/not-run
- Playwright: passed/failed/not-run
- Docker compose config: passed/failed/not-applicable

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 없음 | - | - |
```
