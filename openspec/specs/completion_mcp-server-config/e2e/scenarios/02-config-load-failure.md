# E2E 시나리오 02: MCP 설정을 로드할 수 없음

## 메타데이터
- 스위트 슬러그: `completion_mcp-server-config`
- 원본 명세 ID: `completion_mcp-server-config`
- 시나리오 ID: `02`
- Playwright 테스트 제목: `mcp.json 손상 시 404 Failed to load MCP config 응답을 반환한다`
- 원본 명세:
  - `openspec/specs/completion_mcp-server-config/spec.md`

## 목적
`services/completion/mcp.json` 파일이 사라지거나 JSON 파싱이 실패하는 상황에서 `GET /mcp-tools`가 HTTP 404와 `Failed to load MCP config` 메시지를 반환해야 한다. 본 시나리오는 운영 환경에서 잘못된 설정 배포로 카탈로그가 손상되었을 때 클라이언트가 일관된 오류를 받게 보장한다. 비-사용자 대상 프로토콜이므로 Playwright `request` API로 검증하며, 컨테이너 내부 파일을 일시적으로 손상시킨 뒤 검증이 끝나면 원본을 즉시 복구한다.

## 사전 조건
- 시나리오 01과 동일한 컨테이너 구성이 healthy 상태이다.
- Playwright 실행 호스트에서 `docker exec process-gpt-e2e-completion ...` 명령을 호출할 수 있다.
- 테스트 종료 시 `mcp.json` 원본이 반드시 복구되어 후속 테스트에 영향을 주지 않는다.

## 테스트 데이터 및 Stub
| 이름 | 유형 | 경로 또는 route | 목적 |
| --- | --- | --- | --- |
| `mcp.json` (원본) | seed | `services/completion/mcp.json` → 컨테이너 `/app/mcp.json` | 시나리오 시작 전 백업 후 시나리오 종료 시 복구 |
| 손상 파일 | fixture(런타임 생성) | 컨테이너 `/app/mcp.json` ← `not-a-json` 문자열로 덮어쓰기 | `JSONDecodeError` 유발 |
| 파일 삭제 분기 | fixture(런타임) | `mv /app/mcp.json /app/mcp.json.bak` | `FileNotFoundError` 유발 |
| gateway 라우트 | route | `GET http://localhost:8088/completion/mcp-tools` | 동일 외부 경로 사용 |

## 절차
1. 사전 단계로 컨테이너의 원본 `mcp.json`을 `mcp.json.e2e-backup`으로 복사한다.
2. 분기 A — JSON 손상: 컨테이너 안에서 `printf` 등으로 `/app/mcp.json`을 잘못된 JSON 문자열로 덮어쓴다.
3. `GET http://localhost:8088/completion/mcp-tools`를 호출하고 응답을 검증한다.
4. 응답 상태 코드가 `404`이고 본문(JSON)의 `detail` 필드가 `Failed to load MCP config`로 시작하는지 확인한다.
5. 분기 B — 파일 부재: 컨테이너 안에서 `/app/mcp.json`을 임시 위치로 이동시킨다.
6. 다시 `GET /completion/mcp-tools`를 호출하고 동일하게 `404` + `Failed to load MCP config` prefix를 확인한다.
7. 사후 정리 단계에서 `mcp.json.e2e-backup`을 `mcp.json`으로 복구하고 마지막으로 다시 한 번 호출하여 200 응답이 돌아오는지 확인한다(부수 효과 차단).

## 기대 결과
- 손상된 JSON과 파일 부재 두 분기 모두에서 HTTP 404 응답을 받는다.
- 응답 JSON `detail` 메시지가 `Failed to load MCP config`로 시작한다(뒤에 원인 메시지가 붙음).
- 사후 정리 후 동일한 라우트가 다시 200을 반환한다(원상 복구 검증).

## 커버하는 요구사항
| 명세 | 요구사항 | 시나리오 |
| --- | --- | --- |
| `completion_mcp-server-config` | MCP 서버 카탈로그 조회 | MCP 설정을 로드할 수 없음 |

## 산출물
- 스크린샷 체크포인트: 본 시나리오는 비-사용자 대상 프로토콜 검증이므로 의도적으로 스크린샷 체크포인트를 두지 않는다.
- Trace/video: Playwright 실패 시 보존됩니다.
- 결과 JSON: `openspec/specs/completion_mcp-server-config/e2e/results/results.json`
