# E2E 시나리오 — 체크포인트 재개 기본화 (kind + 로컬 Supabase + 실제 브라우저)

## 목적
워크아이템이 다시 실행될 때(크래시 재점유·사람 답변·반려) 각 에이전트 서비스가 이미 끝낸 단계를
반복하지 않고 이어 가는지를, **운영과 같은 배포 형태(쿠버네티스)와 실제 화면**에서 검증한다.
스펙: `../specs/agent-sdk_workitem-resume-signal`, `../specs/deepagents_workitem-checkpoint-resume`,
`../specs/cli-agent_workitem-session-resume`, `../specs/codex_workitem-resume`.

## 구성 (mock 없음)
```
브라우저(Playwright, Chromium) → localhost:18088 (port-forward.sh)
  → gateway(Spring, docker 프로파일) ─┬─ frontend(vue3 빌드)            ─┐
                                       ├─ completion(API)                 │
                                       ├─ process-gpt-{deepagents,cli-agent,codex}
                                       └─ memento                         │
  polling-service ── 워크아이템 진행 ─────────────────────────────────────┤
  deepagents ×2 (+DinD 샌드박스), cli-agent ×1 (PVC), codex 워커 ×1 (emptyDir)
                                  ↓
     로컬 Supabase(호스트 54321/54322) · 로컬 LiteLLM(호스트 4000, gpt-4.1-mini)
```
| 구성요소 | 실물 |
|---|---|
| 클러스터 | 로컬 kind `kind-kind`, 네임스페이스 `resume-e2e` (`k8s/stack.yaml`) |
| 이미지 | 각 저장소 작업 트리로 빌드 + 미릴리스 SDK 층(`build-images.sh`, `Dockerfile.sdk-overlay`) |
| 데이터 | 로컬 Supabase(`supabase_*_process-gpt-vue3`). 클러스터에서는 호스트 게이트웨이 `192.168.5.2` 로 붙는다 |
| LLM | 로컬 LiteLLM `gpt-4.1-mini` (Claude Code 는 Anthropic 호환 엔드포인트로) |
| lease | 20초 / heartbeat 5초 (운영 120/30 과 비율만 같다) |

## 운영 매니페스트와 다른 점(이유)
| 항목 | e2e | 이유 |
|---|---|---|
| 복제 수 | deepagents 2, codex 워커 1 | 다른 파드 재점유 / 같은 파드 재점유를 각각 관찰 |
| cli-agent `IS_SANDBOX=1` | 추가 | 컨테이너가 root 라 Claude Code 가 `command_exec` 를 거부(운영에도 필요 — 결과 문서) |
| codex 이미지 `e2e-bwrap` | bwrap 을 격리 없는 대역으로 교체 | arm64 VM + Rosetta 에서 bubblewrap 이 동작하지 않음(이 머신 한계) |
| frontend 이미지 | 호스트에서 만든 dist 를 운영 런타임 스테이지에 담음 | 저장소 `package-lock.json` 불일치로 `npm ci` 실패(커밋 상태) |

## 사전 조건
- 로컬 Supabase 와 LiteLLM 이 떠 있다. VM 디스크 여유 10GB 이상(`up.sh` 가 점검).
- `./build-images.sh` 로 이미지 적재, `seed.py` 로 계정·에이전트·프로세스 5개 생성.
- e2e 밖의 집힐 수 있는 워크아이템이 없다(`up.sh` 가 점검하고 있으면 시작하지 않는다).

## 실행
```bash
./build-images.sh                  # 이미지 빌드 + kind 적재
DB_URL=... SUPABASE_SERVICE_KEY=... python seed.py
./up.sh                            # 스택 기동 + 포트포워드
npm install && npx playwright test # 전체(약 7분)
kubectl --context kind-kind -n resume-e2e scale deploy/polling-service deploy/process-gpt-deepagents \
  deploy/process-gpt-cli-agent deploy/process-gpt-codex-worker --replicas=0   # 끝나면 폴링 주체를 내린다
```

## 시나리오
테스트 이름이 스펙 시나리오 ID 로 시작한다(`resume.spec.ts`). 화면 조작은 브라우저, 판정은 DB·kubectl.

| ID | 화면에서 하는 일 | 크래시 | 판정 |
|---|---|---|---|
| RS-3.2·RS-6.2 | 초안 결과에 피드백 입력 | – | feedback 마지막 항목 `kind=revision`, 다시 집은 워커 로그 `재개 사유: revision`, 표로 다시 작성 |
| RE-1.1 | deepagents 프로세스 실행 → 결과 확인 | 1단계 도구 완료 직후 그 파드 강제 삭제 | 다른 파드가 `claim_count=2`, 로그 `재개 사유: reclaim`·`마지막 체크포인트부터 이어서`, step1 도구 1회, 결과 화면에 step3 |
| RE-1.3·RE-1.4 | cli-agent 프로세스 실행 → 결과 확인 | step1 기록 직후 파드 강제 삭제(같은 PVC 로 새 파드) | 실행 중 세션 파일 존재, 새 파드 `reclaim`, step1 한 줄이고 kill 전의 그 줄, 결과에 실린 세션 = 기록된 세션 |
| RE-1.6 | codex 프로세스 실행 → 결과 확인 | step1 기록 직후 노드에서 컨테이너 프로세스 SIGKILL(emptyDir 유지) | 같은 파드 restartCount+1, `reclaim`, step1 한 줄이고 kill 전의 그 줄, 대화 rollout 1개(같은 thread) |
| RE-2.1·RS-6.1 | cli-agent 가 멈추면 질문 카드에 답 입력 | – | `HUMAN_ASKED` + 카드에 거부 문구, feedback `kind=human_answer`, 워커 `재개 사유: human_answer`, 멈춘 세션 transcript 에 답 원문 |
| RE-4.1 | – | `DB_PORT=1` 로 deepagents 파드 기동 | 파드 Failed, 종료 코드 1, `기동을 중단한다`, 폴링 서버 미기동 |

## 안전장치
- 테스트 데이터는 `resume_e2e_` 접두어 프로세스와 `resume-e2e@localhost.dev` 계정뿐이다. `seed.py --drop` 으로 지운다.
- polling-service 는 완료 인스턴스의 소스 파일 정리 작업을 함께 돈다(끄는 설정 없음). 테스트가 끝나면 내린다.
