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

# kind 설치 (Mac)
brew install kind

# kind 설치 (Windows)
curl.exe -Lo kind.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
```

### 2. 클러스터 생성
```bash
# Mac
kind create cluster --name process-gpt

# Windows 
.\kind.exe create cluster --name process-gpt
```

### 3. 설정 파일 수정 (필수)
`secrets.yaml`에서 실제 값으로 변경:
```yaml
# OpenAI API 키
OPENAI_API_KEY: "sk-your-actual-openai-key"

# Supabase 설정
SUPABASE_KEY: "your-actual-supabase-anon-key"
SERVICE_ROLE_KEY: "your-actual-supabase-service-role-key"
JWT_SECRET: "your-actual-jwt-secret"

# Supabase 데이터베이스 설정
DB_NAME: "your-db-name"
DB_USER: "your-db-user"
DB_PASSWORD: "your-db-password"
DB_HOST: "your-db-host"
DB_PORT: "your-db-port"

# SMTP 설정
SMTP_PASSWORD: "your-smtp-password"

# 기타 API 키들
LANGSMITH_API_KEY: "your-langsmith-api-key"
LANGSMITH_PROJECT: "your-langsmith-project"
MEM_ZERO_API_KEY: "your-mem-zero-api-key"
PERPLEXITY_API_KEY: "your-perplexity-api-key"

# Google Cloud 설정
# google-credentials secret의 credentials.json 내용
```

`configmap.yaml`에서 실제 값으로 변경:
```yaml
SUPABASE_URL: "https://your-project.supabase.co"
SMTP_PORT: "587"
SMTP_SERVER: "smtp.gmail.com"
SMTP_USERNAME: "your-smtp-username"
```

### 4. 배포 순서
```bash
# 1단계: 기본 설정 파일들 먼저 배포 (필수)
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml

kubectl apply -f secrets-test.yaml
kubectl apply -f configmap-test.yaml
kubectl apply -f rbac.yaml
kubectl apply -f pvc.yaml

# 2단계: 모든 deployment와 service 배포
kubectl apply -f deployments/
kubectl apply -f services/
```

### 5. 상태 확인
```bash
kubectl get pods
kubectl get services
kubectl get secrets
kubectl get configmaps
```

### 6. 접근
```bash
kubectl port-forward service/frontend-service 3000:5173
```
브라우저에서 `http://localhost:3000` 접근

## 📚 파일 설명

### 필수 설정 파일들:
- **`secrets.yaml`**: API 키, 데이터베이스 정보, JWT 시크릿 등 민감한 정보 (실제 값으로 수정 필요)
- **`configmap.yaml`**: Supabase URL 등 공개 설정 정보 (실제 값으로 수정 필요)
- **`rbac.yaml`**: MCP Proxy 서비스 계정 권한 설정 (RBAC = Role-Based Access Control)
- **`pvc.yaml`**: LangChain 캐시를 위한 Persistent Volume Claim

### 배포 파일들:
- **`deployments/`**: 모든 애플리케이션 배포 설정
- **`services/`**: 모든 서비스 네트워킹 설정

## 🗑️ 정리
```bash
kubectl delete -f services/
kubectl delete -f deployments/
kubectl delete -f pvc.yaml
kubectl delete -f rbac.yaml
kubectl delete -f configmap.yaml
kubectl delete -f secrets.yaml

# Mac
kind delete cluster --name process-gpt

# Windows 
.\kind.exe delete cluster --name process-gpt
```

## ⚠️ 주의사항

* 실제 API 키와 데이터베이스 정보 필요