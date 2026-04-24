# Process-GPT Compose Stack

이 폴더는 Process-GPT + Supabase + Neo4j + 내부 서비스 실행용 Docker Compose 번들입니다.

## 제외된 서비스

요청에 따라 아래 6개는 compose에 포함하지 않았습니다.

- `billing-deployment.yaml`
- `fcm-service-deployment.yaml`
- `gateway-skt.yaml`
- `frontend-skt-deployment.yaml`
- `insurance-backoffice.yaml`
- `scaling-agent.yaml`

## 포함된 특이사항

- `browser-use`: KEDA/StatefulSet 없이 단일 컨테이너로 실행
- `bpmn-extractor`(pdf2bpmn): KEDA 없이 단일 API 컨테이너로 실행
- `work-assistant-agent`, `pdf2bpmn`은 LLM 프록시 환경변수 사용:
  - `LLM_MODEL`
  - `LLM_PROXY_URL`
  - `LLM_PROXY_API_KEY`

## 1) 서버로 파일 업로드

```bash
gcloud compute scp --recurse \
  "C:/Users/user/Desktop/process-gpt-llm-proxy/deploy/process-gpt-compose-stack" \
  "instance-20260409-100258:/home/user/process-gpt-gs/" \
  --zone "us-central1-f" --project "process-gpt-419207"
```

## 2) 커스텀 이미지 소스 업로드

```bash
gcloud compute scp --recurse \
  "C:/Users/user/Desktop/work-assistant-agent" \
  "instance-20260409-100258:/home/user/process-gpt-gs/src-work-assistant-agent" \
  --zone "us-central1-f" --project "process-gpt-419207"

gcloud compute scp --recurse \
  "C:/Users/user/Desktop/pdf2bpmn" \
  "instance-20260409-100258:/home/user/process-gpt-gs/src-pdf2bpmn" \
  --zone "us-central1-f" --project "process-gpt-419207"
```

## 3) 서버에서 커스텀 이미지 빌드

```bash
gcloud compute ssh "instance-20260409-100258" --zone "us-central1-f" --project "process-gpt-419207" --command "
  sudo docker build -t local/work-assistant-agent:llm-proxy /home/user/process-gpt-gs/src-work-assistant-agent &&
  sudo docker build -t local/pdf2bpmn:llm-proxy /home/user/process-gpt-gs/src-pdf2bpmn
"
```

## 4) 서버에서 실행

```bash
gcloud compute ssh "instance-20260409-100258" --zone "us-central1-f" --project "process-gpt-419207" --command "
  cd /home/user/process-gpt-gs/process-gpt-compose-stack &&
  sudo docker compose up -d
"
```

## 5) 확인

```bash
gcloud compute ssh "instance-20260409-100258" --zone "us-central1-f" --project "process-gpt-419207" --command "
  cd /home/user/process-gpt-gs/process-gpt-compose-stack &&
  sudo docker compose ps
"
```

# 설치 명령어

아래는 변수만 바꿔서 바로 실행하는 **간단 버전**입니다.

```bash
# 0) 환경 변수
INSTANCE="<vm-name>"
ZONE="<zone>"
PROJECT="<project-id>"
LOCAL_DIR="C:/Users/user/Desktop/process-gpt-llm-proxy/deploy/process-gpt-compose-stack"
```

```bash
# 1) 오프라인 Docker 설치 + compose 폴더 준비 + 설정파일 업로드
gcloud compute ssh --zone "$ZONE" "$INSTANCE" --project "$PROJECT" --command "
  cd /home/user/docker-offline &&
  sudo dnf install --disablerepo='*' ./*.rpm -y &&
  sudo systemctl enable --now docker &&
  mkdir -p /home/user/docker-compose/nginx
"

gcloud compute scp "$LOCAL_DIR/docker-compose.yml" "$INSTANCE:/home/user/docker-compose/docker-compose.yml" --zone "$ZONE" --project "$PROJECT"
gcloud compute scp "$LOCAL_DIR/.env" "$INSTANCE:/home/user/docker-compose/.env" --zone "$ZONE" --project "$PROJECT"
gcloud compute scp "$LOCAL_DIR/litellm_config.yaml" "$INSTANCE:/home/user/docker-compose/litellm_config.yaml" --zone "$ZONE" --project "$PROJECT"
gcloud compute scp "$LOCAL_DIR/nginx/nginx.conf" "$INSTANCE:/home/user/docker-compose/nginx/nginx.conf" --zone "$ZONE" --project "$PROJECT"
```

```bash
# 2) 이미지 로드 + 기동 (agent-router 제외)
gcloud compute ssh --zone "$ZONE" "$INSTANCE" --project "$PROJECT" --command "
  cd /home/user/docker-compose &&
  ls /home/user/docker-images/*.tar | sed '/agent-router/d' | xargs -I{} docker load -i '{}' &&
  docker load -i /home/user/docker-images/process-gpt.tar &&
  docker compose config --services | sed '/^agent-router$/d;/^nginx$/d' | xargs docker compose up -d &&
  docker compose up -d --no-deps nginx &&
  docker compose ps
"
```

```bash
# 3) agent-router까지 올릴 때
gcloud compute ssh --zone "$ZONE" "$INSTANCE" --project "$PROJECT" --command "
  cd /home/user/docker-compose &&
  docker load -i /home/user/docker-images/agent-router.tar &&
  docker compose up -d agent-router &&
  docker compose ps agent-router nginx
"
```

# tar 생성 명령어

docker pull ghcr.io/uengine-oss/<이미지명>
docker save -o "docker-images/<생성할 파일명>.tar" ghcr.io/uengine-oss/<이미지명>

# load 테스트
docker load -i "docker-images/<생성할 파일명>.tar"

# 예시
docker pull ghcr.io/uengine-oss/work-assistant-agent:llm-proxy-v0.0.4
docker save -o "docker-images/0416/ghcr.io_uengine-oss_work-assistant-agent_llm-proxy-v0.0.4.tar" ghcr.io/uengine-oss/work-assistant-agent:llm-proxy-v0.0.4
docker load -i "docker-images/0416/ghcr.io_uengine-oss_work-assistant-agent_llm-proxy-v0.0.4.tar"