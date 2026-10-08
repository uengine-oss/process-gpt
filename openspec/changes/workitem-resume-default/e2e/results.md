# E2E 실행 결과 — 2026-10-07

전체 실행 1회: **6 passed (6.7분)**, `npx playwright test` (Chromium headless, Playwright 1.58.2).
원시 결과: `results/e2e-results.json`(마지막 실행), 실패 때만 `test-results/` 에 영상·trace.

| 시나리오 | 결과 | 시간 | 근거(DB·클러스터) |
|---|---|---|---|
| RS-3.2·RS-6.2 반려 → revision | ✓ | 1.2m | `resume_e2e_revision` feedback 마지막 `kind=revision`, 다시 집힘 `claim_count=1`, 표 형식 재작성 |
| RE-1.1 deepagents 파드 사망 → 다른 파드 재점유 | ✓ | 1.1m | `claim_count=2`, step1 도구 05:51:15 1회 → 파드 삭제 → 05:51:54 끊긴 step2 재실행 → step3 |
| RE-1.3·1.4 cli-agent 파드 사망 → 새 파드가 세션 재개 | ✓ | 1.9m | `claim_count=2`, steps.log step1 1줄(kill 전 줄 유지), 결과의 `cliagents_session_id` = 실행 중 기록한 세션 |
| RE-1.6 codex 같은 파드 재시작 → thread 재개 | ✓ | 1.1m | `claim_count=2`, restartCount +1, step1 1줄(kill 전 줄 유지), 대화 rollout 1개 |
| RE-2.1·RS-6.1 cli-agent 질문 카드 답변 → 같은 세션 | ✓ | 34s | `HUMAN_ASKED` → 카드 답 → `kind=human_answer` → 멈춘 세션 transcript 에 답 원문. 재개 뒤에도 같은 권한이라 다시 `HUMAN_ASKED`(중복 알림 없음) |
| RE-4.1 체크포인터 저장소 불가 → 기동 실패 | ✓ | 48s | 파드 `Failed`, exit 1, 폴링 서버 미기동 |

## e2e 가 찾은 결함과 조치
| # | 결함 | 영향 | 조치 |
|---|---|---|---|
| 1 | SDK: 종료 신호(SIGTERM)로 실행이 끊기면 사용자 취소와 같은 경로로 lease 를 비웠다 → `STARTED`+lease 없음 = 아무도 회수하지 않는 고아 | 롤링 배포·스케일 다운·파드 삭제 때 진행 중 작업이 영구히 멈춤. 재개 기본화의 전제를 깸 | **수정**: 사용자 취소가 아닌 취소면 lease 를 남겨 만료 뒤 재점유(`tests/test_shutdown_reclaim.py`, 스펙 RS-2.3) |
| 2 | cli-agent: Claude Code 2.1.216 의 거부 문구 "This command requires approval" 를 권한 거부로 보지 않았다 | 사람에게 묻는 경로가 한 번도 열리지 않음 | **수정**: 도구 오류 + 해당 문구를 거부로 인식(cli-agent 쪽, cliagents 는 그대로) |
| 3 | cli-agent: 거부 뒤 모델이 설명 한 줄만 써도 "결과 있음" 으로 보아 폼 계약 위반 FAILED | 같은 이유로 HITL 불가 | **수정**: 거부 + 폼 결과 미충족이면 멈춤(스펙 RE-2.0) |
| 4 | cli-agent: 멈춤 이벤트를 `human_input_required` 로 보냄 — 저장소 enum 에 없어 저장 실패, 화면 질문 카드가 안 뜸 | 사람이 답할 화면이 없음 | **수정**: `human_asked` + `{question, type}` |
| 5 | cli-agent 컨테이너가 root → Claude Code 가 `--dangerously-skip-permissions` 거부, `command_exec` 작업 즉시 실패(오류 원문은 삼켜지고 "결과 형식 불일치" 만 남음) | `command_exec` 를 고른 작업 전부 실패 | **배포 설정**: e2e 매니페스트에 `IS_SANDBOX=1`. 운영 매니페스트에도 필요(미반영) |
| 6 | (환경) arm64 VM + Rosetta 에서 bubblewrap 동작 불가 → codex 셸 명령 전부 실패, 모델이 결과를 지어냄 | 이 개발 머신 한정 | e2e 전용 이미지에서 bwrap 대역 사용. amd64 노드에서 재확인 필요 |

## 한계
- 모델이 거부 뒤 사과문으로 폼을 채우면 "결과를 냈다" 로 보아 저장한다(규칙상 우회 성공과 구분 불가). 시나리오 지시는 "result 를 비워 두고 종료" 로 고정했다.
- codex 는 같은 파드 재점유만 다룬다. 다른 파드(emptyDir 유실)는 범위 밖.
- 시행은 시나리오당 1회(전체 실행 1회 + 개발 중 개별 실행). 모델 판단에 따른 흔들림은 통계적으로 다루지 않았다.
- 실행 중 로컬 Supabase 가 VM 디스크 부족(이미지 빌드 캐시)으로 한 번 내려갔다 — 캐시를 비우고 복구, `up.sh` 에 디스크 점검 추가.

---

# 업무 시나리오 — 구매 요청 처리 (`purchase.spec.ts`, `seed_purchase.py`)

3 태스크: 구매 요청(사용자 제출) → 공급사 선정(에이전트: 비교표 → **구매 대장 한 줄** → 품의서 → 보고) → 발주서 작성(에이전트) → 완료.
오케스트레이션만 다른 정의 3개를 `E2E_ORCH=deepagents|cli|codex` 로 각각 실행. 대장 줄이 써진 직후 실행을 죽인다.

| 서비스 | 결과 | 인스턴스 | 요청번호 | 공급사 선정 claim_count | 대장 줄 | 인스턴스 |
|---|---|---|---|---|---|---|
| deepagents | ✓ 1.8m | `purchase_request_e2e_deepagents.67a15641-…` | PR-DEEPAGENTS-008741 | 2 | 1 (공유 PVC 파일) | COMPLETED |
| cli-agent | ✓ 1.5m | `purchase_request_e2e_cli.f921d564-…` | PR-CLI-776310 | 2 | 1 (작업 공간 PVC) | COMPLETED |
| codex | ✓ 1.4m | `purchase_request_e2e_codex.034b6808-…` | PR-CODEX-866410 | 2 | 1 (대화 작업 공간) | COMPLETED |

## 이 시나리오가 찾은 것
| # | 내용 | 조치 |
|---|---|---|
| 7 | SDK 1차 수정(종료 시 lease 유지)이 취소를 삼켜 폴링 루프가 계속 돌았다 → 종료 중인 파드가 lease 만료 뒤 자기 작업을 다시 집음(claim_count 3) | **수정**: 종료 취소를 끝까지 전달(`ShutdownStopsPollingTest`, 되돌림 검사 통과) |
| 8 | 크래시 창이 1초 → kill 이 완료 뒤에 들어가 판정 무효 | 대장 뒤에 품의서 작성 단계를 넣어 창 확대 |
| 9 | deepagents `write_file` 은 덮어쓰지 않아 실패 시도가 여러 번 생김 → 호출 수로 세면 오판 | 판정을 최종 대장 파일 줄 수(공유 PVC) / 성공한 쓰기 호출 수(샌드박스)로 |

## 처음 요청된 expense_resolution_process 를 쓰지 못한 이유
- `ACT_TEAMLEAD_APPROVAL` 활동에 `type`·`description` 이 없어 completion 이 `/complete` 를 500 으로 거부(이 정의는 현재 시작 불가).
- 에이전트가 쓰는 `expense_*` 테이블은 테넌트 MCP 가 가리키는 원격 Supabase 에 있다. 로컬로 돌리려고 바꿨던 테넌트 MCP·로컬 테이블은 모두 되돌렸다.

## SDK 2차 수정(종료 취소 전달) 뒤 기능 시나리오 재실행
- 6/6 통과: RS-3.2·6.2 ✓, RE-1.1 ✓, RE-1.3·1.4 ✓ (1차 실행) / RE-1.6 ✓, RE-2.1·6.1 ✓, RE-4.1 ✓ (2차 실행).
- 1차 실행 4번째에서 테스트 계정 로그인이 거절됐다(같은 시각 다른 곳에서 계정 비밀번호가 바뀜). 자격 증명을 갱신해 남은 3개를 다시 돌렸다.
