# docker-infra

process-gpt 로컬 개발에 필요한 **순수 인프라만** 담당하는 docker-compose 구성.
이 저장소(process-gpt)에 소스가 없는, 이미지를 그대로 pull해서 쓰는 서비스들만
모아뒀다:

- Supabase 전체 스택: `db`(Postgres), `kong`(API Gateway), `auth`(GoTrue),
  `rest`(PostgREST), `realtime`, `storage`, `imgproxy`, `meta`, `functions`
  (Edge Functions), `analytics`(Logflare), `studio`(관리 UI)
- `age-postgres` — Apache AGE 그래프 확장 Postgres (strategy, bpmn-extractor가
  공유)
- `neo4j` — 지식 그래프용
- `litellm-db` / `litellm-proxy` — LLM 프록시

## 포함되지 않은 것

`nginx`(게이트웨이), `agent-router`, `robo-data-glossary-backend`,
`polling-service`는 여기 없다. `nginx`는 frontend/completion/memento/
base-agent-langchain-react/deepagents로 라우팅하는 앱 계층 결합 서비스라
지금 범위에서 뺐고, 나머지 셋은 이 저장소에 소스가 없는 별도 서비스라
같이 안 묶었다. 필요해지면 별도로 연결한다.

`frontend`, `completion`, `memento`, `deepagents`, `base-agent-langchain-react`,
`bpmn-extractor`, `strategy` 등 이 저장소의 `services/<name>` 서브모듈에
소스가 있는 앱 서비스는 **이 compose에 포함되지 않는다.** 각자
`npm run dev`(frontend) 또는 개별 `docker build`/`uvicorn` 등으로 띄운다.

## 사용법

```bash
cd docker-infra
./up.sh      # .env 없으면 .env.example에서 자동 생성 후 전체 기동(healthy 대기)
./down.sh    # 종료 (데이터는 유지, -v를 붙이면 볼륨까지 삭제)
```

기동 후 접속 포인트 (기본값 기준, `.env`에서 변경 가능):

| 서비스 | 접속 |
|---|---|
| Kong (Supabase API Gateway) | http://localhost:54321 |
| Studio (관리 UI) | http://localhost:3001 |
| Postgres 직접 접속 | `localhost:54322` (postgres/`${POSTGRES_PASSWORD}`) |
| Apache AGE 직접 접속 | `localhost:55433` (postgres/postgres) |
| neo4j 브라우저 | http://localhost:7474 |
| LiteLLM 프록시 | http://localhost:4010 |

앱 서비스를 로컬에서 돌릴 때는 `.env`의 `ANON_KEY`/`SERVICE_ROLE_KEY`/
`JWT_SECRET`/`API_EXTERNAL_URL`(Kong 주소)을 그 서비스의 `.env`에도 동일하게
맞춰야 한다.

## 참고

`process-gpt-infra-docker`(별도 저장소)의 원본 compose에서 인프라 서비스
정의만 그대로 가져왔다 — 앱 서비스 소스가 필요한 단일서버/K8s 운영 배포는
계속 `process-gpt-infra-docker`를 독립적으로 클론해서 쓴다
(`.claude/skills/process-gpt-install/references/single-server.md`,
`production-k8s.md` 참고). 이 폴더는 로컬 개발 경로 전용이다.
