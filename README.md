

## Process GPT Project

Core values of Process GPT:

*   **Autonomous Business Process Automation**: Process GPT is designed to allow **AI agents to automatically execute defined business processes**, producing results without constant human instruction or manual execution of every step. This minimizes human intervention, embodying the ambient agent philosophy, and ensures that human involvement does not become a bottleneck, allowing agents to operate in highly automated processes.

*   **Flexible and Robust Collaboration via Multi-Agent Systems**: Process GPT configures **multiple AI agents to collaborate within a single workflow**, enabling them to professionally handle complex tasks and share intermediate results. This reliably automates high-complexity work that would be difficult for a single agent. Each agent leverages specialized domain knowledge and tools, and can automatically call upon other specialized agents to delegate tasks when necessary.

*   **Natural Language-Based Continuous Process Learning and Optimization**: Process GPT enables non-expert users to **define business processes using natural language**, which automatically generates initial process models. Moreover, it establishes an **automatic optimization cycle** by analyzing user feedback and system logs from agent performance, continuously improving processes and augmenting learning data for incorrect workflows to enhance future performance.

### For Detail:

* **Task Execution through a Multi-Agent System** (powered by CrewAI)
* **BPMN-based Hybrid Process Execution** (Deterministic / Stochastic modes)
* **Collaborative Work via the Agent-to-Agent (A2A) Protocol**
* **Isolated Tool Invocation** through multiple MCP (Model Context Protocol) servers (using Toolhive)
* **Integrations** with Browser-use, OpenAI Deep Research, Supabase, and N8n *(coming soon)*

**Online Service**
🌐 [www.process-gpt.io](http://www.process-gpt.io)

**Demo Video**
🎥 [Watch on YouTube](https://youtu.be/KBxxQvxvmPo?si=dtuKqc-WMTzw0jVh)

---


## Design Principles

### Core Principle
**Users should be able to declare and modify processes, rules, system integration mechanisms, etc. in natural language, and the system should automatically improve with minimal feedback provided during use.**

All such changes must be **logged for tracking and recovery**, while users should simultaneously be able to directly control automation results and regulations through a **generalized UI** at any time.

---

### Principle 1. **Natural Language-Centric Definition and Training-Free Operation**
- All **process definitions, rules, system integrations, and business interfaces** should be writable in **natural language** without requiring programming knowledge or complex logical/mathematical thinking.
- Users should be able to design automation with **business objective or strategic-level descriptions** alone, without undergoing separate training processes.
- The system should be progressively refined and managed through **minimal feedback (approval, modification, rejection)** provided during actual use.

---

### Principle 2. **Human-in-the-Loop and Learning by Example**
- Automated agents must provide **human interfaces** that allow **people to substitute and perform tasks** at any time.
- Each task should provide **necessary context (related data, previous step outputs, similar cases)** in a clear and organized manner to facilitate human processing.
- Agents learn from **actual performance examples** where humans directly handle tasks, correcting and improving their execution knowledge. In other words, **human exemplars** become the agent's training data.

---

### Principle 3. **Automatic Compensation and Separation of Recovery Responsibility**
- When errors or failures occur in automated processes performed by agents, recovery should be automatically implemented through **compensating transactions (rollback)**.
- Operators should not need to track and correct agent details individually; **the system itself should take responsibility for failure recovery and processing**.
- This liberates users from system imperfections and ensures overall business continuity.

--- 


## Subprojects

* **execution** (Execution Engine): [GitHub](https://github.com/uengine-oss/process-gpt-execution)
* **memento** (Document Memory Storage): [GitHub](https://github.com/uengine-oss/process-gpt-memento)
* **crewai-action** (MCP / Multi-Agent Task Execution Agent): [GitHub](https://github.com/uengine-oss/prcoess-gpt-crewai-action)
* **crewai-deep-research** (Multi-Agent Deep Research Agent): [GitHub](https://github.com/uengine-oss/process-gpt-crewai-deep-research)
* **openai-deep-research** (OpenAI-based Deep Research Agent): [GitHub](https://github.com/uengine-oss/process-gpt-openai-deep-research)
* **react-voice-agent** (Voice Interaction Agent): [GitHub](https://github.com/uengine-oss/process-gpt-react-voice-agent)
* **frontend** (Vue3 Frontend): [GitHub](https://github.com/uengine-oss/process-gpt-vue3)
* **API gateway**: [GitHub](https://github.com/uengine-oss/process-gpt-gateway)

---

## Process-GPT Local Installation Guide (Kind)

This is a quick guide to running Process-GPT on a local Kubernetes/Kind cluster.

### 📋 Prerequisites

* Docker
* kubectl
* kind

### 🚀 Installation & Execution

#### 1. Install Required Tools

```bash
# Install and run Docker Desktop
docker --version

# Install kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl/

# Install kind (Mac)
brew install kind

# Install kind (Windows)
curl.exe -Lo kind.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
```

#### 2. Create the Cluster

```bash
# Mac
kind create cluster --name process-gpt

# Windows
.\kind.exe create cluster --name process-gpt
```

#### 3. Clone the repo and see Configuration Files

Clone this repo:
```
git clone https://github.com/uengine-oss/process-gpt
```

See `secrets.yaml`:

```yaml
OPENAI_API_KEY: "sk-your-actual-openai-key"
SUPABASE_KEY: "your-actual-supabase-anon-key"
SERVICE_ROLE_KEY: "your-actual-supabase-service-role-key"
JWT_SECRET: "your-actual-jwt-secret"
DB_NAME: "your-db-name"
DB_USER: "your-db-user"
DB_PASSWORD: "your-db-password"
DB_HOST: "your-db-host"
DB_PORT: "your-db-port"
SMTP_PASSWORD: "your-smtp-password"
LANGSMITH_API_KEY: "your-langsmith-api-key"
LANGSMITH_PROJECT: "your-langsmith-project"
MEM_ZERO_API_KEY: "your-mem-zero-api-key"
PERPLEXITY_API_KEY: "your-perplexity-api-key"
# Google Cloud settings: contents of credentials.json for the google-credentials secret
```

See `configmap.yaml`:

```yaml
SUPABASE_URL: "https://your-project.supabase.co"
SMTP_PORT: "587"
SMTP_SERVER: "smtp.gmail.com"
SMTP_USERNAME: "your-smtp-username"
```

#### 4. Create Database and Obtain the configuration values
- Go to https://supabase.com/ and Click "Start Project" to create a new Project named "process-gpt"
- Go to "Integration" Menu and install "cron" extension (If not, you may encounter "cron schema doesn't exist ERROR")
- Obtain values for SUPABASE_URL, SUPABASE_KEY, SERVICE_ROLE_KEY, JWT_SECRET, DB_HOST, DB_NAME, DB_USER for next configuration
- SUPABASE_URL, SUPABASE_KEY, SERVICE_ROLE_KEY, JWT_SECRET could be obtained from Settings > API Keys / JWT Keys
- DB_HOST, DB_NAME, DB_USER could be obtained from the screen that can be shown by clicking "Connect" menu and select type as "Python" and method should be "Transaction pooler"

  > Youtube video required to understand how to getting this information

#### 5. Create Tables
- Go to "SQL Editor", paste the DDL Script from 'init.sql'

#### 6. Deployment

```bash
# Step 1: Deploy core configuration files (required)
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f rbac.yaml
kubectl apply -f pvc.yaml

# Step 2: Deploy all deployments and services
kubectl apply -f deployments/
kubectl apply -f services/
```

#### 7. Check Status

```bash
kubectl get pods -w
```
then, wait until the logs look like this:
```
NAME                                               READY   STATUS    RESTARTS   AGE
airbnb-agent-859f5b84f-jdtx2                       1/1     Running   0          84m
autonomous-deployment-65cc4bd5d4-842m8             1/1     Running   0          84m
crewai-action-deployment-778d9858dd-r9dwg          1/1     Running   0          84m
crewai-deep-research-deployment-8645d9568d-tzxlt   1/1     Running   0          84m
execution-deployment-cb7d8c4dc-smkm8               1/1     Running   0          5m44s
frontend-deployment-84f95b8986-kk249               1/1     Running   0          84m
gateway-6bc9494c54-wc8qm                           1/1     Running   0          84m
memento-deployment-55879b968b-t9fbj                1/1     Running   0          84m
polling-service-deployment-7dddbfb949-wdd8b        1/1     Running   0          84m
react-voice-agent-75bdf46c58-vl4qv                 1/1     Running   0          84m
```

#### 8. Access the Application

```bash
kubectl port-forward service/gateway 8088:80
```

Open your browser and go to **[http://localhost:8088](http://localhost:8088)**

---

### 📚 File Descriptions

**Core Config Files:**

* `secrets.yaml`: Sensitive values (API keys, DB credentials, JWT secrets) — must be updated with real values.
* `configmap.yaml`: Public configuration values (e.g., Supabase URL) — must be updated with real values.
* `rbac.yaml`: Service account permissions for the MCP Proxy (Role-Based Access Control).
* `pvc.yaml`: Persistent Volume Claim for LangChain caching.

**Deployment Files:**

* `deployments/`: Deployment configurations for all applications.
* `services/`: Networking configurations for all services.

**Database Scheme:**

* `init.sql`: Supabase database table definition script.


---

## User Manual
📖 [Process-GPT User Manual](https://docs.process-gpt.io/)

---

# Process-GPT 로컬 개발 환경 구축 공식 온보딩 가이드

> 이 문서는 Process-GPT를 처음 접하는 개발자가 **다시 위로 올라가서 확인할 필요 없이**
> 처음부터 끝까지 순차적으로 따라가며
> **단 하나의 명령어도 누락 없이**
> 로컬 개발 환경을 완성할 수 있도록 작성된 공식 온보딩 가이드입니다.

---

## 0. 반드시 이 문서를 처음부터 끝까지 읽어야 하는 이유

Process-GPT는 단일 애플리케이션이 아닙니다.  
다음과 같은 **다중 서비스 + 다중 기술 스택**이 정확한 순서와 설정으로 연결되어야 정상 동작합니다.

- Frontend (Vue3 + Vite)
- Gateway (Spring Boot, JWT 인증)
- Completion Service (Python + OpenAI)
- Polling Service (비동기 이벤트 처리)
- Memento Service (메모리/컨텍스트 저장)
- Supabase (Auth + PostgreSQL + Storage)
- Docker 기반 로컬 인프라

👉 **하나라도 누락되면**  
로그인 실패, 401 오류, Completion 무응답, 메모리 저장 실패가 발생합니다.

---

## 1. 전체 아키텍처 개요

```
[Browser]
   ↓
[Vue3 Frontend]
   ↓
[Spring Boot Gateway]  ← JWT 검증 기준점
   ↓
[Completion Service] ←→ [Polling Service]
   ↓
[Memento Service]
   ↓
[Supabase (Auth + DB)]
```

- Gateway는 모든 요청의 **단일 진입점**
- JWT Secret이 Gateway와 Supabase 간 불일치 시 전체 시스템 실패

---

## 2. Repository 준비 (절대 생략 불가)

### 2-1. 작업 디렉토리 생성

```bash
mkdir process-gpt
cd process-gpt
```

### 2-2. Repository Clone

```bash
git clone https://github.com/uengine-oss/process-gpt-vue3
git clone https://github.com/uengine-oss/process-gpt-completion
git clone https://github.com/uengine-oss/process-gpt-memento
```

⚠️ 반드시 **같은 상위 디렉토리**에 존재해야 합니다.

---

## 3. Frontend (process-gpt-vue3) 설정

### 3-1. Node.js 버전 확인

```bash
node -v
```

- **권장 버전:** `v18.17.0`
- 다른 버전 사용 시:
  - Vite 실행 오류
  - dependency 충돌
  - build 실패 가능성

---

### 3-2. 기존 Node 삭제가 필요한 이유 (Windows)

- `nvm`은 Node를 관리하는 도구
- OS에 직접 설치된 Node가 있으면 **PATH 충돌 발생**
- 반드시 기존 Node 제거 필요

**경로**
- 제어판 → 프로그램 제거 → Node.js 삭제

---

### 3-3. nvm 설치

#### Windows
https://github.com/coreybutler/nvm-windows/releases  
→ `nvm-setup.exe` 실행

#### macOS
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

---

### 3-4. Node 18.17.0 설치

```bash
nvm install 18.17.0
nvm use 18.17.0
node -v
```

---

### 3-5. Frontend 의존성 설치

```bash
cd process-gpt-vue3
npm install
```

---

## 4. Supabase 로컬 환경 구축 (Docker 기반)

### 4-1. Docker Desktop 설치

https://www.docker.com/get-started/

Docker Desktop은 **반드시 실행 중**이어야 합니다.

---

### 4-2. Supabase 초기화

```bash
cd process-gpt-vue3
npx supabase init
```

---

### 4-3. Supabase 실행

```bash
cd supabase
npx supabase start
```

정상 실행 시 다음 정보 출력:
- Studio URL
- API URL
- anon key / service key
- JWT Secret

---

### 4-4. DB 초기 스키마 로딩 (필수)

**파일 위치**
```
process-gpt-vue3/docker-compose/volumes/db/init.sql
```

**절차**
1. Supabase Studio 접속
2. SQL Editor 열기
3. `init.sql` 전체 복사 → 실행

⚠️ 이 단계 누락 시 **DB 오류 100% 발생**

---

## 5. Frontend 실행

```bash
cd process-gpt-vue3
npm run dev
```

브라우저에서 출력된 `localhost` 포트 접속

---

## 6. Gateway (Spring Boot) 설정

### 6-1. JDK 설치

```bash
choco install openjdk11 -y
```

### 6-2. Maven 설치

```bash
choco install maven -y
```

확인:

```bash
java -version
mvn -v
```

---

### 6-3. JAVA_HOME 설정 (중요)

```bash
where java
```

예:
```
C:\Program Files\Eclipse Adoptium\jdk-11.0.x\bin\java.exe
```

**환경변수 설정**
- JAVA_HOME = `C:\Program Files\Eclipse Adoptium\jdk-11.0.x`
- Path에 `%JAVA_HOME%\bin` 추가

---

### 6-4. Visual C++ Build Tools 설치

https://visualstudio.microsoft.com/ko/visual-cpp-build-tools/

✔ **"C++를 사용한 데스크톱 개발"** 선택

---

### 6-5. JWT Secret 설정 (가장 중요)

Supabase 실행 시 출력된 JWT Secret 확인 후 수정

**파일**
```
gateway/src/main/java/.../ForwardHostHeaderFilter.java
```

```java
private static final String SECRET_KEY =
    Optional.ofNullable(System.getenv("SECRET_KEY"))
    .orElse("SUPABASE_JWT_SECRET");
```

❌ 다를 경우:
- 로그인 실패
- 모든 API 401

---

### 6-6. Gateway 실행

```bash
cd process-gpt-vue3/gateway
mvn spring-boot:run
```

---

## 7. Completion Service 설정

### 7-1. Python 설치

- 권장 버전: **Python 3.12.0**
- https://www.python.org/downloads/

---

### 7-2. 가상환경 생성

```bash
cd process-gpt-completion
uv venv --python 3.12.0
uv pip install -r requirements.txt
source .venv/Scripts/activate
```

---

### 7-3. `.env` (main.py)

```env
ENV=local
OPENAI_API_KEY=YOUR_KEY

SUPABASE_URL=
SUPABASE_KEY=

DB_HOST=127.0.0.1
DB_PORT=54322
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=postgres
```

---

### 7-4. polling_service `.env`

⚠️ 루트 + polling_service 내부 **2개 생성 필수**

```env
ENV=localhost
OPENAI_API_KEY=

SUPABASE_URL=
SUPABASE_KEY=

MEMENTO_SERVICE_URL=http://localhost:8005
COMPLETION_SERVICE_URL=http://localhost:8000
```

---

### 7-5. Completion 실행

```bash
python main.py
```

새 터미널:

```bash
cd polling_service
python polling_service.py
```

---

## 8. Memento Service 설정

```bash
cd process-gpt-memento
uv venv
uv pip install -r requirements.txt
source .venv/Scripts/activate
```

### `.env`

```env
SUPABASE_URL=
SUPABASE_KEY=
OPENAI_API_KEY=
```

### 실행

```bash
python main.py
```

---

## 9. 전체 실행 순서 (절대 변경 금지)

1. Docker Desktop
2. Supabase
3. Frontend
4. Gateway
5. Completion (main)
6. Completion (polling)
7. Memento

---

## 10. 최종 체크리스트

- [ ] 로그인 성공
- [ ] JWT 정상 검증
- [ ] Completion 응답
- [ ] Polling 이벤트 수신
- [ ] Memory 저장/조회
- [ ] Supabase DB CRUD 정상

---

## 마무리

이 문서는 **Process-GPT 로컬 개발 환경 구축의 공식 기준 문서**입니다.  
신규 개발자 온보딩, 사내 위키, PDF 변환, 자동화 스크립트 작성의 기준으로 활용하십시오.
