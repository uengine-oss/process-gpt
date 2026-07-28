# 시나리오 10 — WMS 서열 출고·팔레타이징 (완전자동 + 예외만 사람)

두산로지스틱스솔루션·Dematic이 파는 "서열 출고(Sequential Dispatch)·로봇
팔레타이징(Mixed Palletizing)"을 실제 ProcessGPT 프로세스 하나로 재현한다.
정상 경로엔 사람이 전혀 없고, 설비가 중량/용적 초과나 적재 실패를 보고했을
때만 사람이 재포장을 지시한다 — 지금까지의 WMS 재보충(Replenishment)
프로세스가 매 단계 HITL인 것과 대조적인 패턴.

- 프로세스: `wms_sequential_dispatch_process` (11개 활동, `services/sample-app-wms`)
- 설치: `services/sample-app-wms/scripts/setup_sequential_dispatch_demo_equipment.sql`
  (1회, `DISPATCH-CELL-01` ROBOT_CELL + 무실패 시뮬레이션 프로파일) →
  `services/sample-app-wms/scripts/install_sequential_dispatch_process.py`
  (둘 다 idempotent — 재실행 안전. `install_processgpt_integration.py`가 먼저
  등록해 둔 `tenants.mcp.mcpServers.wms`를 재사용하므로 그것도 먼저 실행돼
  있어야 한다)
- 녹화 스크립트: `scripts/record_wms_sequential_dispatch_demo.mjs`
- 완성 영상: `docs/demo/wms-sequential-dispatch-demo-narrated.mp4`
  (= `demo-recordings/wms-sequential-dispatch-demo-narrated.mp4`, 12분 35초,
  OpenAI TTS 내레이션(marin) 20장면 — 슬라이드 2장 + 빌드타임(BPMN 편집기) +
  런타임 정상/예외 2경로. 원본 스크린샷 20장은
  `demo-recordings/wms-sequential-dispatch-demo/`에 남아 있다(gitignore됨))

## 이 데모가 실제로 실행하는 흐름

```
출고 계획 등록(사람) → 출고 단위 등록 ×2 → 웨이브 오픈 → 서열 배정 ×2
→ 설비 상태 조회 → 팔레타이징 명령 전송 → 결과 확인(HITL)
  → [정상: SUCCESS/PARTIAL] 출고 서열 현황 최종 확인 → 종료
  → [예외: OVERWEIGHT/OVERVOLUME/ABORTED] 재포장 지시(HITL) → 종료
```

앞 6개 서비스 활동은 전부 실제 `wms-mcp` 도구(`create_outbound_order`,
`open_dispatch_wave`, `assign_dispatch_sequence`, `get_equipment_status`,
`dispatch_palletize_command`)를 호출해 실제 Postgres RPC를 실행한다 —
시뮬레이션이 아니다. 정상 경로는 `wcs_gateway_simulator`(실패율 0으로
설정된 `DISPATCH-CELL-01`)가 실제로 완료시키고, 예외 경로는 시뮬레이터
대신 `wms_report_command_result`를 OVERWEIGHT로 직접 호출해 재현한다
(design.md D7 — 계획 시점 상한 검증과 실측 시점 초과는 서로 다른 실패).

## 이 시나리오를 만들며 발견·수정한 버그 2건 (`services/completion`)

이전에는 어떤 WMS MCP 프로세스도 completion의 실제 폴링 서비스를 통해
end-to-end로 실행해 본 적이 없었다(문서상 "검증"은 항상 raw MCP client
스크립트로 도구만 개별 호출한 것이었다). 이 시나리오를 실제로 돌리며 다음
2개의 플랫폼 버그를 처음 발견하고 고쳤다 — WMS뿐 아니라 MCP 도구를 쓰는
모든 프로세스에 영향을 준다:

1. `polling_service/mcp_processor.py`의 `sanitize_mcp_tools()`가 스키마
   보정이 필요 없는(= 정상적인) dict 스키마 도구를 아무 분기에도 append하지
   않고 조용히 버리고 있었다 — 에이전트에게 도구가 아예 안 묶여
   "No tool results found"로 실패하면서도 워크아이템은 DONE으로 남았다.
2. `workitem_processor.py`의 `handle_service_workitem()`이 serviceTask
   완료 후 다음 활동으로 진행시키는 로직(`execute_next_activity`)을 전혀
   호출하지 않았다 — userTask 완료 경로에만 있던 `_check_service_tasks`를
   흉내 내 직접 다음 serviceTask를 SUBMITTED로 전환하도록 추가했다.

두 수정 모두 `services/completion` 저장소에 커밋·푸시돼 있다.

## 알려진 제약

- `confirm_palletize_result`/`handle_repack_exception` 폼은 `fields_json`만
  정의돼 있고 `html`이 비어 있어, 실제 화면에서는 (다른 커스텀 HTML 폼이
  없으면) 범용 자유입력 텍스트로 폴백한다 — `register_outbound_plan`도
  동일. 그래서 이 시나리오의 HITL 제출은 `/completion/complete`를 로그인
  세션의 실제 JWT로 직접 호출한다(scenario-tutorial-lv1.md와 동일한 이유 —
  화면은 실제 상태 전이를 보여주되, 제출 자체는 API로 한다).
- `dispatch_palletize_command`의 `expected_version`은 에이전트가 직전
  `get_equipment_status` 산출물 텍스트에서 숫자를 그대로 읽어 써야 한다 —
  실제로 한 번 "1"을 기본값으로 잘못 짐작해 CONFLICT가 난 적이 있어,
  설치 스크립트의 instruction에 "임의로 1을 쓰지 마라 + CONFLICT 시
  에러 메시지의 found 값으로 1회 재시도" 지침을 명시적으로 추가했다.
- 로컬 Docker 리소스가 빠듯하면(다른 무거운 컨테이너들과 동시 실행 시)
  Postgres가 간헐적으로 크래시할 수 있다 — 녹화 스크립트의 `shRetry`가
  "recovery mode"/연결 끊김을 자동 재시도하지만, 심하면 무관한 컨테이너를
  잠시 내려 메모리를 확보하는 편이 훨씬 빠르다.
