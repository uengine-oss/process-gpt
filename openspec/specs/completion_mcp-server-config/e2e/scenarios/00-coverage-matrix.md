# completion_mcp-server-config E2E 커버리지 매트릭스

## 범위
- 스위트 슬러그: `completion_mcp-server-config`
- 원본 명세 ID: `completion_mcp-server-config`
- 원본 명세:
  - `openspec/specs/completion_mcp-server-config/spec.md`
- 백엔드/제품 계약:
  - completion FastAPI 라우트 `GET /mcp-tools` — `services/completion/mcp.json` 파일에서 MCP 서버 카탈로그를 로드하여 `mcpServers` 객체를 반환한다.
  - 파일이 없거나 JSON 형식이 손상된 경우 HTTP 404 + `Failed to load MCP config` 응답.
- E2E 루트: `openspec/specs/completion_mcp-server-config/e2e/`
- Playwright 명세: `openspec/specs/completion_mcp-server-config/e2e/tests/completion_mcp-server-config.spec.mjs`
- 결과 디렉터리: `openspec/specs/completion_mcp-server-config/e2e/results/`

## 시나리오 목록
| ID | 시나리오 문서 | Playwright 테스트 제목 | 주요 동작 |
| --- | --- | --- | --- |
| 01 | `01-catalog-success.md` | `GET /mcp-tools 응답이 mcpServers 카탈로그를 반환한다` | gateway 경유로 카탈로그를 조회하고 stdio·url 두 형식 항목을 모두 검증 |
| 02 | `02-config-load-failure.md` | `mcp.json 손상 시 404 Failed to load MCP config 응답을 반환한다` | completion 컨테이너에서 `mcp.json`을 임시 손상시키고 404 응답·메시지 검증, 정상 상태 복구 |

## 요구사항 커버리지
| 명세 | 요구사항 | 필수 수준 | 커버 시나리오 | 비고 |
| --- | --- | --- | --- | --- |
| `completion_mcp-server-config` | MCP 서버 카탈로그 조회 | SHALL | 01, 02 | 정상 경로(01)와 손상 경로(02)를 모두 검증 |

## 명세 시나리오 커버리지
| 명세 | 요구사항 | 명세 시나리오 | 커버 시나리오 | 사용자 검증 표면 |
| --- | --- | --- | --- | --- |
| `completion_mcp-server-config` | MCP 서버 카탈로그 조회 | 카탈로그 조회 성공 | 01 | gateway(nginx) → completion `/mcp-tools` 응답 본문(JSON 구조·필드) |
| `completion_mcp-server-config` | MCP 서버 카탈로그 조회 | MCP 설정을 로드할 수 없음 | 02 | gateway(nginx) → completion `/mcp-tools` 응답 상태 코드(404)·상세 메시지 |

## 스펙 관련 코드 표면
### 백엔드
| 파일 | 함수/클래스/라우트 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| `services/completion/mcp_config_api.py` | `add_routes_to_app`, `load_mcp_tools`, `GET /mcp-tools` | MCP 서버 카탈로그 조회 | line/function >= 90% | 명세 라우트의 유일한 구현체. 정상 경로와 예외 경로 모두 이 파일에 존재 |
| `services/completion/mcp.json` | MCP 서버 카탈로그 데이터 | MCP 서버 카탈로그 조회 | 파일 존재 + JSON 파싱 성공 | `load_mcp_tools`가 직접 읽는 카탈로그 원본. 손상 시 명세상 404를 반환해야 함 |
| `services/completion/main.py` | `add_mcp_routes_to_app(app)` 등록부 | MCP 서버 카탈로그 조회 | 호출됨 | FastAPI 앱에 라우트가 노출되는지 확인하는 진입점 |

### 프론트엔드
| 파일 | 컴포넌트/함수/API 호출 | 관련 요구사항 | 커버리지 기준 | 선정 근거 |
| --- | --- | --- | --- | --- |
| 해당 없음 | — | — | — | 본 명세는 비-사용자 대상 백엔드 프로토콜 계약(`GET /mcp-tools`)이며, 현재 프론트엔드 UI 페이지에서 이 라우트를 호출하지 않음. 재확인 근거: (a) `services/frontend/src/components/api/ProcessGPTBackend.ts` `getMCPTools()`는 `/completion/mcp-tools`를 호출하는 유일한 API 메서드이지만 Vue 컴포넌트·스토어·페이지 어디에서도 호출되지 않음(`Backend.ts` 인터페이스 선언, `BackendFactory.ts` 라우팅 등록, `UEngineBackend.ts` stub만 존재). (b) `services/frontend/src/components/pages/account-settings/MCPServer.vue` 설정 화면은 존재하나 `backend.getMCPByTenant()` (테넌트별 MCP 설정, UEngineBackend에서 stub `{}` 반환)을 호출하며, 본 명세의 카탈로그 라우트와 별개의 백엔드 계약을 사용함. 따라서 프론트엔드 커버리지는 평가 대상에서 제외하고 비고에 명시함. |

## 재사용 산출물
| 항목 | 출처 | 사용 방식 |
| --- | --- | --- |
| `docker-compose.e2e.yml` (db, kong, completion, gateway, frontend) | 저장소 루트 | 본 스위트에서 새로운 서비스 추가 없이 그대로 재사용 |
| nginx gateway 설정 (`completion_agent-memory-chat/e2e/docker/nginx.e2e.conf`) | 기존 스위트 | `/completion/*` → `completion:8000` 프록시 경로 재사용 |
| Playwright `node_modules` junction 패턴 | `openspec/e2e/memories/playwright-node-modules-junction.md` | `tests/node_modules`를 `services/frontend/node_modules`로 junction 생성 |

## 미검증 및 보류 항목
| 항목 | 사유 | 후속 조치 |
| --- | --- | --- |
| 사용자 UI 스크린샷 | 본 명세는 비-사용자 대상 프로토콜 계약이며, 현재 저장소에 `/mcp-tools` 응답을 사용자 화면에 표시하는 페이지가 없음. 설정 화면 `MCPServer.vue`는 존재하나 `getMCPByTenant()`(테넌트별 MCP 설정) API를 사용하며 본 명세의 카탈로그 라우트와는 다른 백엔드 계약을 호출함 | 향후 `MCPServer.vue` 등 UI에서 `getMCPTools()` (`/completion/mcp-tools`)를 직접 소비하는 기능이 추가되면 해당 화면을 진입점으로 하는 사용자 시나리오를 추가 |
| 프론트엔드 coverage | 본 라우트를 호출하는 UI 코드 경로가 존재하지 않으므로 source-mapped 커버리지 수집 대상이 없음 | UI 소비자가 생기는 시점에 재평가 |

## 체크리스트
- [x] 모든 Requirement가 하나 이상의 E2E 시나리오에 매핑되어 있습니다.
- [x] 중요한 OpenSpec Scenario가 E2E 시나리오에 매핑되어 있거나 미검증 및 보류 항목에 기록되어 있습니다.
- [x] 사람이 읽는 요구사항명, 명세 시나리오명, 목적, 절차, 기대 결과는 한국어로 작성되어 있습니다.
- [x] 원본 OpenSpec에 영어 설명이 있더라도 E2E 문서에는 한국어 의미로 변환되어 있으며, API 경로·필드명·이벤트명 같은 계약 식별자만 원문으로 유지합니다.
- [x] 원본 명세가 하나의 백엔드 연계 피쳐 또는 응집된 사용자 workflow 범위이며, 마이크로서비스 전체 요약이나 프론트엔드 단독 명세가 아닙니다.
- [x] 원본 명세의 서비스 접두어 또는 도메인 구분자가 `frontend`, `ui`, `react`, `page`, `component` 같은 구현 레이어가 아닙니다.
- [x] E2E가 실행할 소유 백엔드 서비스/API/데이터 계약이 명확합니다.
- [x] 서비스 접두형 명세 ID를 사용하는 경우 스위트 슬러그가 동일한 값을 유지합니다.
- [x] E2E 시나리오, 테스트 스크립트, seed/stub, 실행 결과, 스크린샷은 `openspec/specs/completion_mcp-server-config/e2e/` 아래에 응집되어 있습니다.
- [x] 사용자-facing 시나리오는 직접 API 요청이 아니라 브라우저 UI 상호작용으로 검증합니다. *(본 명세는 비-사용자 대상 프로토콜 계약이므로 Playwright `request` 기반 시나리오가 명시적으로 허용됨 — User-Action Rule 단서 조항)*
- [x] 시나리오별 스크린샷 체크포인트가 매뉴얼에 재사용할 수 있는 UI 상태를 설명합니다. *(비-사용자 대상 프로토콜이므로 의도적으로 비워두고 사유 기록)*
- [x] 스펙 관련 백엔드/프론트엔드 파일과 함수가 코드 표면 표에 기록되어 있습니다.
- [x] 커버리지 기준이 전체 저장소가 아니라 스펙 관련 파일/함수 중심으로 정의되어 있습니다.
- [x] 결과 경로가 `OUTPUT_CONTRACT.md`와 일치합니다.
