## Context

- 근거 조사: `업무 기록/checkpoint-resume-survey-2026-10-06.md`(§7 제안 구조, §8 우선순위, 실험 E1–E4), `업무 기록/REPORT.md` §11 권고 2번.
- SDK는 이미 "호스트" 역할의 절반(lease, 재점유, 상한 3회)을 한다. 점유 RPC는 `claim_count`를 행에 실어 돌려준다(재점유면 2, 3). 하지만 SDK도 서비스도 이 값을 읽지 않는다.
- 사람 답변(`HUMAN_ASKED` → 답 → `FB_REQUESTED`)과 반려(DRAFT → 반려 → `FB_REQUESTED`)는 점유 시점 행 모양이 같다(`STARTED`, `claim_count`=1, feedback 1건). `draft` 유무는 반려를 거친 뒤 묻는 경우가 있어 기준으로 쓸 수 없다.
- 세 프레임워크의 이어서 실행 방법은 실측으로 하나씩 정해졌다: LangGraph 입력 `None`, Claude Code `--resume` + 이어서 지시, Codex `thread/resume` + 이어서 지시.
- 서비스는 배포된 SDK 버전에 고정(`==0.10.x`)되어 있다. SDK 릴리스와 서비스 배포 순서가 어긋날 수 있다.

## Goals / Non-Goals

**Goals:**
- SDK가 재개 사유·회차·키·답 원문을 표준으로 넘긴다.
- 세 서비스가 그 신호로 이어서 실행해, 실험 E2·E3·E4(같은 파드)에서 완료 단계 재실행 0을 얻는다.
- cli-agent 사람 답변 경로 결함(답 원문 미전달, 세션 미사용)을 고친다.
- deepagents의 체크포인터 초기화 실패가 조용히 InMemory로 넘어가지 않게 한다.
- 모든 변경은 하위 호환이다.

**Non-Goals:**
- todo 키 상태 저장소(`ResumeStore`)와 LangGraph 어댑터의 SDK 이관(조사 §8의 6번) — 다음 단계.
- codex의 진행 중 rollout 파드 밖 미러, cli-agent 다중 파드(조사 §8의 7번). 다른 파드 재개는 이번 범위가 아니다.
- 부수효과 도구의 멱등키.
- `checkpoints*` 테이블의 스키마 편입·보존 정책.

## Decisions

### D1. 재개 정보는 `extras["resume"]` 딕셔너리로 넘긴다
- 실행 문맥의 `extras`(그리고 `metadata`)에 `{"kind","attempt","key","answer_raw"}`를 싣는다. SDK 쪽에는 같은 모양의 불변 값 객체와 해석 함수(`resume_info_of`)를 둔다.
- 서비스는 SDK의 새 심볼을 import하지 않고 이 딕셔너리만 읽는다. 그래서 구버전 SDK와 짝지어 배포돼도 깨지지 않는다(키가 없으면 `fresh`로 보고 기존 동작).
- 대안: 서비스가 SDK 함수를 import → SDK 릴리스 전에는 서비스가 기동하지 못한다. 기각.

### D2. 판정 순서: `claim_count` > feedback `kind` > 없음
- `claim_count > 1`이면 무조건 `reclaim`. 사람 답변을 처리하던 중 죽은 경우도 `reclaim`이다. 이때 deepagents는 남은 interrupt가 있으면 기존 규칙(마지막 feedback 원문으로 `Command(resume)`)이 먼저 적용되고, cli-agent는 실행 시작 직후 저장된 세션(답이 이미 들어간 대화)을 이어 간다.
- feedback 마지막 항목 `kind`로 `human_answer`/`revision`. `kind`가 없는 항목은 `revision`(이전 동작과 같음).
- 대안: 직전 `human_asked` 이벤트 조회 → 점유 경로에 DB 왕복이 하나 늘고 이벤트 저장 실패에 취약. 기각.

### D3. 화면이 feedback 항목에 `kind`를 남긴다
- 질문 카드 답(`resumePatchForAnswer`)은 `human_answer`, 결과 화면의 피드백 전송은 `revision`. 스키마 변경이 없고(feedback은 jsonb 배열), 이 필드를 모르는 소비자는 무시한다.

### D4. 서비스별 재개 입력
| 서비스 | `reclaim` | `human_answer` |
|---|---|---|
| deepagents | 그래프를 만든 뒤 `aget_state`로 `next`가 남았는지 보고, 남았으면 입력 `None`. 남은 interrupt가 있으면 기존 `Command(resume)`가 우선 | 기존 규칙 유지(interrupt가 있으면 원문으로 resume) |
| cli-agent | 실행 첫 이벤트에서 세션 ID를 작업 공간 파일에 저장 → 재점유 때 그 세션 `--resume` + SDK 이어서 지시 | `answer_raw`(없으면 마지막 feedback 원문)로 `plan_resume` → 멈춘 세션 재개 + 원문 답 |
| codex | 프롬프트를 SDK 이어서 지시 + 원래 지시(참고)로 교체 | 해당 없음 |

- deepagents의 `next` 판정은 체크포인트 튜플만으로는 할 수 없어(어느 노드가 다음인지는 그래프가 계산) 그래프 생성 뒤에 한다.
- cli-agent 세션 파일은 HITL pending 파일과 따로 둔다(`.processgpt-session.json`). pending은 "사람을 기다리는가"라는 다른 사실이다.
- cli-agent에서 `kind`가 없는 답(구버전 화면)이라도 pending 파일이 있으면 사람 답변으로 본다. pending 파일은 직전 실행이 사람에게 묻고 멈췄다는 확실한 증거다.

### D5. 이어서 지시 문구는 SDK가 소유한다
- cli-agent `plan_resume`와 E4 C1c 문구가 같은 내용이었다. SDK `continuation_prompt(original)`로 표준화하되, 서비스는 SDK 새 심볼에 의존하지 않도록(D1) 같은 문구를 자기 쪽 상수로 두고 테스트로 SDK 문구와 핵심 요소(중단·반복 금지·이어서)를 맞춘다.
- 원래 지시를 참고로 붙인다: 다른 파드에서 thread가 없어 새로 시작되는 경우에도 모델이 할 일을 알 수 있다.

### D6. deepagents 체크포인터 실패 처리
- 기동 시 `DB_*`가 있으면 체크포인터를 미리 초기화하고, 실패하면 `SystemExit(1)`로 종료한다(쿠버네티스가 재시작·알림).
- 실행 시점에 `DB_*`가 있는데 체크포인터가 없으면 예외를 던진다. SDK 경계가 오류 이벤트 + `FAILED`로 화면에 알린다. 초기화 실패를 영구 플래그로 두지 않고 다음 요청에서 다시 시도한다(일시 장애 뒤 자동 회복).
- `DB_*`가 없으면 기존처럼 InMemory(경고 로그).

## Risks / Trade-offs

- [끊긴 도구는 다시 실행된다(at-least-once)] → 이번 범위 밖. 멱등키는 후속 과제로 남긴다.
- [다른 파드 재개는 여전히 처음부터(codex emptyDir, cli-agent 단일 PVC)] → 이어서 지시에 원래 지시를 포함해 최소한 올바른 작업은 하게 한다. 미러는 후속.
- [`kind` 없는 과거 답은 `revision`으로 분류] → cli-agent는 pending 파일로 보정, deepagents는 interrupt 유무로 판단하므로 영향이 없다. codex는 HITL이 없다.
- [deepagents 기동 실패로 바뀜] → 운영에서 DB가 잠시 내려가면 파드가 CrashLoop. 의도된 동작(조용히 HITL 반복보다 낫다). 로컬은 `DB_*`를 비우면 된다.
- [reclaim인데 그래프 `next`가 비어 있음(결과 저장 직전 사망)] → 기존처럼 새 입력으로 실행. 결과만 다시 만든다.

## Migration Plan

1. SDK 배포(재개 정보 추가). 서비스는 아직 읽지 않으므로 동작 변화 없음.
2. 화면 배포(`kind` 기록).
3. 서비스 배포. 순서가 바뀌어도 D1·D2로 안전하다(재개 정보 없으면 기존 동작).
- 롤백: 서비스만 되돌리면 이전 동작. SDK의 추가 필드는 무해하다.

## Open Questions

- `reclaim` 상한(3회) 도달 시 사용자에게 "재개 실패" 사유를 따로 보여 줄지.
- `answer_raw`를 `revision`에서도 서비스가 요약본 대신 쓰게 할지(현재는 각 서비스 기존 동작 유지).
