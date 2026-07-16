# 프로덕션 설치 (Kubernetes — AWS EKS / GCP GKE / Azure AKS)

확장 가능한 운영 환경. [process-gpt-k8s](https://github.com/uengine-oss/process-gpt-k8s)
레포의 `deployments/` 매니페스트는 **Supabase를 매니지드(cloud.supabase.com)
프로젝트로 가정**한다 — 프로덕션에서도 이 조합(K8s에는 앱 서비스만, 데이터
플레인은 매니지드 Supabase)이 가장 단순하고 안전하다.

## 0. 사용자에게 먼저 물을 것

1. 클라우드 (AWS / GCP / Azure / 기존 클러스터 있음)
2. Supabase: 매니지드(권장) vs 셀프호스팅(Helm 차트, 운영 부담 큼)
3. 도메인/TLS 여부 (tenant_id가 도메인에서 파생되므로 도메인 확정이 중요)
4. LLM: OpenAI 직결 vs 사내 프록시 vs LiteLLM 게이트웨이

## 1. 클러스터 준비 (클라우드별)

권장 사양: 노드 3개 × 4vCPU/16GB (Standard 프로파일 기준). 에이전트 동적
스핀업(agent-router)과 KEDA 오토스케일링을 쓰면 노드 오토스케일러도 켠다.

```bash
# AWS EKS
eksctl create cluster --name process-gpt --region ap-northeast-2 \
  --nodegroup-name ng1 --node-type m6i.xlarge --nodes 3 --nodes-min 2 --nodes-max 6

# GCP GKE
gcloud container clusters create process-gpt --region asia-northeast3 \
  --machine-type e2-standard-4 --num-nodes 3 --enable-autoscaling --min-nodes 2 --max-nodes 6

# Azure AKS
az aks create -g process-gpt-rg -n process-gpt --node-count 3 \
  --node-vm-size Standard_D4s_v5 --enable-cluster-autoscaler --min-count 2 --max-count 6
```

이후 `kubectl config current-context`로 연결 확인.

## 2. Supabase 준비

**매니지드(권장)**: supabase.com에서 프로젝트 생성 →
- `SUPABASE_URL=https://<project>.supabase.co`, `ANON_KEY`, `SERVICE_ROLE_KEY`,
  DB 접속정보(Direct connection host/password) 확보
- 레포 루트 `init.sql`을 SQL Editor 또는 psql로 실행해 스키마 시드
  (pgvector extension 활성화 포함, `vecs.sql`도 확인)
- Auth 설정: Site URL = 프론트 도메인, SMTP 연동, 이메일 확인 ON

**셀프호스팅**: 커뮤니티 `supabase-kubernetes` Helm 차트 사용. JWT 세트 재생성
(single-server.md 공통 준비 절 참조), PV 스토리지 클래스·백업 전략을 함께 설계.

## 3. 이미지 레지스트리 접근

`ghcr.io/uengine-oss/*`는 private:

```bash
kubectl -n dev create secret docker-registry ghcr-cred \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=$GITHUB_PAT
# 각 Deployment spec.template.spec에 imagePullSecrets: [{name: ghcr-cred}] 추가
# 또는 default serviceaccount에 패치:
kubectl -n dev patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"ghcr-cred"}]}'
```

## 4. 설정/시크릿

```bash
kubectl create namespace dev   # 매니페스트가 dev 네임스페이스 고정

cp configmap-example.yaml my-configmap.yaml   # name: my-config 유지 (deployment가 참조)
cp secrets-example.yaml  my-secrets.yaml
# 채울 값: SUPABASE_URL, ANON_KEY/SERVICE_ROLE_KEY, DB_*, OPENAI_API_KEY,
#          LLM_MODEL/LLM_PROXY_*, SMTP_*, ENV=prod
kubectl -n dev apply -f my-configmap.yaml -f my-secrets.yaml
kubectl -n dev apply -f rbac.yaml    # agent-router의 동적 pod 생성 권한
kubectl -n dev apply -f pvc.yaml     # memento chroma 등 영속 볼륨
# agent-router용 런타임 시크릿 (없으면 에이전트 스핀업 실패):
kubectl -n dev create secret generic agent-runtime-secrets \
  --from-literal=OPENAI_API_KEY=... --from-literal=SUPABASE_URL=... \
  --from-literal=SUPABASE_KEY=...
```

시크릿은 가능하면 클라우드 시크릿 매니저 연동(External Secrets Operator /
CSI driver)으로 승격을 제안한다.

## 5. 배포

```bash
kubectl -n dev apply -f deployments/
kubectl -n dev apply -f completion-service.yaml -f frontend-deployment-service.yaml \
  -f memento-service-service.yaml -f gateway-service.yaml -f react-voice-agent-service.yaml
kubectl -n dev get pods -w
```

이 매니페스트들(`deployments/` 등)은
[process-gpt-k8s](https://github.com/uengine-oss/process-gpt-k8s) 레포에 있고,
core 서브셋(frontend, completion, memento, polling-service, crewai-action,
crewai-deep-research, react-voice-agent, gateway)만 제공한다. 추가 서비스
(base-agent-langchain-react, deepagents, instance-classifier 등)가 필요하면
**`process-gpt-infra-docker`의 `docker-compose.yml`에 정의된 image·environment를
원본 삼아** Deployment+Service 매니페스트를 생성해준다. 이미지 태그는 그
compose에 고정된 태그를 그대로 쓰는 것이 검증된 조합이다 (버전 불일치가 최다
장애 원인 — troubleshooting #13-b, #15).

## 6. 인그레스 / TLS / 도메인

```bash
# ingress-nginx + cert-manager 설치 후:
# gateway-service(80)를 process-gpt.example.com으로 노출
```

- **tenant_id = 접속 호스트명**이므로 도메인 확정 후 시드 테넌트를 그 이름으로
  생성한다 (`public.tenants.id = 'process-gpt.example.com'` 등, troubleshooting #12).
- WebSocket 경로(`/autonomous`, Realtime)가 인그레스에서 Upgrade 헤더를
  통과시키는지 확인 (troubleshooting #13-b).
- SSE(`/agent/chat/stream`, `/completion/*`)는 버퍼링 off + 긴 read timeout.

## 7. 스케일링 (선택)

- HPA: completion·base-agent 등 stateless 서비스에 CPU 기반 HPA.
- KEDA: 큐 기반 에이전트 오토스케일링 (README 아키텍처 참조).
- agent-router: `K8S_NAMESPACE`, `AGENT_RUNTIME_IMAGE`, TTL 스위퍼 설정 확인.

## 8. 검증·데모

verification.md 체크리스트(URL을 도메인으로 치환) → 통과 시
demo-playwright.md 데모. 프로덕션에서는 데모 계정/테넌트를 별도로 만들어
시연하고 종료 후 정리한다.
