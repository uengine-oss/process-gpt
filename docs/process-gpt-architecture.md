
# Process-GPT Architecture and Design

## Deployment Architecture

Process-GPT is an **agent-based BPM platform** composed of multiple microservices, each deployed as a Kubernetes pod. The system runs on Kubernetes (e.g., a local Kind cluster) and integrates with external services (OpenAI, search APIs, etc.) as needed. Key components include: 

- **API Gateway** (Java Spring Boot): The entry point for clients, exposing a unified REST API and routing requests to backend services.
- **Execution Engine** (Python FastAPI): Orchestrates business process flows (BPMN/JSON), managing process definitions and instances. It delegates AI-driven tasks to agent services and interacts with the database for persistence.
- **CrewAI Action Agent** (Python): A multi-agent system for task execution, coordinating multiple AI agents (a “crew”) to complete complex tasks.
- **CrewAI Deep Research Agent** (Python): A multi-agent research assistant that divides research queries among multiple agents (searchers, analyzers, aggregators).
- **OpenAI Deep Research Agent** (Python): A single-agent (LLM-based) service that performs research using OpenAI models and tools.
- **React Voice Agent** (Python): A voice-enabled agent that transcribes speech to text (STT), routes intent, and replies via text-to-speech (TTS).
- **Memento Memory Service** (Python): A document memory and retrieval service. It ingests and stores documents and embeddings, allowing agents to retrieve relevant information (vector database functionality).
- **Supabase (Postgres) Database**: A central PostgreSQL database (managed via Supabase) holds persistent data for the platform – process definitions, process instances, tasks, user info, etc.
- **MCP Proxy**: A bridge for safe tool invocation (Model Context Protocol). Agents call tools via this proxy.

Below is a **deployment diagram** illustrating these components and their interactions:

```mermaid
flowchart LR
  subgraph Kubernetes Cluster
    direction TB;
    Gateway["Gateway\n(Java API Gateway)"];
    Execution["Execution Engine\n(Python FastAPI)"];
    CrewAction["CrewAI Action Agent\n(Python, multi-agent)"];
    CrewResearch["CrewAI Deep Research Agent\n(Python, multi-agent)"];
    OpenAIResearch["OpenAI Deep Research Agent\n(Python, LLM)"];
    VoiceAgent["React Voice Agent\n(Python, voice interface)"];
    Memory["Memento Memory Service\n(Python, vector store)"];
    MCPProxy["MCP Proxy\n(Tool invocation bridge)"];
    
    Gateway --> Execution;
    Gateway --> VoiceAgent;
    VoiceAgent --> Execution;
    Execution --> CrewAction;
    Execution --> CrewResearch;
    Execution --> OpenAIResearch;
    Execution --> Memory;
    CrewAction --> MCPProxy;
    CrewResearch --> MCPProxy;
    OpenAIResearch --> MCPProxy;
    CrewAction --> Memory;
    CrewResearch --> Memory;
    OpenAIResearch --> Memory;
    Execution --> DB[(PostgreSQL\nSupabase DB)];
    Memory --> DB;
    CrewAction --> DB;
    CrewResearch --> DB;
    OpenAIResearch --> DB;
    VoiceAgent --> DB;
  end
  UserClient["User (UI/Web)"] --> Gateway;
  UserVoice["User (Voice)"] -.-> VoiceAgent;
  OpenAIAPI["OpenAI API\n(GPT models)"] --- OpenAIResearch;
  OpenAIAPI --- VoiceAgent;
  ExternalTools["External APIs/Tools\n(Search, Email, etc)"] --- MCPProxy;
```

*Figure: Deployment diagram of Process-GPT microservices and external integrations.*

In this architecture, the **Gateway** service is the single point of access for clients (web UI or other applications). It forwards requests to the appropriate backend services. For example, a user action to start or complete a process goes to the Gateway, which then calls the **Execution Engine**. The Execution Engine manages the process logic, interacts with the database, and if an AI-driven task is required, delegates to one of the agent services. 

The **CrewAI Action** and **Deep Research agents** host the logic for autonomous multi-agent collaborations. They use the **MCP Proxy** to perform tool actions (e.g., web browsing, sending emails) in isolation, using configured tool servers. The **OpenAI Deep Research agent** usually involves a single agent (GPT-4 or similar) that may call the OpenAI API or perform its own tool-augmented reasoning for research tasks. 

The **React Voice Agent** connects microphone/speaker input to the system. It will transcribe user speech to text, send it through the Gateway/Execution Engine or directly to an agent, and then synthesize the response back to speech.

All services share a **common database** (Supabase Postgres) for persistence of state. Secrets and configuration (database credentials, API keys for OpenAI, Supabase URL/key, SMTP settings for email, etc.) are managed via Kubernetes secrets and configmaps. A persistent volume can store cached data such as LangChain indexes or other state that should survive pod restarts.

**Networking:** Within the cluster, services communicate over internal cluster networking (each agent has a Kubernetes Service for discovery). The Gateway exposes an HTTP service (port 80) which is port-forwarded for local access. In production, it would be fronted by an ingress or load balancer. 

---

## Database Schema

All persistent data is stored in a **PostgreSQL database** (via Supabase). The core schema includes tables for **Process Definitions**, **Process Instances**, **Work Items**, **Role Mappings**, **Chat Messages**, and **Documents/Knowledge**. The diagram below illustrates the **entity-relationship model** of the main tables (excluding Supabase’s internal auth tables):

```mermaid
erDiagram
    PROCESS_DEFINITION ||--o{ PROCESS_INSTANCE : "defines"
    PROCESS_DEFINITION {
        UUID id PK
        string name
        text bpmn_model  // BPMN XML or JSON definition
        text description
        timestamptz created_at
        varchar created_by  // user id or email
    }
    PROCESS_INSTANCE ||--o{ WORK_ITEM : "has"
    PROCESS_INSTANCE ||--o{ ROLE_MAPPING : "has"
    PROCESS_INSTANCE ||--o{ CHAT_MESSAGE : "has"
    PROCESS_INSTANCE {
        UUID id PK
        UUID process_def_id FK "→ PROCESS_DEFINITION.id"
        varchar status
        timestamptz started_at
        timestamptz completed_at
        varchar initiated_by
    }
    WORK_ITEM {
        UUID id PK
        UUID process_instance_id FK "→ PROCESS_INSTANCE.id"
        varchar task_name
        varchar status
        varchar assigned_to  // user or agent role
        text result
    }
    ROLE_MAPPING {
        UUID id PK
        UUID process_instance_id FK "→ PROCESS_INSTANCE.id"
        varchar role_name
        varchar user_email  // participant fulfilling the role
    }
    CHAT_MESSAGE {
        UUID id PK
        UUID process_instance_id FK "→ PROCESS_INSTANCE.id"
        varchar sender  // e.g., "User" or agent name
        text content
        timestamptz timestamp
    }
    DOCUMENT }o--o{ PROCESS_DEFINITION : "referenced by"
    DOCUMENT {
        UUID id PK
        text title
        text content  // or URL if stored externally
        vector embedding  // pgvector
        timestamptz added_at
        varchar added_by
    }
```

*Figure: Entity-Relationship Diagram of Process-GPT database schema (key tables).* 

**Explanation:**  
- **PROCESS_DEFINITION** stores templates of business processes (BPMN/JSON).  
- **PROCESS_INSTANCE** records runtime executions of processes, linked to a definition.  
- **WORK_ITEM** represents discrete tasks within a process instance (human or AI).  
- **ROLE_MAPPING** binds abstract roles to concrete users/agents per instance.  
- **CHAT_MESSAGE** logs conversational turns linked to a process instance.  
- **DOCUMENT** stores knowledge with vector embeddings for semantic search (used by agents via Memento).  

---

## Execution Engine (Process Execution Service)

The **Execution Engine** interprets and runs business process models. It loads process definitions and handles process instances and their state. It integrates with **AI agents** via HTTP/A2A calls and with the DB for persistence.

**Core Classes and Structure (inferred):**

```mermaid
classDiagram
    class ProcessEngine {
        + startProcess(definitionId, params)
        + completeTask(taskId, result)
        + invokeAgentTask(task)
        + registerProcessDefinition(def)
        - db : DatabaseConnection
        - agentClients : AgentClient[]
    }
    class ProcessDefinition {
        + id
        + name
        + model  // BPMN or JSON structure
        + roles  // list of roles
        + tasks  // task definitions
    }
    class ProcessInstance {
        + id
        + definitionId
        + status
        + currentStep
        + variables
        + roleAssignments
        + start()
        + markTaskComplete(taskId, result)
    }
    class WorkItem {
        + id
        + instanceId
        + name
        + type  // human or AI
        + status
        + assignee
        + result
    }
    class AgentClient {
        + serviceName
        + invoke(taskDetails)
    }
    class A2AAgentClient {
        + sendMessage(agentId, message)
        + onMessageReceived(message)
    }
    class Mem0AgentClient {
        + queryMemory(query)
    }
    class AgentServer {
        + receiveA2AMessage(message)
        + broadcastToAgents(message)
    }
    class DatabaseManager {
        + saveProcessInstance(instance)
        + loadProcessDefinition(id)
        + fetchPendingWorkItems()
        + updateWorkItemStatus(id, status)
    }

    ProcessEngine o-- ProcessDefinition : "uses"
    ProcessEngine o-- ProcessInstance : "manages"
    ProcessEngine --> AgentClient : "calls"
    ProcessEngine --> DatabaseManager : "persists via"
    ProcessInstance o-- ProcessDefinition : "instance of"
    ProcessInstance *-- WorkItem : "has tasks"
    ProcessInstance "1" o-- "many" ChatMessage : "conversation"
    AgentClient <|-- A2AAgentClient
    AgentClient <|-- Mem0AgentClient
    AgentServer .. A2AAgentClient : "communicates"
    ProcessEngine ..> AgentServer : "embeds A2A server"
```

**Typical Sequence (AI task within a process):**

```mermaid
sequenceDiagram
    participant User
    participant Gateway
    participant ExecEngine as Execution Engine
    participant CrewAgent as CrewAI Action Agent
    participant DB as Database

    User->>Gateway: HTTP POST /processes {definition_id: "contest_submission_evaluation"}
    Gateway->>ExecEngine: Forward request (startProcess)
    ExecEngine->>DB: Insert PROCESS_INSTANCE (running)
    ExecEngine->>DB: Insert WORK_ITEM (task: Evaluate Submission, assignee: AI)
    ExecEngine->>CrewAgent: POST /tasks {context, task details}
    activate CrewAgent
    CrewAgent-->>ExecEngine: 202 Accepted
    CrewAgent->>CrewAgent: [multi-agent analysis & tool use]
    CrewAgent->>ExecEngine: POST /tasks/{id}/complete {result}
    deactivate CrewAgent
    ExecEngine->>DB: Update WORK_ITEM (completed, result)
    ExecEngine-->>Gateway: 200 (process advanced/completed)
    Gateway-->>User: Response (status/result)
```

---

## Memento (Document Memory Service)

**Purpose:** Provide long-term memory and knowledge retrieval (RAG) for agents.

**Core Components (inferred):**

```mermaid
classDiagram
    class MementoService {
        + addDocument(source, metadata)
        + queryKnowledge(queryText) : List<Document>
        - vectorStore : VectorStore
        - loaders : Loader[]
    }
    class DocumentLoader {
        <<abstract>>
        + load(source) : Document
    }
    class FileSystemLoader {
        + load(filePath) : Document
    }
    class GoogleDriveLoader {
        + load(driveFileId) : Document
    }
    class SupabaseStorageLoader {
        + load(bucketPath) : Document
    }
    class Document {
        + id
        + text
        + metadata
        + embedding
    }
    class VectorStore {
        + embed(text) : vector
        + addDocument(Document)
        + querySimilar(vector) : List<Document>
        - index
    }
    class RAGChain {
        + retrieve(question) : List<Document>
        + generateAnswer(question, docs) : string
        - vectorStore : VectorStore
        - llm
    }

    MementoService o-- VectorStore : "uses"
    MementoService o-- RAGChain : "may use"
    MementoService ..> DocumentLoader : "utilizes"
    DocumentLoader <|-- FileSystemLoader
    DocumentLoader <|-- GoogleDriveLoader
    DocumentLoader <|-- SupabaseStorageLoader
    VectorStore o.. Document : "stores"
    RAGChain .. VectorStore : "queries"
    RAGChain ..> Document : "retrieves relevant"
```

**Query Sequence:**

```mermaid
sequenceDiagram
    participant Agent as Agent (e.g., CrewAI)
    participant Memento as Memento API
    participant VectorStore as Vector Index
    participant Supabase as DB

    Agent->>Memento: GET /query?question="What is the latest policy?"
    Memento->>VectorStore: embed(question)
    Memento->>Supabase: SELECT ... ORDER BY embedding <-> :vector LIMIT 5
    Supabase-->>Memento: Top documents
    Memento-->>Agent: JSON docs (excerpts, ids)
    Agent->>Memento: GET /documents/{id}
    Memento->>Supabase: SELECT content FROM documents WHERE id=:id
    Supabase-->>Memento: Content
    Memento-->>Agent: Full text
```

---

## CrewAI Action Agent (Multi-Agent Task Executor)

**Goal:** Manage a crew of role-based AI agents to collaborate on complex tasks (plan → critique → revise → approve).

**Core Structure (inferred):**

```mermaid
classDiagram
    class CrewManager {
        + startCrewTask(taskDetails)
        + getResult() : TaskResult
        - crew : Crew
        - status
    }
    class Crew {
        + agents : Agent[*]
        + addAgent(agent)
        + broadcast(message, fromAgent)
        + coordinateTurn()
    }
    class Agent {
        + name
        + role
        + state
        + tools
        + receiveMessage(message)
        + generateMessage() : message
    }
    class AgentBoss {
        + instructAgents(task, context)
        + evaluateOutputs(outputs)
        + decideNextStep()
    }
    class Tool {
        <<interface>>
        + name
        + execute(params) : result
    }
    class SearchTool {
        + execute(query) : webResults
    }
    class EmailTool {
        + execute(draftParams) : status
    }
    class MCPProxyClient {
        + callTool(toolName, params)
    }

    CrewManager --> Crew : "creates and manages"
    Crew "1" o-- "*" Agent : "has agents"
    Crew .. AgentBoss : "may include"
    AgentBoss --> Crew : "coordinates via"
    Agent --> Tool : "uses"
    Tool <|.. SearchTool
    Tool <|.. EmailTool
    Agent ..> MCPProxyClient : "invokes external tools"
```

**Collaboration Sequence:**

```mermaid
sequenceDiagram
    participant ExecEngine
    participant CrewAI as CrewAI Action Service
    participant AgentBoss as "Agent Boss"
    participant AgentA as "Agent A (Generator)"
    participant AgentB as "Agent B (Critic)"
    participant MCP as MCP Proxy

    ExecEngine->>CrewAI: POST /tasks {"task": "Develop a marketing plan", context:...}
    CrewAI->>AgentBoss: Initialize Crew (Generator, Critic)
    AgentBoss->>AgentA: "Propose a plan for product X."
    AgentBoss->>AgentB: "Critique the plan."
    AgentA->>MCP: (Optional) Search market data
    MCP-->>AgentA: Results
    AgentA-->CrewAI: "Draft Plan: ..."
    AgentB-->CrewAI: "Feedback: ..."
    AgentBoss->>AgentA: "Revise based on feedback."
    AgentA-->CrewAI: "Revised Plan: ..."
    AgentB-->CrewAI: "Approved."
    AgentBoss-->ExecEngine: Final Plan
    CrewAI-->>ExecEngine: 200 OK (task complete)
```

---

## CrewAI Deep Research Agent (Multi-Agent Researcher)

**Goal:** Thorough research using specialized roles (Searcher, Analyst, Lead), combining external sources and internal memory.

**Research Sequence:**

```mermaid
sequenceDiagram
    participant ExecEngine
    participant CrewResearch as CrewAI Deep Research
    participant Lead as Lead Agent
    participant Search as Search Agent
    participant Analyst as Analyst Agent
    participant MCP as Search / Tools

    ExecEngine->>CrewResearch: POST /research {"query": "Compare product X vs Y vs Z"}
    CrewResearch->>Lead: Initialize crew
    Lead->>Search: "Find info on X vs Y vs Z."
    Lead->>Analyst: "Summarize findings."
    Search->>MCP: Web/Perplexity search
    MCP-->>Search: Results (URLs, snippets)
    Search-->CrewResearch: Findings
    Analyst->>Memento: GET /query?question="X vs Y features"
    Memento-->>Analyst: Internal docs
    Analyst-->CrewResearch: Summary
    Lead->>CrewResearch: Compile final report
    CrewResearch-->>ExecEngine: Report (brief)
```

---

## OpenAI Deep Research Agent (Single-Agent Researcher)

**Goal:** Efficient research using a single powerful LLM (e.g., GPT‑4) with tool use (search, memory, calculator).

**Structure (conceptual):**

```mermaid
classDiagram
    class OpenAIResearchAgent {
        + answerQuery(query) : string
        - tools : Tool[]
        - llm
        - promptTemplate
    }
    class Tool_oa {
        + name
        + description
        + call(args) : any
    }
    class WebSearchTool {
        + call(query) : string
    }
    class MemoryQueryTool {
        + call(query) : string
    }
    class CalculatorTool {
        + call(expression) : number
    }

    OpenAIResearchAgent o-- Tool_oa : "uses"
    Tool_oa <|-- WebSearchTool
    Tool_oa <|-- MemoryQueryTool
    Tool_oa <|-- CalculatorTool
```

**Query Sequence:**

```mermaid
sequenceDiagram
    participant ExecEngine
    participant OpenAIAgent as OpenAI Research
    participant OpenAIAPI as GPT-4
    participant Tools as Tools (Search, Memory)

    ExecEngine->>OpenAIAgent: POST /research {"query": "How to improve customer retention?"}
    OpenAIAgent->>OpenAIAPI: Prompt (with available functions)
    OpenAIAPI->>Tools: web_search("customer retention strategies")
    Tools-->>OpenAIAPI: Search results
    OpenAIAPI->>Tools: memory_query("our customer retention policy")
    Tools-->>OpenAIAPI: Internal info
    OpenAIAPI-->>OpenAIAgent: Final answer
    OpenAIAgent-->>ExecEngine: Response
```

---

## React Voice Agent (Voice Interaction Service)

**Goal:** Provide voice UX with STT, intent routing, and TTS.

**Structure (conceptual):**

```mermaid
classDiagram
    class VoiceAgentServer {
        + startListening()
        + handleTranscription(text)
        - sttService : SpeechToText
        - ttsService : TextToSpeech
    }
    class SpeechToText {
        + transcribe(audioStream) : string
    }
    class WhisperSTT {
        + transcribe(audio) : string
    }
    class GoogleSTT {
        + transcribe(audio) : string
    }
    class TextToSpeech {
        + synthesize(text) : audio
    }
    class InteractionManager {
        + processCommand(text)
        + routeQuestion(text)
        - currentContext
    }

    VoiceAgentServer --> SpeechToText : uses
    VoiceAgentServer --> TextToSpeech : uses
    SpeechToText <|-- WhisperSTT
    SpeechToText <|-- GoogleSTT
    VoiceAgentServer --> InteractionManager : delegates
    InteractionManager ..> GatewayAPI : calls
    InteractionManager ..> ExecEngineAPI : calls
    InteractionManager ..> OpenAIResearchAPI : calls
```

**Voice Command Sequence:**

```mermaid
sequenceDiagram
    participant User (Speaking)
    participant VoiceAgent as Voice Agent
    participant Gateway
    participant ExecEngine
    Note over User: "Create a new expense report process for Alice."
    VoiceAgent->>WhisperSTT: Transcribe audio
    WhisperSTT-->>VoiceAgent: "Create a new expense report process for Alice."
    VoiceAgent->>Gateway: POST /processes {"definition":"expense_report","initiator":"Alice"}
    Gateway->>ExecEngine: startProcess
    ExecEngine-->>Gateway: Process started (ID=123)
    Gateway-->>VoiceAgent: Acknowledgement
    VoiceAgent->>TTS: Synthesize response
    VoiceAgent-->>User: "Started the expense report process for Alice."
```

---

## API Gateway

**Role:** Front-door for clients. Routes to internal services, enforces auth (JWT), serves UI (optionally), and handles cross-cutting concerns.

**Gateway Structure (conceptual):**

```mermaid
classDiagram
    class ApiGatewayApplication {
        + main()  // Spring Boot entry
    }
    class RouteConfig {
        + routes()  // define mappings
    }
    class AuthFilter {
        + filter(request)  // JWT validation
    }
    class LoggingFilter {
        + filter(request)  // request logging
    }
    class WebUIController {
        + getIndex()  // serves UI
    }

    ApiGatewayApplication ..> RouteConfig
    ApiGatewayApplication ..> AuthFilter
    ApiGatewayApplication ..> LoggingFilter
    RouteConfig o-- AuthFilter : applies
    RouteConfig o-- LoggingFilter : applies
    ApiGatewayApplication ..> WebUIController
```

**Gateway Request Flow:**

```mermaid
sequenceDiagram
    participant UserApp as Client
    participant Gateway
    participant ExecAPI as Execution Engine
    UserApp->>Gateway: GET /api/process/instances (Bearer JWT)
    Gateway->>Gateway: Validate JWT
    alt Invalid
        Gateway-->>UserApp: 401 Unauthorized
    else Valid
        Gateway->>ExecAPI: GET /instances (with auth)
        ExecAPI-->>Gateway: 200 JSON
        Gateway-->>UserApp: 200 JSON
    end
```

---

## Conclusion

Process-GPT integrates **deterministic BPM** with **agentic AI**. The **Execution Engine** provides structured workflows, the **Memento** service supplies knowledge retrieval, **CrewAI agents** enable multi-agent collaboration for complex tasks, the **OpenAI agent** offers efficient single-agent research, the **Voice Agent** adds natural speech interactions, and the **API Gateway** secures and unifies access. The architecture is modular, scalable on Kubernetes, and extensible via MCP tools and additional agents.
