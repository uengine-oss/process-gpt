

## Process GPT Project
**A BPMN-based Multi-Agent Orchestration Framework for the Enterprise**

![Overall Architecture](docs/thumbnails/process-gpt.png)

Process GPT is an open-source platform that combines the 30-year-proven BPMN (Business Process Model and Notation) international standard with the autonomy of modern AI agents. It lets non-technical users design business processes in natural language, lets multiple specialized agents collaborate to execute them, and continuously learns from feedback to make every future run better.

Where classic BPM requires code and specialists, and pure agent frameworks (CrewAI, LangGraph, AutoGen, Swarm/OpenAI SDK) leave you without visual processes, audit trails, or compensation semantics — Process GPT sits at the intersection: **visual + code + standards-based, engineered for production**.

**Online Service**
🌐 [www.process-gpt.io](http://www.process-gpt.io)

## Process-GPT Related Videos

| 대화로 HWPX 문서를 생성하고 편집하는 ProcessGPT | HWPX 문서를 생성하는 AI ProcessGPT | 나노바나나 기반 슬라이드 생성 ProcessGPT |
|:---:|:---:|:---:|
| [![대화로 HWPX 문서를 생성하고 편집하는 [ProcessGPT]](docs/thumbnails/HpcG2IV9nqA.jpg)](https://youtu.be/HpcG2IV9nqA) | [![HWPX 문서를 생성하는 AI [ProcessGPT]](docs/thumbnails/jigU-3CY87Y.jpg)](https://youtu.be/jigU-3CY87Y) | [![나노바나나 기반 슬라이드 생성 [ProcessGPT]](docs/thumbnails/SVrVh_YrF7U.jpg)](https://youtu.be/SVrVh_YrF7U) |
| **6. ProcessGPT 아키텍처** | **ProcessGPT 26년 1월 웨비나_빈 캔버스 위, AI가 그리는 비즈니스의 미래 (Full)** | **Agent Ops 구현 미리보기 - [Process GPT] 휴먼-에이전트 성과 분석** |
| [![6. ProcessGPT 아키텍처](docs/thumbnails/QXS-tL8raqM.jpg)](https://youtu.be/QXS-tL8raqM) | [![ProcessGPT 26년 1월 웨비나_빈 캔버스 위, AI가 그리는 비즈니스의 미래 (Full)](docs/thumbnails/t28gqnPyofg.jpg)](https://youtu.be/t28gqnPyofg) | [![Agent Ops 구현 미리보기 - [Process GPT] 휴먼-에이전트 성과 분석](docs/thumbnails/GZ8WY8LSgeA.jpg)](https://youtu.be/GZ8WY8LSgeA) |
| **ProcessGPT 웨비나 Full** | **ProcessGPT   AI 에이전트 팀이 만드는 완전 자율 업무 시대** | **Process GPT - 나의 친구, 나의 AI 에이전트 (full)** |
| [![ProcessGPT 웨비나 Full](docs/thumbnails/kq4IiPDngQw.jpg)](https://youtu.be/kq4IiPDngQw) | [![ProcessGPT   AI 에이전트 팀이 만드는 완전 자율 업무 시대](docs/thumbnails/eyME6A6K9CM.jpg)](https://youtu.be/eyME6A6K9CM) | [![Process GPT - 나의 친구, 나의 AI 에이전트 (full)](docs/thumbnails/KBxxQvxvmPo.jpg)](https://youtu.be/KBxxQvxvmPo) |
| **Process GPT - 나의 친구, 나의 AI 에이전트** | **[Process-GPT] AI를 이용한 비즈니스 프로세스 / 폼 자동 생성** | **ProcessGPT 1차 프로모션 영상** |
| [![Process GPT - 나의 친구, 나의 AI 에이전트](docs/thumbnails/kd6_hKSQDYc.jpg)](https://youtu.be/kd6_hKSQDYc) | [![[Process-GPT] AI를 이용한 비즈니스 프로세스 / 폼 자동 생성](docs/thumbnails/DI4vLwijsMs.jpg)](https://youtu.be/DI4vLwijsMs) | [![ProcessGPT 1차 프로모션 영상](docs/thumbnails/pUiFodjImcc.jpg)](https://youtu.be/pUiFodjImcc) |
| **Process-GPT e2e 데모** | **process-gpt 채팅 기능 데모** | **process-gpt 인스턴스 실행 데모** |
| [![Process-GPT e2e 데모](docs/thumbnails/U_21lPKoGOI.jpg)](https://youtu.be/U_21lPKoGOI) | [![process-gpt 채팅 기능 데모](docs/thumbnails/UA7kYEk4sAk.jpg)](https://youtu.be/UA7kYEk4sAk) | [![process-gpt 인스턴스 실행 데모](docs/thumbnails/mRTGKSd8Jhg.jpg)](https://youtu.be/mRTGKSd8Jhg) |

---

### Why Process GPT

*   **Flexible and Robust Collaboration via Multi-Agent Systems** — Process GPT configures **multiple AI agents to collaborate within a single BPMN-based business process**, so that multiple agent frameworks can professionally handle complex tasks and share intermediate results. This reliably automates high-complexity work that would be difficult for a single agent. Each agent leverages specialized domain knowledge and tools, and can automatically call upon other specialized agents to delegate tasks when necessary.

*   **Automated Business Process Generation** — Process GPT is designed to let **AI agents automatically define business processes**, producing results without constant human instruction or manual execution of every step. This minimizes human intervention, embodying the *ambient agent* philosophy, and ensures that human involvement does not become a bottleneck.

*   **Natural-Language-Based Continuous Process Learning and Optimization** — Non-expert users can **define business processes using natural language**, which automatically generates initial process models. An **automatic optimization cycle** analyzes user feedback and agent execution logs, continuously improving processes and augmenting training data for workflows that need correction.

*   **Deterministic Regularization of AI Decisions** — When agents repeatedly make the same kind of judgment, Process GPT automatically converts it into a **DMN decision table or Python rule**, guaranteeing that "same input = same output" for enterprise-critical paths while keeping AI flexibility for exceptions.

*   **Enterprise-Grade Reliability** — BPMN Compensation Events provide automatic rollback and compensating transactions on failure. Human-in-the-Loop is a native BPMN pattern, not a workaround. Every step is auditable against an ISO/IEC 19510 process model.

---

### What's Under the Hood

*   **Framework-agnostic Multi-Agent System** — powered by LangChain Deepagents, CrewAI, and more; pick the best runtime per task
*   **BPMN-based Hybrid Process Execution** — deterministic (DMN/code) and stochastic (LLM reasoning) modes in one diagram
*   **Collaborative Work via the Agent-to-Agent (A2A) Protocol** — agents discover and negotiate with each other through Agent Cards
*   **Isolated Agent/Tool Execution** — each MCP and A2A server runs in its own container, orchestrated on Kubernetes with KEDA queue-based autoscaling and a Sidecar isolation pattern
*   **Skill Self-Learning & Feedback Loops** — agents improve their own Skills through a Think → Execute → Reflect cycle driven by user feedback
*   **Context Engineering** — Mem0 + Neo4j knowledge graph + Memento RAG service give agents deep organizational context
*   **Voice & Realtime Channels** — GPT-4 Realtime API + Twilio PSTN integration for voice-driven process triggers
*   **Process Marketplace** — share and reuse verified process templates across teams and organizations
*   **Integrations** — Browser-use, OpenAI Deep Research, Supabase (Postgres, Realtime, Storage, Auth), ERP/CRM via MCP, N8n *(coming soon)*

---

### Core Architecture (5 Layers)

| Layer | Role | Key Components |
|---|---|---|
| **UI & Gateway** | User entry & routing | Vue 3 Frontend, React Voice Agent, Nginx / Spring Cloud Gateway |
| **Core Process** | BPMN definition, instance lifecycle, polling | Execution Engine (FastAPI), Polling Service |
| **Knowledge & RAG** | Document parsing, embedding, retrieval | Memento (Supabase vector DB, Google Drive ingestion) |
| **AI Agents** | Task execution | CrewAI Action, CrewAI Deep Research, OpenAI Deep Research, Browser-Use, BPMN Extractor |
| **Infrastructure** | State, events, storage, auth | Supabase (Postgres, Realtime, Storage, Auth), Docker Compose / Kubernetes |

---

### Where Process GPT Sits in the Market

Process GPT is the only player in the **"BPMN + AI Hybrid"** category — purpose-built for enterprises that need the governance of BPM and the autonomy of modern agents at the same time.

| | ProcessGPT | CrewAI / LangGraph / AutoGen | Dify.ai / n8n | Google ADK / AWS Bedrock |
|---|---|---|---|---|
| **Orchestration** | **BPMN visual modeling** | Code-based roles/graphs | Visual low-code | Console / blueprint |
| **Determinism** | **DMN + Python auto-conversion** | None | Conditional nodes | Guardrails only |
| **Agent-to-Agent** | **A2A + event-driven** | Sequential / group chat | N/A | A2A (Google) / internal |
| **Self-learning** | **Skills + feedback loop** | Memory only | None | None |
| **Compensation** | **BPMN Compensation Events** | None | Basic error branches | None |
| **Autoscaling** | **KEDA + Sidecar** | Manual | Manual | Managed (vendor-locked) |
| **Non-developer access** | **High (NL + visual)** | Low (code) | High | Medium |
| **Deployment** | **Open source, multi-cloud, on-prem** | Library-level | SaaS / self-host | Cloud-locked |

---

### Who It's For

*   **Enterprises modernizing legacy BPM** — keep your BPMN assets, add AI autonomy
*   **Regulated industries** — finance, healthcare, public sector where audit trails and compliance are non-negotiable
*   **Citizen developers** — business users automating their own work in natural language, no coding required
*   **AI teams building production agents** — skip the infrastructure rebuild; get K8s-native isolation, scaling, and observability out of the box

---

### Get Started

*   **Website:** [process-gpt.io](https://www.process-gpt.io)
*   **Documentation:** [docs.process-gpt.io](https://docs.process-gpt.io)
*   **SaaS:** try it instantly at [process-gpt.io](https://process-gpt.io)
*   **Self-host:** clone [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker) and run `docker compose up` to deploy the full local-dev stack; Kubernetes manifests included for production

> *Process GPT creates a new category — "the BPMN of AI agents" — and sets the standard for enterprise multi-agent orchestration.*

Maintained by **uEngine Solutions** · learning@uengine.org



---

## Subprojects

* **API gateway**: [GitHub](https://github.com/uengine-oss/process-gpt-gateway)
* **frontend**: [GitHub](https://github.com/uengine-oss/process-gpt-vue3)
* **completion**: [GitHub](https://github.com/uengine-oss/process-gpt-completion)
* **memento** (Document Memory Storage): [GitHub](https://github.com/uengine-oss/process-gpt-memento)
* **base-agent-langchain-react**: [GitHub](https://github.com/uengine-oss/process-gpt-base-agent-langchain-react)
* **deepagents**: [GitHub](https://github.com/uengine-oss/process-gpt-deepagents)
* **deep-research**: [GitHub](https://github.com/uengine-oss/process-gpt-deep-research)
* **openai-deep-research** (OpenAI-based Deep Research Agent): [GitHub](https://github.com/uengine-oss/process-gpt-openai-deep-research)
* **a2a-orch**: [GitHub](https://github.com/uengine-oss/process-gpt-a2a-orch)
* **react-voice-agent** (Voice Interaction Agent): [GitHub](https://github.com/uengine-oss/process-gpt-react-voice-agent)
* **agent-feedback**: [GitHub](https://github.com/uengine-oss/process-gpt-agent-feedback)
* **mcp-validator**: [GitHub](https://github.com/uengine-oss/process-gpt-mcp-validator)
* **bpmn-extractor** (ProcessGPT BPMN extractor from PDFs): [GitHub](https://github.com/uengine-oss/process-gpt-bpmn-extractor)
* **computer-use**: [GitHub](https://github.com/uengine-oss/process-gpt-computer-use)
* **office-mcp**: [GitHub](https://github.com/uengine-oss/process-gpt-office-mcp)
* **analytic** [GitHub](https://github.com/uengine-oss/process-gpt-analytic)
* **strategy** [GitHub](https://github.com/uengine-oss/process-gpt-strategy)
* **instance-classifier** [GitHub](https://github.com/uengine-oss/process-gpt-instance-classifier)

### Syster(Related) Projects
* **Robo Architect**: [GitHub](https://github.com/uengine-oss/robo-architect)

---

## Design Principles

### Design Principles
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


## Repository Structure (Monorepo)

This repo is a **meta-project**: every microservice listed above lives as a Git
submodule under `services/`, application code stays locally in the root
project, and the **local-install assets (Docker Compose, nginx, env, DB init)
live in the `process-gpt-infra-docker` submodule**.

> **Local install files live in a separate repo.** Docker Compose files and
> configs for local-dev installation are maintained in
> [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> and vendored here as a submodule at `process-gpt-infra-docker/`. See
> [Running the Stack with Docker Compose](#running-the-stack-with-docker-compose)
> below, or the standalone [Local Installation Guide](docs/local-installation-guide.md).

```
process-gpt/
├── .gitmodules                    # Submodule definitions (auto-managed)
├── .env.example                   # Shared env template (reference copy)
│
├── scripts/
│   ├── init-submodules.sh         # One-shot service-submodule add (Bash)
│   └── init-submodules.ps1        # One-shot service-submodule add (PowerShell)
│
├── process-gpt-infra-docker/      # Local install assets (submodule — separate repo)
│   ├── docker-compose.yml         #   Full stack: infra + microservices + gateway
│   ├── nginx/nginx.conf
│   ├── litellm_config.yaml
│   ├── .env.example
│   ├── volumes/                   #   db / api / functions / email-templates / pooler
│   ├── start-all-services.sh/.ps1 #   Interactive launcher (Bash + PowerShell)
│   ├── stop-all-services.sh/.ps1  #   Stop / teardown helpers
│   └── services/                  #   Same microservices, vendored for `build:` targets
│
└── services/                      # All subprojects (submodules — external repos)
    ├── frontend/                  # process-gpt-vue3
    ├── completion/                # process-gpt-completion
    ├── memento/                   # process-gpt-memento
    ├── base-agent-langchain-react/
    ├── deepagents/
    ├── agent-feedback/
    ├── mcp-validator/
    ├── a2a-orch/
    ├── bpmn-extractor/
    ├── computer-use/
    ├── deep-research/
    ├── openai-deep-research/
    ├── office-mcp/
    ├── analytic/
    ├── instance-classifier/
    ├── strategy/
    └── react-voice-agent/
```

### Cloning with submodules

```bash
# Fresh clone (one shot) — includes process-gpt-infra-docker and services/*
git clone --recurse-submodules https://github.com/uengine-oss/process-gpt.git

# Already cloned? Fetch the submodules:
cd process-gpt
git submodule update --init --recursive
```

> If you only want to run the app locally with Docker Compose (no need to
> touch `process-gpt` source at all), you can skip this repo entirely and
> clone [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
> directly — see the [Local Installation Guide](docs/local-installation-guide.md).

### Adding / updating submodules later

Re-run the initializer (idempotent; existing submodules are skipped):

```bash
# Linux / macOS / Git Bash
./scripts/init-submodules.sh

# Windows PowerShell
.\scripts\init-submodules.ps1
```

To pull the latest commit of every submodule:

```bash
git submodule update --remote --merge
```

---

## Running the Stack with Docker Compose

All Docker Compose assets (compose file, nginx, env template, DB init SQL,
launcher scripts) live in the `process-gpt-infra-docker` submodule, not in
this repo's root. Initialize it, then run everything from inside it:

```bash
git submodule update --init process-gpt-infra-docker
cd process-gpt-infra-docker

cp .env.example .env
# Open .env and fill in: LLM API keys, secrets, host IP, SMTP, etc.

./start-all-services.sh          # Linux / macOS / Git Bash
.\start-all-services.ps1         # Windows PowerShell
```

The launcher prompts you to start **all services**, **infra only**, or **pick
individual microservices**, brings up infra (Supabase, Postgres, Neo4j,
LiteLLM) first with `--wait`, then the selected services and the nginx
gateway. It also remembers your last selection and supports named presets
(`--last`, `--save-as`, `--preset`).

Default ports once running:

| Service           | URL                                          |
|-------------------|----------------------------------------------|
| Gateway (Nginx)   | http://localhost:8088                        |
| Completion        | http://localhost:8000                        |
| Memento           | http://localhost:8005                        |
| Supabase Kong     | http://localhost:54321                       |
| Supabase Studio   | http://localhost:`${STUDIO_PORT}` (3001 default) |
| Neo4j Browser     | http://localhost:7474                        |

Full command reference (start/stop options, profiles, troubleshooting) is in
the [Local Installation Guide](docs/local-installation-guide.md) and in
`process-gpt-infra-docker`'s own [README](https://github.com/uengine-oss/process-gpt-infra-docker#readme).

---

## Process-GPT Local Installation Guide

Please refer to the [Local Installation Guide](docs/local-installation-guide.md).


---

## User Manual
📖 [Process-GPT User Manual](https://docs.process-gpt.io/)

