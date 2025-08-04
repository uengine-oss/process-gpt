# Process-GPT Kind 로컬 환경 가이드

Process-GPT를 로컬 Kubernetes 클러스터에서 실행하는 간단한 가이드입니다.

## 📋 필요 도구

* Docker Desktop
* kubectl
* kind

## 🚀 설치 및 실행

### 1. 도구 설치
```bash
# Docker Desktop 설치 후 실행
docker --version

# kubectl 설치
# https://kubernetes.io/docs/tasks/tools/install-kubectl/

# kind 설치 (Windows)
curl.exe -Lo kind.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
```

### 2. 클러스터 생성
```bash
kind create cluster --name process-gpt
```

### 3. 설정 파일 수정
`secrets.yaml`에서 실제 값으로 변경:
```yaml
OPENAI_API_KEY: "sk-your-actual-key"
SUPABASE_URL: "https://your-project.supabase.co"
SUPABASE_KEY: "your-actual-key"
SERVICE_ROLE_KEY: "your-actual-key"
JWT_SECRET: "your-actual-secret"
DB_NAME: "your-db-name"
DB_USER: "your-db-user"
DB_PASSWORD: "your-db-password"
DB_HOST: "your-db-host"
```

`configmap.yaml`에서 실제 값으로 변경:
```yaml
SUPABASE_URL: "https://your-project.supabase.co"
```

### 4. 배포
```bash
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f rbac.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f execution-deployment.yaml
kubectl apply -f gateway-deployment.yaml
kubectl apply -f mcp-proxy-deployment.yaml
```

### 5. 상태 확인
```bash
kubectl get pods
kubectl get services
```

### 6. 접근
```bash
kubectl port-forward service/frontend-service 3000:5173
```
브라우저에서 `http://localhost:3000` 접근

## 🗑️ 정리
```bash
kubectl delete -f .
kind delete cluster --name process-gpt
```

## ⚠️ 주의사항

* 실제 API 키와 데이터베이스 정보 필요