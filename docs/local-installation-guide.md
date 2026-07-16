## Process-GPT Local Installation Guide (Docker Compose)

This is the quickest way to run the full Process-GPT stack (Supabase, Neo4j,
LiteLLM, nginx gateway, and the application microservices) on your own
machine. All install assets — the compose file, nginx config, `.env`
template, and DB init SQL — live in the
[process-gpt-infra-docker](https://github.com/uengine-oss/process-gpt-infra-docker)
repo, vendored into this repo as the `process-gpt-infra-docker/` submodule.

> Looking for a single-server or production Kubernetes install instead? See
> `.claude/skills/install-process-gpt/references/single-server.md` and
> `production-k8s.md` (Kubernetes manifests for a real cluster live in the
> separate [process-gpt-k8s](https://github.com/uengine-oss/process-gpt-k8s) repo).

### 📋 Prerequisites

* Docker / Docker Compose (Docker Desktop is fine)
* Git
* (optional, only if you want to build services from source instead of
  pulling images) `git submodule` support for nested submodules

### 🚀 Installation & Execution

#### 1. Get the compose files

If you've already cloned `process-gpt` with `--recurse-submodules`, the
compose files are already at `process-gpt-infra-docker/` — just `cd` in:

```bash
cd process-gpt
git submodule update --init process-gpt-infra-docker
cd process-gpt-infra-docker
```

If you only want to run the app and don't need the `process-gpt` source at
all, you can clone `process-gpt-infra-docker` on its own instead:

```bash
git clone https://github.com/uengine-oss/process-gpt-infra-docker.git
cd process-gpt-infra-docker
```

Nested service submodules (`services/*`) are only needed if you want to
build a service from source (`build:` targets, e.g. iterating on the
frontend) rather than pulling its published image:

```bash
# --recursive is intentionally avoided (can misidentify nested worktrees as submodules)
git submodule update --init
```

#### 2. Configure environment

```bash
cp .env.example .env
```

Open `.env` and fill in at minimum an LLM key (OpenAI direct is simplest):

```dotenv
OPENAI_API_KEY=sk-...
LLM_MODEL=gpt-4.1
LLM_PROXY_URL=https://api.openai.com/v1
LLM_PROXY_API_KEY=sk-...        # same as OPENAI_API_KEY
OPENAI_BASE_URL=https://api.openai.com/v1

# local dev: skip email confirmation on signup
ENABLE_EMAIL_AUTOCONFIRM=true
```

Supabase JWT values (`JWT_SECRET`/`ANON_KEY`/`SERVICE_ROLE_KEY`) can stay at
their dev defaults for local use.

#### 3. Start the stack

```bash
# Linux / macOS / Git Bash
./start-all-services.sh

# Windows PowerShell
.\start-all-services.ps1
```

The launcher lets you start **all services**, **infra only**, or **pick
individual microservices** (interactive checkbox menu, multi-select). Infra
(Supabase, Postgres, Neo4j, LiteLLM) always comes up first with `--wait`,
then your selected services, then the nginx gateway.

```text
Choose a start mode:
  1) ALL services
  2) Individual services (select multiple)
  3) Just the infra stack (db / supabase / neo4j / litellm)
  q) Quit
Selection [1/2/3/q]: 2
```

Non-interactive shortcuts:

```bash
./start-all-services.sh all                          # everything
./start-all-services.sh frontend memento completion   # specific services
./start-all-services.sh --last                        # repeat your last selection
```

GHCR images are private — if you haven't logged in and don't already have
the images locally, either log in first:

```bash
echo $GITHUB_PAT | docker login ghcr.io -u <user> --password-stdin
```

or start with `docker compose up -d --pull never <services...>` to force use
of local images.

#### 4. Check status

```bash
docker compose ps -a --format '{{.Service}}\t{{.State}}\t{{.Status}}'
```

Wait for `db`/`kong`/`auth` etc. to report healthy/running before opening the
app — Postgres takes 30–60s on first boot to apply the init SQL.

#### 5. Access the Application

* Gateway (app entry point): **http://localhost:8088**
* Supabase Studio: http://localhost:3001
* Supabase Kong (API): http://localhost:54321
* Neo4j Browser: http://localhost:7474 (only if you started `neo4j`/`bpmn-extractor`)

#### 6. Stop / clean up

```bash
./stop-all-services.sh                 # stop everything
./stop-all-services.sh frontend        # stop just a few services
./stop-all-services.sh --volumes       # stop AND wipe volumes (destructive!)
./stop-all-services.sh --wipe          # also wipe bind-mount dirs (db data/storage/logs)
```

---

### 📚 File Reference (in `process-gpt-infra-docker/`)

* `docker-compose.yml` — full stack: infra (Supabase/Neo4j/LiteLLM), all
  microservices, and the nginx gateway, in one file.
* `nginx/nginx.conf` — gateway routing.
* `litellm_config.yaml` — LiteLLM proxy config.
* `.env.example` — environment variable template.
* `volumes/` — `api/kong.yml`, `db/*.sql` + `db/init/` (schema seed),
  `email-templates/`, `functions/`, `pooler/`.
* `start-all-services.sh` / `.ps1`, `stop-all-services.sh` / `.ps1` —
  interactive launcher/teardown with presets (state in `.process-gpt-state/`,
  git-ignored).

### Troubleshooting

If something doesn't come up cleanly (port conflicts, container name
conflicts, private image pulls, Apple Silicon platform warnings, login/tenant
issues, etc.), check `.claude/skills/install-process-gpt/references/troubleshooting.md`
and `INSTALL_MEMORY.md` at the root of this repo — both catalog issues hit
during real installs with symptom → cause → fix.
