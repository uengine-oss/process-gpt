## ADDED Requirements

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
