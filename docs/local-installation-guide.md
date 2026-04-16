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
