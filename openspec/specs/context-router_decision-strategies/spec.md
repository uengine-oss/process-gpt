# 판단 전략(타입 결정) 명세

## Purpose
`context-router` 서비스가 "주어진 선택지 중 하나를 고르는" 판단을 빠르고 측정 가능한 확률과 함께 제공하는 능력을 보장한다. 판단은 전략 패턴으로 구성되며, 전용 판단 모델(judge)이 설정돼 있으면 그것을 최우선으로 쓰고, 없거나 확신이 부족하면 LLM 의 다음 토큰 로그확률(logprob), 그것도 지원되지 않으면 JSON 응답 순으로 자동 전환한다. 대화 맥락 라우팅, 엔진의 분기 판단, 클라이언트의 의도 분류처럼 반복되는 짧은 판단이 같은 계약을 공유한다.

## Requirements

### Requirement: 선택지 중 하나와 확률을 돌려주는 판단 API
시스템은 `POST /decide` 로 상태(`state`), 질문(`question`), 선택지 목록(`options`: `key`, `label`, 선택 `hint`)을 받아, 선택지 중 정확히 하나(`choice`)와 선택지별 확률(`probabilities`, 합계 1), 확신도(`confidence`), 판단에 쓰인 전략(`strategy`), 모델(`model`), 지연(`latency_ms`)을 SHALL 반환한다. 선택지 밖의 값은 결과로 반환하지 SHALL NOT 한다.

#### Scenario: 정상 판단
- **WHEN** 클라이언트가 세 개의 선택지로 `POST /decide` 를 호출한다
- **THEN** 응답의 `choice` 는 세 선택지의 `key` 중 하나이고, `probabilities` 는 세 키를 모두 포함하며 합이 1 이다

#### Scenario: 선택지가 하나뿐일 때
- **WHEN** 선택지가 하나인 판단을 요청한다
- **THEN** 모델을 호출하지 않고 그 선택지를 확률 1 로 반환하며 `strategy` 는 `trivial` 이다

### Requirement: 전략 우선순위 — 판단 모델 최우선
시스템은 설정된 순서(`DECIDE_STRATEGIES`, 기본 `judge,logprob,json`)대로 전략을 시도하고, 판단 모델 엔드포인트(`DECIDE_JUDGE_URL`)가 설정돼 응답하면 그 결과를 SHALL 사용한다. 앞선 전략이 설정되지 않았거나 응답하지 못하면 다음 전략으로 SHALL 넘어가며, 넘어간 사실을 결과의 `notes` 에 SHALL 남긴다.

#### Scenario: 판단 모델이 설정되고 응답할 때
- **GIVEN** 판단 모델 엔드포인트가 설정돼 있고 정상 응답한다
- **WHEN** 판단을 요청한다
- **THEN** 결과의 `strategy` 는 `judge` 이고 LLM 은 호출되지 않는다

#### Scenario: 판단 모델이 내려가 있을 때
- **GIVEN** 판단 모델 엔드포인트가 응답하지 않는다
- **WHEN** 판단을 요청한다
- **THEN** 결과의 `strategy` 는 `logprob`(지원 시) 또는 `json` 이고, `notes` 에 판단 모델을 건너뛰었다는 기록이 있다

#### Scenario: 아무 전략도 답하지 못할 때
- **WHEN** 설정된 모든 전략이 응답하지 못한다
- **THEN** 시스템은 어떤 전략들을 시도했는지 담은 오류를 반환하고 임의의 선택지를 고르지 않는다

### Requirement: 확신도에 따른 에스컬레이션
시스템은 `DECIDE_ESCALATE_BELOW` 가 설정된 경우, 측정된(calibrated) 확신도가 그 값보다 낮은 결과를 다음 전략으로 SHALL 넘기고, 최종 결과의 `notes` 에 어느 전략의 어떤 판단에서 넘어왔는지 SHALL 남긴다. 더 강한 전략이 없으면 원래 결과를 그 사실과 함께 SHALL 반환한다.

#### Scenario: 망설이는 판단 모델
- **GIVEN** 에스컬레이션 기준이 0.9 이고 판단 모델의 확신도가 0.55 이다
- **WHEN** 판단을 요청한다
- **THEN** 다음 전략(logprob)의 결과가 반환되고 `notes` 에 판단 모델로부터 에스컬레이션됐다는 기록이 있으며 `latency_ms` 는 두 단계를 합한 값이다

#### Scenario: 확신하는 판단 모델
- **GIVEN** 에스컬레이션 기준이 0.9 이고 판단 모델의 확신도가 0.96 이다
- **WHEN** 판단을 요청한다
- **THEN** 판단 모델의 결과가 최종이고 다음 전략은 호출되지 않는다

### Requirement: logprob 전략의 가용성 자동 판별
시스템은 LLM 에 한 글자 답(선택지 문자)을 요청하고 첫 토큰의 상위 로그확률에서 선택지 문자들의 확률만 모아 정규화해 SHALL 판단한다. 엔드포인트가 로그확률을 거부하거나 반환하지 않으면 그 (엔드포인트, 모델)에 대해 이 전략을 SHALL 건너뛴다. 첫 토큰이 선택지 문자가 아니면(생각 모드 모델) 생각 모드를 끈 요청으로 한 번 SHALL 재시도하고, 성공한 요청 형식을 기억해 이후 재시도 없이 SHALL 사용한다.

#### Scenario: 로그확률을 주지 않는 모델
- **GIVEN** LLM 이 로그확률 요청을 거부한다(예: 추론 모델, 로그확률 미지원 제공자)
- **WHEN** 판단을 요청한다
- **THEN** logprob 전략은 건너뛰어지고 JSON 전략의 결과가 반환된다

#### Scenario: 생각 모드 모델
- **GIVEN** LLM 의 첫 토큰이 선택지 문자가 아닌 문장이다
- **WHEN** 판단을 요청한다
- **THEN** 생각 모드를 끈 요청으로 다시 판단하고, 다음 판단부터는 처음부터 그 형식으로 요청한다

### Requirement: 측정된 확신도와 자기 보고 확신도의 구분
시스템은 결과마다 확신도가 토큰 확률·판단 모델로 측정된 값인지(`calibrated: true`), 모델이 스스로 적은 값인지(`calibrated: false`, JSON 전략) SHALL 표시한다. 이 값을 임계값으로 쓰는 클라이언트는 자기 보고 값에 더 엄격한 기준을 SHALL 적용할 수 있어야 한다.

#### Scenario: JSON 전략의 결과
- **WHEN** JSON 전략이 판단한다
- **THEN** 결과의 `calibrated` 는 `false` 이고 `notes` 에 확신도가 자기 보고라는 기록이 있다

### Requirement: 판단 모델 엔드포인트 계약
시스템은 판단 모델과 `POST {state, question, options:[{key,label}]}` → `{choice, probabilities, model}` 계약으로 통신하며, 같은 계약을 따르는 참조 판단 서버를 SHALL 제공한다. 참조 판단 서버는 오픈 웨이트 모델에서 선택지 문자의 다음 토큰 로짓만으로 판단하여 선택지 밖의 답을 내지 SHALL NOT 한다.

#### Scenario: 참조 판단 서버
- **GIVEN** 참조 판단 서버가 오픈 웨이트 모델로 기동돼 있다
- **WHEN** 세 선택지로 판단을 요청한다
- **THEN** 세 선택지에 대한 확률과 선택 하나, 사용한 모델 식별자를 반환한다

### Requirement: 호출자가 특정 전략을 건너뛰는 판단
시스템은 판단 요청마다 건너뛸 전략 목록(`skip`)을 받아, 그 전략을 시도하지 않고 다음 전략부터 SHALL 판단하며, 건너뛴 사실을 결과의 `notes` 에 SHALL 남긴다. 호출자가 앞선 전략의 결과를 다른 근거로 의심할 때(예: 대화 라우팅의 근거 없는 선택) 쓴다.

#### Scenario: 판단 모델을 건너뛴 재판단
- **WHEN** `skip=("judge",)` 로 판단을 요청한다
- **THEN** 결과의 `strategy` 는 `logprob` 또는 `json` 이고 `notes` 에 judge 를 건너뛰었다는 기록이 있다

### Requirement: 참조 판단 서버의 임베딩 엔드포인트
참조 판단 서버는 `EMBED_MODEL`(예: `BAAI/bge-m3`)이 설정되면 OpenAI 형식의 `POST /embeddings`(`input` 문자열 목록 → `data[].embedding`, 정규화된 벡터)를 SHALL 제공하여, 대화 라우팅의 후보 좁히기가 같은 서버의 임베딩을 쓰거나 OpenAI 등 다른 OpenAI 형식 엔드포인트로 바꿔 쓸 수 있어야 한다.

#### Scenario: 임베딩 요청
- **GIVEN** 참조 판단 서버가 `EMBED_MODEL=BAAI/bge-m3` 로 기동돼 있다
- **WHEN** 문장 두 개로 `POST /embeddings` 를 호출한다
- **THEN** 길이 1 로 정규화된 벡터 두 개가 입력 순서대로 돌아온다
