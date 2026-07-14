

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
submodule under `services/`, while infrastructure, gateway and orchestration
glue stay locally in the root project.

> **Local install files live in a separate repo.** Docker Compose files and
> configs for local-dev installation have moved to
> [process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker).
> The `infra/`, `gateway/`, and `start-all-services.*` shown below are leftovers
> of the previous layered compose setup and are pending cleanup in a follow-up
> change — don't use them for installation.

```
process-gpt/
├── .gitmodules                    # Submodule definitions (auto-managed)
├── docker-compose.yml             # Root wrapper (include: infra + compose + gateway)
├── .env.example                   # Shared env template (copy to .env)
│
├── start-all-services.sh / .ps1   # Interactive launcher  (Bash + PowerShell)
├── stop-all-services.sh  / .ps1   # Stop / teardown helpers
│
├── infra/                         # Shared infrastructure (LOCAL, not a submodule)
│   ├── docker-compose.yml         #   Supabase, Postgres, Neo4j, LiteLLM
│   ├── litellm_config.yaml
│   └── volumes/                   #   db / api / functions / logs / pooler ...
│
├── gateway/                       # Nginx reverse proxy (LOCAL, not a submodule)
│   ├── docker-compose.yml
│   └── nginx/nginx.conf
│
├── compose/                       # Microservice compose definitions (LOCAL)
│   └── docker-compose.yml         #   frontend, completion, memento, crewai-*, ...
│
├── scripts/
│   ├── init-submodules.sh         # One-shot submodule add (Bash)
│   └── init-submodules.ps1        # One-shot submodule add (PowerShell)
│
└── services/                      # All subprojects (submodules — external repos)
    ├── execution/                 # process-gpt-execution
    ├── memento/                   # process-gpt-memento
    ├── frontend/                  # process-gpt-vue3
    ├── completion/                # process-gpt-completion
    ├── crewai-action/             # process-gpt-crewai-action
    ├── crewai-deep-research/
    ├── openai-deep-research/
    ├── react-voice-agent/
    ├── autonomous-execution/
    ├── agents.github.io/
    ├── generic-agent/
    ├── agent-feedback/
    ├── mcp-validator/
    ├── agent-sdk/
    ├── langchain-react/
    ├── a2a-orch/
    ├── agent-utils/
    ├── bpmn-extractor/
    ├── computer-use/
    ├── claude-skills/
    ├── deep-research/
    ├── office-mcp/
    └── docs/                      # process-gpt-docs.github.io
```

### Cloning with submodules

```bash
# Fresh clone (one shot)
git clone --recurse-submodules https://github.com/uengine-oss/process-gpt.git

# Already cloned? Fetch the submodules:
cd process-gpt
git submodule update --init --recursive
```

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

> Requires **Docker Compose v2.20+** (uses `include`).

### 1. Configure environment

```bash
cp .env.example .env
# Open .env and fill in: secrets, API keys, host IP, SMTP, etc.
```

### 2. Start everything (or a subset) interactively

The launcher prompts you to start **all services**, **infrastructure only**,
or **pick individual microservices** (multi-select with ranges).

```bash
# Linux / macOS / Git Bash
./start-all-services.sh

# Windows PowerShell
.\start-all-services.ps1
```

Example interactive session:

```text
Choose a start mode:
  1) ALL services (everything in infra + compose + gateway)
  2) Individual services (select multiple)
  3) Just the infra stack (db / supabase / neo4j / litellm)
  q) Quit
Selection [1/2/3/q]: 2
```

> **Infra (Supabase / Postgres / Neo4j / LiteLLM) and the gateway (Nginx) are always
> started automatically.** You only select which application microservices to add.

Picking `2` opens a keyboard-driven checkbox menu — no typing required:

```text
Process-GPT - select microservices to start

  [Up/Down] move   [Space] toggle   [A] all/none   [Enter] confirm   [Q] cancel
  Selected: 3 / 23

  > [✓]  1) Frontend (Vue 3)
    [✓]  2) Completion (LangChain chat / form gen)
    [ ]  3) Polling Service
    [✓]  4) Memento (RAG / vector store)
    [ ]  5) Glossary Backend
    [ ]  6) CrewAI Action (multi-agent tasks)
    ...
    [ ] 23) MCP Proxy
```

| Key             | Action                                |
|-----------------|---------------------------------------|
| `↑` / `↓`       | Move the cursor                       |
| `PgUp` / `PgDn` | Move 5 rows at a time                 |
| `Home` / `End`  | Jump to first / last row              |
| `Space`         | Toggle the highlighted row            |
| `A`             | Select all / clear all                |
| `Enter`         | Confirm and start the selected stack  |
| `Q` or `Esc`    | Cancel without starting anything      |

The infra stack (Supabase, Postgres, Neo4j, LiteLLM) is **always** brought up
first; selected services and their `depends_on` graph follow.

### 3. Non-interactive shortcuts

```bash
# Everything at once
./start-all-services.sh all
.\start-all-services.ps1 -All

# Specific services from the CLI (deps resolved automatically)
./start-all-services.sh frontend memento completion
.\start-all-services.ps1 -Services frontend,memento,completion

# Just infra (no app services)
.\start-all-services.ps1 -InfraOnly
```

### 3.1 Repeat last selection / Named presets

Each interactive run saves your selection so you can re-run it without
re-picking. You can also save named presets.

```bash
# Re-run whatever you started last time (one-key shortcut: option 4 in the menu)
./start-all-services.sh --last
.\start-all-services.ps1 -Last

# Save the current selection as a named preset
.\start-all-services.ps1 -Services frontend,memento,completion -SaveAs dev
./start-all-services.sh frontend memento completion --save-as dev

# Load it later (menu option 5 or):
.\start-all-services.ps1 -Preset dev
./start-all-services.sh --preset dev
```

State lives in `.process-gpt-state/` (git-ignored):

```
.process-gpt-state/
├── last-selection.txt        # auto-updated every run
└── presets/
    ├── dev.txt
    ├── voice-demo.txt
    └── ...
```

In the **checkbox menu** option (2), the items from your last run come
**pre-checked**, so usually you only need to press Enter to repeat them.

### 4. Stop / clean up

```bash
# Stop everything
./stop-all-services.sh
.\stop-all-services.ps1

# Stop just a few services
./stop-all-services.sh frontend memento
.\stop-all-services.ps1 -Services frontend,memento

# Tear down AND wipe volumes (destructive!)
./stop-all-services.sh --volumes
.\stop-all-services.ps1 -Volumes

# DEEP CLEAN: also wipe bind-mount dirs (db data, storage, logs).
# Use this if Postgres gets stuck in a restart loop with
#   "Database directory appears to contain a database; Skipping initialization"
#   "could not open directory \"pg_notify\""
./stop-all-services.sh --wipe
.\stop-all-services.ps1 -Wipe
```

### 5. Default ports

| Service           | URL                                          |
|-------------------|----------------------------------------------|
| Gateway (Nginx)   | http://localhost:8088                        |
| Frontend          | http://localhost:8080 (proxied via gateway)  |
| Completion        | http://localhost:8000                        |
| Memento           | http://localhost:8005                        |
| Supabase Kong     | http://localhost:54321                       |
| Supabase Studio   | http://localhost:`${STUDIO_PORT}` (3001 default) |
| Neo4j Browser     | http://localhost:7474                        |
| LiteLLM Proxy     | http://localhost:4000                        |

---

## Process-GPT Local Installation Guide (Kind)

Please refer to the [Local Installation Guide](docs/local-installation-guide.md).


---

## User Manual
📖 [Process-GPT User Manual](https://docs.process-gpt.io/)

