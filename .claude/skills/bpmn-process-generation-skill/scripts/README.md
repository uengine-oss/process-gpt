# scripts — 서비스(ProcessGPT deepagent) 모드 후처리

대화형(Claude Code) 모드는 `.bpmn/` 폴더에 파일로 산출물을 만든다(저장/검증 없음).
**서비스 모드**에서는 이 폴더의 스크립트가 09-service-execution.md 의 **출력 계약 JSON**을 받아
**pdf2bpmn 와 동일하게 Supabase 저장 + 실행 검증**을 수행하고, 생성된 프로세스 정보를
**최종 요약 JSON** 으로 반환한다.

## 구성

| 파일 | 역할 |
|------|------|
| `run_postprocess.py` | 오케스트레이터. 입력 계약 → 저장 → (옵션)검증 → 최종 요약 JSON 출력 |
| `save_to_supabase.py` | 저장. elements[]→flattened 변환 + proc_def/configuration/form_def/users/agent_skills/tenants.skills 기록 |
| `validate_process.py` | 검증 래퍼. 벤더링한 ProcessValidator 에 Supabase·LLM 의존성 주입 |
| `validation/process_validator.py` | **pdf2bpmn 에서 그대로 vendoring** 한 실행 검증·자동교정 엔진 (수정 금지) |
| `requirements.txt` | supabase, httpx, anthropic(교정 LLM, 선택) |

## 실행

```bash
pip install -r <skill_dir>/scripts/requirements.txt
python <skill_dir>/scripts/run_postprocess.py --input result.json --tenant <tenant_id>
```

옵션:
- `--no-validate` : 저장만 하고 검증 건너뜀
- `--actor-email <email>` : 검증 실행 시 /initiate·/complete 에 넘길 actor
- `--report-dir <dir>` : 검증 상세 리포트(.md) 저장 위치

`run_postprocess.py` 는 **마지막 stdout 한 줄**에 요약 JSON 을 출력한다(앞 줄은 로그). 호출자는 그 줄을 파싱한다.

## 입력 (출력 계약 JSON)

09-service-execution.md 의 계약. 단일 또는 멀티:
- 단일: `{ "type": "process-definition-result", "processDefinition": {...elements[]...}, "forms": [...], "agents": [...], "skills": [...] }`
- 멀티: `{ "processes": [ <단일 계약>, ... ] }` 또는 `[ {...}, {...} ]`

## 환경변수 (deepagent 런타임 env 상속 — 키를 파일에 넣지 말 것)

deepagent(`core/db.py`·`core/model.py`)와 **동일한 변수명**을 쓴다. deepagent 의 Docker 샌드박스(`core/sandbox/docker_sandbox.py`)가 이 변수들을 컨테이너로 전달하고, `TENANT_ID` 는 **요청 tenant 로 자동 주입**한다.

| 변수 | 용도 |
|------|------|
| `TENANT_ID` | **요청 tenant (deepagent 가 자동 주입)**. `--tenant` 없으면 이 값을 사용 |
| `SUPABASE_URL`(또는 `SUPABASE_KEY_URL`) | Supabase URL (필수) |
| `SERVICE_ROLE_KEY` → `SUPABASE_KEY` → `SUPABASE_ANON_KEY` | Supabase 키 (이 순서로 탐색, 필수) |
| `COMPLETION_ENGINE_URL` | process-gpt-completion 실행 엔진. 비우면 검증 graceful skip |
| `LLM_PROXY_URL` + `LLM_PROXY_API_KEY` (+`LLM_MODEL`) | 검증 자동교정 LLM (OpenAI 호환 프록시, 1순위) |
| `ANTHROPIC_API_KEY` | 자동교정 LLM 2순위 |
| `OPENAI_API_KEY` | 자동교정 LLM 3순위 (셋 다 없으면 교정 없이 검증만) |
| `PDF2BPMN_VALIDATION_MAX_ITERS` | 개선 반복 최대(기본 5) |
| `PDF2BPMN_VALIDATION_ADVANCE_TIMEOUT` | 제출 후 진행 대기 초(기본 70) |
| `PDF2BPMN_VALIDATION_CLEANUP` | 검증 인스턴스 삭제 여부(기본 false) |

> LLM 우선순위는 deepagent `core/model.py` 와 동일: `LLM_PROXY_URL`+`LLM_PROXY_API_KEY` → `ANTHROPIC_API_KEY` → `OPENAI_API_KEY`. 모델명은 `LLM_MODEL`.

## 저장되는 것 (pdf2bpmn 동일)

- `proc_def` : id, name, **definition(flattened)**, bpmn=null, tenant_id, type='bpmn', isdeleted=false. (id 조회→uuid update, 없으면 insert)
- `configuration` : `proc_map` 에 미분류로 등록
- `form_def` : 폼별 id/html/proc_def_id/activity_id/**fields_json**/tenant_id. (tenant+proc+activity 조회→update/insert)
- `users`(is_agent) : 기존 agent user 에 `skills` 병합 + `agent_skills(user_id,tenant_id,skill_name)` 매핑
- `tenants.skills` : 재사용 스킬명 동기화(스키마에 없으면 skip)

## 검증되는 것 (pdf2bpmn 동일)

`validation/process_validator.py` 가 `COMPLETION_ENGINE_URL` 의 `/initiate`·`/complete` 로
start→end 실제 실행, `bpm_proc_inst` 폴링으로 진행 확인. 정적/실행 결함 발견 시 LLM 으로
정의를 자동 교정 후 재저장(최대 N회). 엔진 미도달/키 없음 시 graceful skip.

## flattened 변환 메모

우리 스킬의 `processDefinition` 은 `elements[]` 형식이다. `save_to_supabase.flatten()` 이
이를 ProcessGPT 가 소비하는 flattened 형식(`activities`/`sequences`/`gateways`/`events`/`roles`
분리 배열, `type`=userTask/startEvent/exclusiveGateway 등, `properties`=JSON 문자열)으로
변환한다. pdf2bpmn 의 `proc_def.definition` 형태와 동일하다.
