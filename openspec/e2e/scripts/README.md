# OpenSpec E2E Shared Scripts

여러 E2E 스위트가 공통으로 쓰는 재사용 코드 산출물 보관소.
스위트별 스크립트는 `openspec/specs/<spec-name>/e2e/scripts/` 아래에 두고,
이 폴더는 **두 개 이상의 스위트에서 거의 같은 모양으로 작성된 스크립트**만
승격하여 둡니다.

## 디렉터리 위치 규칙

- **suite-local** — `openspec/specs/<spec-name>/e2e/scripts/`
  - canned 응답이 시나리오와 강하게 묶이는 mock
  - 한 스위트만 쓰는 헬퍼
  - 처음 작성된 스크립트 (아직 한 번만 등장)
- **shared (이 폴더)** — `openspec/e2e/scripts/`
  - 두 번 이상 같은 패턴으로 작성된 스크립트의 일반화 버전
  - 시나리오 데이터 부분이 매개변수/주입식으로 분리되어 있어야 함
  - 한 스위트의 변경이 다른 스위트를 깨면 안 되므로 변경 전 모든 소비자
    스위트를 확인 후 수정

## 승격 규칙 ("rule of two")

스킬의 Phase F에서 다음 조건을 모두 만족할 때 승격을 고려합니다:

1. 같은 모양의 스크립트가 **두 개 이상의 스위트에 이미 존재**한다.
2. 두 스크립트의 차이가 데이터/응답/셀렉터 같은 시나리오 부분이고, 핵심
   로직(HTTP 라우팅, 인자 파싱, flush 절차)이 동일하다.
3. 데이터 부분을 매개변수/모듈 주입으로 분리하면 두 스위트 모두 그대로
   동작할 만큼 일반화가 깔끔하다.

승격 시:

- 새 파일을 `openspec/e2e/scripts/`에 만들고
- 이 README의 "현재 제공 스크립트" 표에 한 줄 추가
- 각 소비자 스위트의 호출부를 상대 경로 import 또는 Docker volume 마운트로
  교체
- 두 스위트의 Playwright를 모두 다시 돌려 그린이 유지되는지 확인

너무 일찍 추상화하면 결국 세 번째 소비자가 모양이 안 맞아 다시 fork 되니,
"두 번 작성한 적이 있어야 승격"이라는 기준을 지키는 것이 안전합니다.

## 현재 제공 스크립트

| 스크립트 | 설명 | 소비 스위트 |
| --- | --- | --- |
| (none yet) | — | — |

## 승격 후보 (참고용)

아래 항목은 현재 두 개 이상의 스위트에서 비슷한 모양으로 작성되어 있어
다음 작업에서 승격을 검토할 만함:

- **OpenAI 호환 mock LLM 서버**
  - `openspec/specs/completion_process-definition-search/e2e/scripts/`의 mock-llm
  - `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_llm.py`
  - 공통 부분: stdlib HTTP 서버, `/v1/embeddings`와 `/v1/chat/completions`,
    `/health`, OpenAI envelope, deterministic embedding
  - 시나리오별 부분: 어떤 키워드가 어떤 벡터/응답으로 매핑되는지
  - 일반화 방향: 핵심 서버를 공유 스크립트로 두고, 응답 매핑은 외부 JSON 또는
    환경 변수로 주입
- **외부 에이전트 디스크립터 mock 서버**
  - `openspec/specs/completion_agent-memory-chat/e2e/scripts/mock_external_agent.py`
  - 다른 스위트에서 한 번 더 필요해지면 그때 승격

승격 작업은 별도 스펙/작업으로 분리해 진행하길 권장 (스위트 기능 작업과
섞이면 회귀 위험이 큼).
