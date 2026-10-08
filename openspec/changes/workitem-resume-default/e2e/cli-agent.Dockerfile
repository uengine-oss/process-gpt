# Build from this directory:
#   docker build -t ghcr.io/uengine-oss/process-gpt-cli-agent:latest .
FROM python:3.13-slim

ENV TZ=Asia/Seoul
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata curl gnupg git ca-certificates \
 && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# The CLI agents this service exists to run. Pinned: their stdout is a parsed
# contract, so "whatever npm installs today" is a silent breakage waiting to
# happen. Bump deliberately, with the exec contract tests green against the
# new version.
ARG CLAUDE_CODE_VERSION=2.1.216
ARG CODEX_VERSION=0.144.4
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get update && apt-get install -y --no-install-recommends nodejs \
 && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" "@openai/codex@${CODEX_VERSION}" \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV PYTHONPATH=/app
ENV PIP_DEFAULT_TIMEOUT=300

COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir -r requirements.txt

COPY . .

# Bundled system skills, so an air-gapped deployment has the same skills as a
# connected one. Seeded into SKILLS_DIRS at startup.
COPY system-skills /app/system-skills

# Workspaces must outlive the process: a run paused for a human resumes into its
# own directory, and a download reads from it after the run has exited.
ENV CLIAGENTS_WORKSPACE_ROOT=/workspace
VOLUME ["/workspace"]

EXPOSE 8890
CMD ["python", "server.py"]
