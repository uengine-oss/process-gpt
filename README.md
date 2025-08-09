

## Process GPT Project

**Process-GPT** is an Agentic BPM platform that supports:

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

## Subprojects

* **execution** (Execution Engine): [GitHub](https://github.com/uengine-oss/process-gpt-execution)
* **memento** (Document Memory Storage): [GitHub](https://github.com/uengine-oss/process-gpt-memento)
* **crewai-action** (MCP / Multi-Agent Task Execution Agent): [GitHub](https://github.com/uengine-oss/prcoess-gpt-crewai-action)
* **crewai-deep-research** (Multi-Agent Deep Research Agent): [GitHub](https://github.com/uengine-oss/process-gpt-crewai-deep-research)
* **openai-deep-research** (OpenAI-based Deep Research Agent): [GitHub](https://github.com/uengine-oss/process-gpt-openai-deep-research)
* **react-voice-agent** (Voice Interaction Agent): [GitHub](https://github.com/uengine-oss/process-gpt-react-voice-agent)
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

#### 3. Update Configuration Files (Required)

Edit `secrets.yaml` with your actual values:

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

Edit `configmap.yaml` with your actual values:

```yaml
SUPABASE_URL: "https://your-project.supabase.co"
SMTP_PORT: "587"
SMTP_SERVER: "smtp.gmail.com"
SMTP_USERNAME: "your-smtp-username"
```

#### 4. Deployment Order

```bash
# Step 1: Deploy core configuration files (required)
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secrets-test.yaml
kubectl apply -f configmap-test.yaml
kubectl apply -f rbac.yaml
kubectl apply -f pvc.yaml

# Step 2: Deploy all deployments and services
kubectl apply -f deployments/
kubectl apply -f services/
```

#### 5. Check Status

```bash
kubectl get pods
kubectl get services
kubectl get secrets
kubectl get configmaps
```

#### 6. Access the Application

```bash
kubectl port-forward service/frontend-service 3000:5173
```

Open your browser and go to **[http://localhost:3000](http://localhost:3000)**

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

