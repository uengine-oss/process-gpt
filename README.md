

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








