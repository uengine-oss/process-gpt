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

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/<service>/<file>` | `<function-or-route>` | <요구사항 제목> | line/function >= 80% | <API route, service call, persistence, job, event 등 직접 구현 근거> |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/<frontend>/src/<file>` | `<component-or-function>` | <요구사항 제목> | 참고/line >= 60% | <사용자 화면, route, store, API client, validation 등 직접 표면 근거> |

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
- [ ] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [ ] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
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
- 스펙 커버리지 HTML 리포트: `openspec/specs/<spec-name>/e2e/results/spec-coverage-report.html`
- 스펙 커버리지 JSON 요약: `openspec/specs/<spec-name>/e2e/results/coverage-summary.json`
- 백엔드 커버리지: `openspec/specs/<spec-name>/e2e/results/backend-coverage/`
- 프론트엔드 커버리지: `openspec/specs/<spec-name>/e2e/results/frontend-coverage/`
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
- OpenSpec 추적성 게이트: passed/failed/not-run
- 백엔드 coverage 게이트: passed/failed/not-run
- 프론트엔드 coverage 보조 게이트: passed/failed/not-run
- AI 스펙 커버리지 판단: sufficient/insufficient/not-run

## 커버리지 요약
| 구분 | 대상 | 결과 | 판단 |
| --- | --- | --- | --- |
| OpenSpec 추적성 | Requirement/Scenario/Test/Screenshot | <예: 4/4 requirements, 6/6 scenarios, 4/4 tests> | 충분/부족 |
| 백엔드 | <스펙 관련 파일/함수> | <예: 핵심 파일 85% 이상, XML+HTML report 생성> | 충분/부족 |
| 프론트엔드 | <스펙 관련 파일/컴포넌트 또는 번들 V8> | <예: source-mapped line 65% 또는 V8 bundle 15.68%> | source-mapped/보조 지표/부족 |

## 알려진 공백
| 공백 | 영향 | 후속 조치 |
| --- | --- | --- |
| 없음 | - | - |
```

## `spec-coverage-report.html`

Create this HTML report after Playwright, traceability, backend coverage, and frontend coverage have been run or explicitly marked unavailable. The report must be self-contained, readable in a browser from the spec-local results folder, and written in Korean. Keep CSS inline. Do not include secrets, tokens, raw request headers containing credentials, or full unredacted environment dumps.

```html
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title><suite-slug> 스펙 커버리지 보고서</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: #172033; background: #f7f8fb; }
    main { max-width: 1180px; margin: 0 auto; }
    section { background: #fff; border: 1px solid #dfe3eb; border-radius: 12px; padding: 20px; margin: 18px 0; box-shadow: 0 1px 2px rgba(16, 24, 40, .04); }
    h1, h2, h3 { margin-top: 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 14px; }
    th, td { border: 1px solid #e4e7ee; padding: 9px 10px; text-align: left; vertical-align: top; }
    th { background: #f1f4f9; }
    code { background: #eef2f7; padding: 2px 5px; border-radius: 4px; }
    .badge { display: inline-block; padding: 4px 9px; border-radius: 999px; font-size: 12px; font-weight: 700; }
    .pass { color: #065f46; background: #d1fae5; }
    .warn { color: #92400e; background: #fef3c7; }
    .fail { color: #991b1b; background: #fee2e2; }
    .muted { color: #667085; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
    .metric { border: 1px solid #e4e7ee; border-radius: 10px; padding: 14px; background: #fbfcff; }
    .metric strong { display: block; font-size: 24px; margin-top: 6px; }
  </style>
</head>
<body>
<main>
  <h1><suite-slug> 스펙 커버리지 보고서</h1>
  <p class="muted">생성 시각: <generated-at> · 원본 명세: <code>openspec/specs/&lt;spec-name&gt;/spec.md</code></p>

  <section>
    <h2>AI 종합 판단</h2>
    <p><span class="badge pass|warn|fail"><sufficient|partial|insufficient></span></p>
    <p><AI가 OpenSpec 추적성, 백엔드 커버리지, 프론트엔드 커버리지, 알려진 공백을 종합해 충분성 판단을 설명합니다.></p>
  </section>

  <section>
    <h2>게이트 요약</h2>
    <div class="grid">
      <div class="metric">OpenSpec Requirement<strong><covered>/<total></strong></div>
      <div class="metric">OpenSpec Scenario<strong><covered>/<total></strong></div>
      <div class="metric">백엔드 커버리지<strong><backend-coverage-percent>%</strong></div>
      <div class="metric">프론트엔드 커버리지<strong><frontend-coverage-percent>%</strong></div>
      <div class="metric">전체 커버리지<strong><overall-coverage-percent>%</strong></div>
    </div>
    <table>
      <thead><tr><th>게이트</th><th>상태</th><th>근거</th></tr></thead>
      <tbody>
        <tr><td>OpenSpec 추적성</td><td><span class="badge pass">passed</span></td><td><coverage-matrix/result-json/screenshot evidence></td></tr>
        <tr><td>백엔드 coverage</td><td><span class="badge pass|warn|fail">passed/failed/unavailable</span></td><td><coverage.py/c8/JaCoCo report path and threshold></td></tr>
        <tr><td>프론트엔드 coverage</td><td><span class="badge pass|warn">supporting</span></td><td><Monocart/Istanbul report path and sourcemap quality></td></tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>OpenSpec 스펙 커버리지</h2>
    <p class="muted">원본 명세의 Requirement와 Scenario가 어떤 E2E 시나리오, Playwright 테스트, 스크린샷 증거로 검증되었는지 보여줍니다.</p>
    <table>
      <thead><tr><th>요구사항</th><th>명세 시나리오</th><th>E2E 시나리오</th><th>Playwright 테스트</th><th>증거</th><th>커버리지</th><th>AI 판단</th></tr></thead>
      <tbody>
        <tr>
          <td>&lt;requirement&gt;</td>
          <td>&lt;spec scenario&gt;</td>
          <td>&lt;NN scenario document&gt;</td>
          <td>&lt;Playwright test title&gt;</td>
          <td>&lt;results.json, screenshot checkpoint, trace, API assertion&gt;</td>
          <td>&lt;예: 100%&gt;</td>
          <td>&lt;충분/부분 충분/부족 및 이유&gt;</td>
        </tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>스펙 관련 백엔드 파일/함수</h2>
    <p class="muted">스펙과 직접 관련된 서버 파일/함수만 대상으로 coverage 산출물을 읽어 퍼센트를 계산합니다. 관련 없는 공용/전체 저장소 코드는 분모에서 제외합니다.</p>
    <table>
      <thead><tr><th>파일</th><th>함수/클래스/라우트</th><th>관련 요구사항</th><th>커버리지</th><th>기준</th><th>AI 판단</th><th>보강 제안</th></tr></thead>
      <tbody>
        <tr>
          <td><code>services/&lt;service&gt;/&lt;file&gt;</code></td>
          <td><code>&lt;function-or-route&gt;</code></td>
          <td>&lt;requirement&gt;</td>
          <td>&lt;line/function/branch %&gt;</td>
          <td>&lt;예: line >= 80%&gt;</td>
          <td>&lt;충분/부분 충분/부족 및 이유&gt;</td>
          <td>&lt;추가할 E2E 시나리오나 단위 테스트&gt;</td>
        </tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>스펙 관련 프론트엔드 파일/함수</h2>
    <p class="muted">소스맵 기반 원본 파일 커버리지를 우선 사용합니다. 기존 이미지에 소스맵이 없으면 소스맵 포함 coverage용 프론트엔드 이미지를 재빌드한 뒤 다시 수집하고, 그래도 불가능할 때만 번들/V8 coverage를 보조 지표로 사용합니다.</p>
    <table>
      <thead><tr><th>대상</th><th>컴포넌트/함수/API 호출</th><th>관련 요구사항</th><th>커버리지</th><th>기준</th><th>AI 판단</th><th>제약</th></tr></thead>
      <tbody>
        <tr>
          <td><code>services/&lt;frontend&gt;/src/&lt;file&gt;</code></td>
          <td><code>&lt;component-or-function&gt;</code></td>
          <td>&lt;requirement&gt;</td>
          <td>&lt;line/function/branch % 또는 V8 bundle coverage&gt;</td>
          <td>&lt;예: raw coverage exists 또는 line >= 60%&gt;</td>
          <td>&lt;충분/보조 지표/부족 및 이유&gt;</td>
          <td>&lt;sourcemap/prebuilt image/minification 등 해석 제약&gt;</td>
        </tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>미커버/취약 분기</h2>
    <table>
      <thead><tr><th>위치</th><th>미커버 동작</th><th>리스크</th><th>권장 보강</th></tr></thead>
      <tbody>
        <tr><td><code>&lt;file:function&gt;</code></td><td>&lt;uncovered branch&gt;</td><td>&lt;spec risk&gt;</td><td>&lt;scenario/test addition&gt;</td></tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>원본 리포트 링크</h2>
    <ul>
      <li>Playwright HTML: <code>html-report/index.html</code></li>
      <li>Backend coverage HTML: <code>backend-coverage/html/index.html</code></li>
      <li>Frontend coverage HTML: <code>frontend-coverage/monocart-report/index.html</code></li>
      <li>Machine summary: <code>coverage-summary.json</code></li>
    </ul>
  </section>
</main>
</body>
</html>
```
