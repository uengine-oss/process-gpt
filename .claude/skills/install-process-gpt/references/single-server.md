# 사내 간단 설치형 (단일 서버)

소규모 팀이 사내 서버 1대(Linux 권장, 16GB+ RAM)에 설치하는 경로.
**docker-compose 방식**과 **K3S 방식** 중 사용자가 선택한다.

## 공통 준비 — 프로덕션급 시크릿

로컬 dev 기본값을 절대 그대로 쓰지 않는다:

1. **JWT 세트 재생성 (셋은 반드시 한 묶음)**:
   `JWT_SECRET`(32자+ 랜덤) 새로 만들고, 그 시크릿으로 `ANON_KEY`와
   `SERVICE_ROLE_KEY` JWT를 재발급 — https://supabase.com/docs/guides/self-hosting#api-keys
   ```bash
   openssl rand -base64 32   # JWT_SECRET 후보
   ```
2. `POSTGRES_PASSWORD`, `LITELLM_MASTER_KEY`, `SECRET_KEY_BASE`,
   `LOGFLARE_API_KEY` 등 교체.
3. **접속 호스트 반영** — 서버 IP/도메인으로:
   ```dotenv
   API_EXTERNAL_URL=http://<host>:54321
   SUPABASE_URL=http://<host>:54321
   SUPABASE_PUBLIC_URL=http://<host>:54321
   SITE_URL=http://<host>:8088          # 실제 프론트 진입 URL과 일치시킬 것
   ```
4. **SMTP 실설정** + `ENABLE_EMAIL_AUTOCONFIRM=false` (운영),
   또는 폐쇄망이면 autoconfirm 유지 결정을 사용자와 함께.
5. **테넌트 주의**: tenant_id는 접속 호스트명에서 파생된다. 사용자들이
   `http://gpt.company.com:8088`로 접속하면 tenant는 `gpt.company.com`이 되므로
   가입/시드 계정의 `public.users.tenant_id`와 `tenants` 레코드,
   JWT `app_metadata.tenant_id`가 그 호스트명과 일치해야 한다
   (troubleshooting #12, #13).

## 방식 A — docker-compose (권장: 가장 단순)

로컬 개발용(local-dev.md)과 동일 절차 + 위 시크릿 강화 + 부팅 자동화:

```bash
# GHCR 로그인 (서버엔 로컬 이미지가 없으므로 필수)
echo $GITHUB_PAT | docker login ghcr.io -u <user> --password-stdin

./start-all-services.sh all      # 또는 프로파일 서비스 나열
```

systemd로 재부팅 생존:

```ini
# /etc/systemd/system/process-gpt.service
[Unit]
Description=Process GPT stack
After=docker.service network-online.target
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/process-gpt
ExecStart=/opt/process-gpt/start-all-services.sh --last
ExecStop=/opt/process-gpt/stop-all-services.sh
[Install]
WantedBy=multi-user.target
```

(또는 compose 서비스들에 `restart: unless-stopped`가 이미 있는지 확인하고
`docker compose up -d`만으로 충분한지 판단.)

방화벽: 외부에 열 포트는 8088(게이트웨이)과 54321(Supabase Kong) 2개가 기본.
Studio(3001)는 관리자망에만.

## 방식 B — K3S (단일 노드 Kubernetes)

K8s 운영 경험을 쌓거나 이후 프로덕션 확장을 염두에 둘 때 선택.

```bash
curl -sfL https://get.k3s.io | sh -    # traefik 포함 설치
sudo k3s kubectl get nodes
```

절차는 production-k8s.md의 매니페스트 경로를 따르되 단일 노드 특성만 다르다:

1. **Supabase**: K8s용 자산이 레포에 없으므로 둘 중 하나
   - (간단) Supabase는 호스트에서 docker-compose(infra 계층만)로 돌리고,
     K3S pod들은 `http://<호스트IP>:54321`로 접근
   - (일관) supabase-kubernetes 커뮤니티 Helm 차트로 클러스터 내 설치
2. 네임스페이스/설정:
   ```bash
   kubectl create namespace dev
   # configmap-example.yaml, secrets-example.yaml을 복사·수정 후:
   kubectl -n dev apply -f my-configmap.yaml -f my-secrets.yaml -f rbac.yaml -f pvc.yaml
   ```
3. 디플로이먼트/서비스:
   ```bash
   kubectl -n dev apply -f deployments/
   kubectl -n dev apply -f completion-service.yaml -f frontend-deployment-service.yaml \
     -f memento-service-service.yaml -f gateway-service.yaml -f react-voice-agent-service.yaml
   ```
   `deployments/`(및 `ingress/`, `keda/`, `rbac/`)는
   [process-gpt-k8s](https://github.com/uengine-oss/process-gpt-k8s) 레포에
   있으며, core 서비스(frontend, completion, memento, polling, crewai×2,
   voice, gateway)만 포함한다 — 나머지 서비스가 필요하면 compose 정의를 참고해
   매니페스트를 생성해준다 (이미지·env 매핑은 `process-gpt-infra-docker`의
   `docker-compose.yml`이 원본).
4. 인그레스: K3S 내장 traefik으로 gateway-service를 80/443에 노출하거나
   NodePort 사용.

## 검증·데모

verification.md → demo-playwright.md 순으로 진행하되, URL을 `localhost` 대신
서버 호스트로 치환한다 (tenant_id도 그 호스트명!).
