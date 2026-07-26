#!/usr/bin/env bash
# =====================================================================
# post-clone-fixes.sh — process-gpt-infra-docker 클론 직후 알려진 스키마/
# nginx/오케스트레이션 설정 격차를 자동 보정한다.
#
# 이 스크립트가 고치는 문제들은 전부 troubleshooting.md #19~#35에 실전
# 설치에서 실제로 겪은 뒤 기록된 것이다. 매번 새로 겪지 않도록 클론 직후,
# `.env` 작성 후 ~ 첫 `docker compose up` 전에 한 번 실행한다.
#
# 참고: 채팅 파일 첨부(PDF 업로드)를 쓰려면 이 스크립트 외에 Supabase Storage
# 버킷("files","chat-images")도 만들어야 한다 — 이건 실행 중인 DB가 필요해
# 이 스크립트(사전 파일 패치)로는 못 하므로 local-dev.md의 "설치 검증" 단계
# SQL 스니펫을 따로 실행할 것 (troubleshooting.md #32 참고).
#
# 사용법:
#   cd process-gpt-infra-docker   # 레포 루트에서
#   bash /path/to/post-clone-fixes.sh
#
# 멱등적으로 동작한다(이미 고쳐져 있으면 스킵) — 재실행해도 안전하다.
# =====================================================================
set -euo pipefail

ROOT="$(pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ] || [ ! -d "$ROOT/volumes/db" ]; then
  echo "[FAIL] process-gpt-infra-docker 레포 루트에서 실행하세요 (docker-compose.yml, volumes/db 필요)" >&2
  exit 1
fi

CHANGED=0
note() { echo "  [FIX] $1"; CHANGED=1; }
skip() { echo "  [OK]  $1 (이미 반영됨)"; }

echo "== post-clone-fixes: 알려진 설정 격차 자동 보정 =="

# ---------------------------------------------------------------------
# 1) volumes/db/roles.sql — supabase_functions_admin 미존재 시
#    ON_ERROR_STOP으로 전체 init.sql/roles.sql이 중단되는 문제 (#19)
# ---------------------------------------------------------------------
ROLES="$ROOT/volumes/db/roles.sql"
if [ -f "$ROLES" ] && grep -q "ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';" "$ROLES" \
   && ! grep -q "ON_ERROR_STOP off" "$ROLES"; then
  python3 - "$ROLES" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = """ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';"""
new = """ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
-- supabase_functions_admin may not exist yet (created conditionally by
-- 98-webhooks.sql depending on pg_net/schema state, notably under arm64
-- emulation) -- don't let a missing role abort the whole script.
\\set ON_ERROR_STOP off
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
\\set ON_ERROR_STOP on"""
if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("PATCHED")
else:
    print("NOMATCH")
PYEOF
  note "volumes/db/roles.sql — supabase_functions_admin 가드 추가"
else
  skip "volumes/db/roles.sql"
fi

# ---------------------------------------------------------------------
# 2) volumes/db/init.sql — public.agent_orch 미존재 타입 캐스팅 (#27)
#    (전체 init.sql이 이 시점에서 중단되어 fetch_pending_task/
#     record_events_bulk 등 800줄 이상이 통째로 미생성되는 원인)
# ---------------------------------------------------------------------
INITSQL="$ROOT/volumes/db/init.sql"
if [ -f "$INITSQL" ] && grep -q '::public.agent_orch' "$INITSQL"; then
  sed -i.bak 's/t\.agent_orch::public\.agent_orch,/t.agent_orch,/' "$INITSQL"
  sed -i.bak 's/agent_orch public\.agent_orch,/agent_orch text,/' "$INITSQL"
  rm -f "$INITSQL.bak"
  note "volumes/db/init.sql — agent_orch 캐스팅을 text로 수정 (2곳)"
else
  skip "volumes/db/init.sql agent_orch 캐스팅"
fi

# ---------------------------------------------------------------------
# 3) nginx.conf — $upstream_agent 가 옛 컨테이너명(process-gpt-...)을
#    하드코딩해 base-agent-langchain-react를 못 찾는 문제 (#25)
# ---------------------------------------------------------------------
NGINX="$ROOT/nginx/nginx.conf"
if [ -f "$NGINX" ] && grep -q 'set \$upstream_agent process-gpt-base-agent-langchain-react:8000;' "$NGINX"; then
  sed -i.bak 's/set \$upstream_agent process-gpt-base-agent-langchain-react:8000;/set $upstream_agent base-agent-langchain-react:8000;/' "$NGINX"
  rm -f "$NGINX.bak"
  note "nginx/nginx.conf — \$upstream_agent 호스트명 수정"
else
  skip "nginx/nginx.conf \$upstream_agent 호스트명"
fi

# ---------------------------------------------------------------------
# 4) nginx.conf — 프론트가 실제로 호출하는 /process-gpt-deepagents/* 에
#    대한 별칭 라우트가 없어 SPA HTML로 떨어지는 문제 (#28)
# ---------------------------------------------------------------------
if [ -f "$NGINX" ] && ! grep -q '/process-gpt-deepagents/' "$NGINX"; then
  python3 - "$NGINX" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor1 = """    location = /deepagents/chat/stream {
      set $upstream_deepagents deepagents:8888;
      proxy_pass http://$upstream_deepagents/chat/stream;
      proxy_http_version 1.1;
      proxy_buffering off;
      proxy_read_timeout 3600s;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }"""
add1 = anchor1 + """

    # /process-gpt-deepagents/chat/stream -> deepagents:8888 /chat/stream
    # Alias: the frontend's DeepAgentRouterService.js calls this prefix
    # (mismatched with the /deepagents/ routes above) -- see troubleshooting #28.
    location = /process-gpt-deepagents/chat/stream {
      set $upstream_deepagents deepagents:8888;
      proxy_pass http://$upstream_deepagents/chat/stream;
      proxy_http_version 1.1;
      proxy_buffering off;
      proxy_read_timeout 3600s;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }"""

anchor2 = """    location /deepagents/ {
      set $upstream_deepagents_root deepagents:8888;
      rewrite ^/deepagents/(.*)$ /$1 break;
      proxy_pass http://$upstream_deepagents_root;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }"""
add2 = anchor2 + """

    # /process-gpt-deepagents/<path> -> deepagents:8888 /<path> (prefix STRIPPED)
    # Alias for DeepAgentRouterService.js's baseUrl -- see troubleshooting #28.
    location /process-gpt-deepagents/ {
      set $upstream_deepagents_root deepagents:8888;
      rewrite ^/process-gpt-deepagents/(.*)$ /$1 break;
      proxy_pass http://$upstream_deepagents_root;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }"""

missing = []
if anchor1 in content:
    content = content.replace(anchor1, add1)
else:
    missing.append("chat/stream anchor")
if anchor2 in content:
    content = content.replace(anchor2, add2)
else:
    missing.append("prefix anchor")

with open(path, "w") as f:
    f.write(content)

if missing:
    print("PARTIAL: " + ", ".join(missing) + " not found -- check nginx.conf manually")
else:
    print("PATCHED")
PYEOF
  note "nginx/nginx.conf — /process-gpt-deepagents/* 별칭 라우트 추가"
else
  skip "nginx/nginx.conf /process-gpt-deepagents/* 별칭"
fi

# ---------------------------------------------------------------------
# 5) storage/imgproxy — macOS bind mount는 xattr 미지원 (#33)
#    named volume으로 교체해 storage-api의 file 백엔드가 동작하게 한다.
# ---------------------------------------------------------------------
if grep -q '\- \./volumes/storage:/var/lib/storage:z' "$ROOT/docker-compose.yml" 2>/dev/null; then
  sed -i.bak 's#- \./volumes/storage:/var/lib/storage:z#- storage-data:/var/lib/storage#' "$ROOT/docker-compose.yml"
  if ! grep -q '^  storage-data:' "$ROOT/docker-compose.yml"; then
    sed -i.bak 's/^volumes:$/volumes:\n  storage-data:/' "$ROOT/docker-compose.yml"
  fi
  rm -f "$ROOT/docker-compose.yml.bak"
  note "docker-compose.yml — storage/imgproxy를 named volume(storage-data)으로 교체"
else
  skip "docker-compose.yml storage bind mount"
fi

# ---------------------------------------------------------------------
# 6) memento — LLM_BASE_URL/EMBEDDING_BASE_URL이 litellm-proxy 하드코딩 (#34)
# ---------------------------------------------------------------------
# 주의: "LLM_BASE_URL: http://litellm-proxy:4000/v1" 부분 문자열은 다른 서비스의
# "CUSTOM_LLM_BASE_URL: http://litellm-proxy:4000/v1"에도 포함되므로(끝부분 일치),
# 파일 전체 grep으로는 판별 못 한다 — memento 블록 전용 멀티라인 anchor로 판별.
RESULT=$(python3 - "$ROOT/docker-compose.yml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = """      LLM_BASE_URL: http://litellm-proxy:4000/v1
      LLM_MODEL: ${LLM_MODEL}
      OPENAI_API_KEY: ${LLM_PROXY_API_KEY}
      EMBEDDING_BASE_URL: http://litellm-proxy:4000/v1
      OPENAI_EMBEDDING_MODEL: ${OPENAI_EMBEDDING_MODEL:-qwen/qwen3-embedding-4b}"""
new = """      LLM_BASE_URL: ${LLM_PROXY_URL}
      LLM_MODEL: ${LLM_MODEL}
      OPENAI_API_KEY: ${LLM_PROXY_API_KEY}
      EMBEDDING_BASE_URL: ${LLM_PROXY_URL}
      OPENAI_EMBEDDING_MODEL: ${OPENAI_EMBEDDING_MODEL:-text-embedding-3-small}"""
if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("PATCHED")
elif new in content:
    print("ALREADY")
else:
    print("NOMATCH")
PYEOF
)
case "$RESULT" in
  PATCHED) note "docker-compose.yml — memento LLM_BASE_URL/EMBEDDING_BASE_URL을 OpenAI 직결로 수정" ;;
  ALREADY) skip "docker-compose.yml memento LLM_BASE_URL" ;;
  *) echo "  [WARN] memento LLM_BASE_URL 자동패치 실패 — 블록 구조가 바뀐 것으로 보임, 수동 확인 필요" ;;
esac
if [ -f "$ROOT/.env" ] && grep -q '^OPENAI_EMBEDDING_MODEL=qwen/qwen3-embedding-4b$' "$ROOT/.env"; then
  sed -i.bak 's#^OPENAI_EMBEDDING_MODEL=qwen/qwen3-embedding-4b$#OPENAI_EMBEDDING_MODEL=text-embedding-3-small#' "$ROOT/.env"
  rm -f "$ROOT/.env.bak"
  note ".env — OPENAI_EMBEDDING_MODEL을 실제 OpenAI 모델명으로 수정"
else
  skip ".env OPENAI_EMBEDDING_MODEL"
fi

# ---------------------------------------------------------------------
# 7) bpmn-extractor — MEMENTO_BASE_URL 누락, host.docker.internal로 잘못 폴백 (#35)
# ---------------------------------------------------------------------
# 주의: "MEMENTO_BASE_URL: http://memento:8005" 문자열은 base-agent-langchain-react
# 등 다른 서비스에도 정상적으로 존재하므로, 파일 전체에 대한 단순 grep으로는
# bpmn-extractor 블록만 짚어낼 수 없다 (오탐으로 인한 스킵 방지). 아래 anchor는
# bpmn-extractor 블록에만 나오는 고유한 멀티라인 문자열이라 이걸로 판별한다.
if [ -f "$ROOT/docker-compose.yml" ]; then
  RESULT=$(python3 - "$ROOT/docker-compose.yml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
anchor = """      NEO4J_URI: ${NEO4J_URI}
      NEO4J_USER: ${NEO4J_USER}
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8012/api/health', timeout=3).read()" ]"""
add = """      NEO4J_URI: ${NEO4J_URI}
      NEO4J_USER: ${NEO4J_USER}
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
      MEMENTO_BASE_URL: http://memento:8005
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8012/api/health', timeout=3).read()" ]"""
if anchor in content:
    content = content.replace(anchor, add)
    with open(path, "w") as f:
        f.write(content)
    print("PATCHED")
elif add in content:
    print("ALREADY")
else:
    print("NOMATCH")
PYEOF
)
  case "$RESULT" in
    PATCHED) note "docker-compose.yml — bpmn-extractor에 MEMENTO_BASE_URL 추가" ;;
    ALREADY) skip "docker-compose.yml bpmn-extractor MEMENTO_BASE_URL" ;;
    *) echo "  [WARN] bpmn-extractor MEMENTO_BASE_URL 자동패치 실패 — 블록 구조가 바뀐 것으로 보임, 수동 확인 필요" ;;
  esac
fi

# ---------------------------------------------------------------------
# 8) deepagents Docker-outside-of-Docker 샌드박스 지원 (#30, #31)
#    - docker.sock 마운트 (보안 민감 — 사용자 승인 후에만 적용할 것)
#    - workspace_host/SKILLS_HOST를 컨테이너 내부 경로가 아니라 실제
#      호스트 경로로 바꿔야 사촌 컨테이너 bind mount가 성립한다.
#    ⚠️ docker.sock 마운트는 해당 컨테이너에 호스트 Docker 데몬 제어 권한을
#       주는 보안 민감 변경이다 — 이 섹션은 기본 비활성화(--with-deepagents-sandbox
#       플래그를 줄 때만 실행)하고, AI 에이전트가 대신 실행할 때도 반드시
#       사용자에게 먼저 물어보고 승인받은 뒤 이 스크립트를 --with-deepagents-sandbox로
#       재실행할 것.
# ---------------------------------------------------------------------
if [ "${1:-}" = "--with-deepagents-sandbox" ]; then
  echo "  [INFO] deepagents 샌드박스(Docker-outside-of-Docker) 활성화 중 (사용자 승인 전제)"
  mkdir -p "$ROOT/volumes/deepagents-workspace" "$ROOT/volumes/deepagents-skills"

  DAGENT_AGENT_PY="$ROOT/services/deepagents/core/agents/agent.py"
  DAGENT_EXECUTOR_PY="$ROOT/services/deepagents/executor.py"

  if [ -f "$DAGENT_AGENT_PY" ] && ! grep -q "_WORKSPACE_DIR = Path" "$DAGENT_AGENT_PY"; then
    python3 - "$DAGENT_AGENT_PY" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = '_SKILLS_CONTAINER_MOUNT = "/skills"'
new = '''_SKILLS_CONTAINER_MOUNT = "/skills"
# Docker-outside-of-Docker: the sandbox backend passes this path as a bind-mount
# *source* to the host's Docker daemon via docker.sock, so it must be a real
# host path (not this container's internal /app/workspace) when running under
# Docker Desktop / a remote daemon.
_WORKSPACE_DIR = Path(os.getenv("WORKSPACE_HOST", str(_BASE_DIR / "workspace")))'''
content = content.replace(old, new, 1)
content = content.replace(
    'backend = get_or_create_sandbox(tenant_id, workspace_host=_BASE_DIR / "workspace", skills_host=_SKILLS_DIR)',
    'backend = get_or_create_sandbox(tenant_id, workspace_host=_WORKSPACE_DIR, skills_host=_SKILLS_DIR)',
)
with open(path, "w") as f:
    f.write(content)
print("PATCHED agent.py")
PYEOF
    note "services/deepagents/core/agents/agent.py — WORKSPACE_HOST 오버라이드 추가"
  else
    skip "services/deepagents/core/agents/agent.py"
  fi

  if [ -f "$DAGENT_EXECUTOR_PY" ] && grep -q 'workspace_host=_AGENT_BASE_DIR / "workspace"' "$DAGENT_EXECUTOR_PY"; then
    sed -i.bak \
      -e 's/from core\.agents\.agent import _BASE_DIR as _AGENT_BASE_DIR, _SKILLS_DIR as _AGENT_SKILLS_DIR$/from core.agents.agent import _BASE_DIR as _AGENT_BASE_DIR, _SKILLS_DIR as _AGENT_SKILLS_DIR, _WORKSPACE_DIR as _AGENT_WORKSPACE_DIR/' \
      -e 's/workspace_host=_AGENT_BASE_DIR \/ "workspace"/workspace_host=_AGENT_WORKSPACE_DIR/' \
      "$DAGENT_EXECUTOR_PY"
    rm -f "$DAGENT_EXECUTOR_PY.bak"
    note "services/deepagents/executor.py — _AGENT_WORKSPACE_DIR 사용하도록 수정 (4곳)"
  else
    skip "services/deepagents/executor.py"
  fi

  DC="$ROOT/docker-compose.yml"
  if [ -f "$DC" ] && grep -q '^\s*- skills-storage:/app/skills$' "$DC"; then
    python3 - "$DC" "$ROOT" <<'PYEOF'
import sys
path, root = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
content = content.replace(
    '      SKILLS_HOST: "/app/skills"',
    f'      SKILLS_HOST: {root}/volumes/deepagents-skills',
)
content = content.replace(
    '      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}\n    volumes:\n      - skills-storage:/app/skills\n    healthcheck:',
    (
        '      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}\n'
        f'      WORKSPACE_HOST: {root}/volumes/deepagents-workspace\n'
        '    volumes:\n'
        '      - ./volumes/deepagents-skills:/app/skills\n'
        '      - /var/run/docker.sock:/var/run/docker.sock\n'
        '      - ./volumes/deepagents-workspace:/app/workspace\n'
        '    healthcheck:'
    ),
)
with open(path, "w") as f:
    f.write(content)
print("PATCHED docker-compose.yml")
PYEOF
    note "docker-compose.yml — deepagents docker.sock/workspace/skills 바인드마운트 추가"
    echo "  [NOTE] 기존 skills-storage 명명 볼륨에 시드 데이터가 있었다면"
    echo "         'docker cp deepagents:/app/skills/. $ROOT/volumes/deepagents-skills/' 로"
    echo "         먼저 복사해두고 이 스크립트를 실행할 것."
  else
    skip "docker-compose.yml deepagents 볼륨"
  fi
else
  echo "  [SKIP] deepagents 샌드박스 패치는 기본 비활성화 — 사용자 승인 후"
  echo "         'bash post-clone-fixes.sh --with-deepagents-sandbox' 로 별도 실행"
  echo "         (docker.sock 마운트는 해당 컨테이너에 호스트 Docker 제어 권한을 부여하는"
  echo "          보안 민감 변경이라 반드시 먼저 물어보고 승인받아야 한다)"
fi

# ---------------------------------------------------------------------
# 9) volumes/db/init.sql — event_type_enum에 pdf2bpmn HITL 이벤트용 값 누락 (#39)
#    (waiting_for_user/task_cancelled/human_feedback_submitted가 없으면
#     record_events_bulk가 재시도 3회 후 실패, HITL 진행 이벤트가 유실됨)
# ---------------------------------------------------------------------
if [ -f "$INITSQL" ] && grep -q "'task_working'," "$INITSQL" && ! grep -q "'waiting_for_user'," "$INITSQL"; then
  python3 - "$INITSQL" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = """  'human_checked',
  'task_working',
  'error'
  );"""
new = """  'human_checked',
  'task_working',
  'error',
  'waiting_for_user',
  'task_cancelled',
  'human_feedback_submitted'
  );"""
if old in content:
    content = content.replace(old, new, 1)
    with open(path, "w") as f:
        f.write(content)
    print("PATCHED")
else:
    print("NOMATCH")
PYEOF
  note "volumes/db/init.sql — event_type_enum에 waiting_for_user/task_cancelled/human_feedback_submitted 추가"
else
  skip "volumes/db/init.sql event_type_enum"
fi

# ---------------------------------------------------------------------
# 10) Apache AGE 전용 컨테이너(age-postgres) + bpmn-extractor/strategy 와이어링 (#37)
#     strategy(온톨로지 그래프)와 bpmn-extractor(pdf2bpmn 프로세스 그래프)가
#     공유하는 그래프 DB. supabase/postgres 이미지엔 AGE가 없어서 필요하다.
# ---------------------------------------------------------------------
if [ -f "$ROOT/docker-compose.yml" ] && ! grep -q '^  age-postgres:' "$ROOT/docker-compose.yml"; then
  RESULT=$(python3 - "$ROOT/docker-compose.yml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

changed = False

# a) bpmn-extractor: AGE_DSN 추가 + age-postgres 의존성
anchor_a = """      NEO4J_URI: ${NEO4J_URI}
      NEO4J_USER: ${NEO4J_USER}
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
      MEMENTO_BASE_URL: http://memento:8005
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8012/api/health', timeout=3).read()" ]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      - db
      - rest
      - neo4j"""
add_a = """      NEO4J_URI: ${NEO4J_URI}
      NEO4J_USER: ${NEO4J_USER}
      NEO4J_PASSWORD: ${NEO4J_PASSWORD}
      MEMENTO_BASE_URL: http://memento:8005
      # pdf2bpmn의 그래프 저장 계층("Neo4jClient")은 이름과 달리 실제로는
      # PostgreSQL Apache AGE 확장을 쓴다 (troubleshooting #36/#37).
      AGE_DSN: postgresql://postgres:postgres@age-postgres:5432/postgres
      # 기본값(http://localhost:8088/claude-skills)은 nginx에 /claude-skills
      # 라우트가 없어 SPA catch-all에서 200 HTML을 받아 "성공"으로 오인하고
      # 실제로는 스킬 파일이 어디에도 안 써지는 버그였다 (troubleshooting #42).
      # deepagents 컨테이너에 직접 붙여 게이트웨이를 우회한다.
      CLAUDE_SKILLS_BASE_URL: http://deepagents:8888
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8012/api/health', timeout=3).read()" ]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      - db
      - rest
      - neo4j
      - age-postgres

  age-postgres:
    # strategy(온톨로지 그래프)와 bpmn-extractor(pdf2bpmn 프로세스 그래프)가
    # 공유하는 Apache AGE 전용 Postgres. Supabase의 postgres 이미지엔 AGE가
    # 없어서(관리형 Supabase도 동일 제약) 별도 인스턴스를 둔다.
    image: apache/age:release_PG16_1.5.0
    platform: linux/amd64
    # container_name 고정 안 함: services/strategy/docker-compose.age.yml을
    # 별도로 띄워본 적이 있으면 동일 이름("process-gpt-age-postgres")의
    # 컨테이너가 이미 존재해 충돌한다 (troubleshooting #37).
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
    ports:
      - "55433:5432"
    volumes:
      - age-postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U postgres -d postgres" ]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s"""
if anchor_a in content:
    content = content.replace(anchor_a, add_a, 1)
    changed = True

# b) strategy: GRAPH_DB_* 추가 + age-postgres healthy 의존성
anchor_b = """      OPENAI_API_KEY: ${LLM_PROXY_API_KEY:-${OPENAI_API_KEY}}
      OPENAI_BASE_URL: ${LLM_PROXY_URL:-${OPENAI_BASE_URL}}
      MODEL: ${LLM_MODEL:-gpt-4.1}
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" ]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      db:
        condition: service_healthy
      rest:
        condition: service_started"""
add_b = """      OPENAI_API_KEY: ${LLM_PROXY_API_KEY:-${OPENAI_API_KEY}}
      OPENAI_BASE_URL: ${LLM_PROXY_URL:-${OPENAI_BASE_URL}}
      MODEL: ${LLM_MODEL:-gpt-4.1}
      # 온톨로지 그래프(Apache AGE)는 일반 테이블과 별개 인스턴스 —
      # Supabase postgres엔 AGE가 없으므로(관리형도 동일) 전용 age-postgres 사용.
      GRAPH_DB_HOST: age-postgres
      GRAPH_DB_PORT: "5432"
      GRAPH_DB_NAME: postgres
      GRAPH_DB_USER: postgres
      GRAPH_DB_PASSWORD: postgres
    healthcheck:
      test: [ "CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" ]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      db:
        condition: service_healthy
      rest:
        condition: service_started
      age-postgres:
        condition: service_healthy"""
if anchor_b in content:
    content = content.replace(anchor_b, add_b, 1)
    changed = True

# c) top-level volumes: age-postgres-data 명명 볼륨 추가
#    (fix #5가 먼저 실행되면 "volumes:\n  storage-data:\n  litellm-db-data:"가
#    되어 "volumes:\n  litellm-db-data:" 앵커가 안 붙는다 — 순서 무관하게
#    "  litellm-db-data:" 줄 자체를 앵커로 쓴다)
anchor_c = "\n  litellm-db-data:"
add_c = "\n  age-postgres-data:\n  litellm-db-data:"
# 주의: "age-postgres-data:" 부분 문자열은 age-postgres 서비스의 볼륨 마운트
# ("- age-postgres-data:/var/lib/postgresql/data", 위 add_a에서 이미 추가됨)
# 에도 나타나므로, 최상위 선언 여부는 반드시 줄 시작(2칸 들여쓰기 전용) 앵커로
# 판별해야 한다 — 단순 "in content"로 검사하면 항상 True가 되어 이 블록이
# 영영 실행되지 않는다.
if anchor_c in content and add_c not in content:
    content = content.replace(anchor_c, add_c, 1)
    changed = True

if changed:
    with open(path, "w") as f:
        f.write(content)
    print("PATCHED")
else:
    print("NOMATCH")
PYEOF
)
  case "$RESULT" in
    PATCHED) note "docker-compose.yml — age-postgres 서비스 추가 + bpmn-extractor/strategy AGE 와이어링 + CLAUDE_SKILLS_BASE_URL 수정" ;;
    *) echo "  [WARN] age-postgres 자동패치 실패 — 블록 구조가 바뀐 것으로 보임, references/troubleshooting.md #37 참고해 수동 반영 필요" ;;
  esac
else
  skip "docker-compose.yml age-postgres"
fi

# ---------------------------------------------------------------------
# 11) bpmn-extractor 그래프 쿼리 — AGE는 Neo4j 맵 프로젝션 문법(`x {.*}`)을
#     지원하지 않음, properties(x)로 치환 (#38). AGE를 실제로 쓰는 경우에만
#     의미가 있으므로 age-postgres 패치(10번)가 적용된 경우에만 실행한다.
# ---------------------------------------------------------------------
PDF2BPMN_SRC="$ROOT/services/bpmn-extractor/src/pdf2bpmn"
if [ -d "$PDF2BPMN_SRC" ] && grep -q '^  age-postgres:' "$ROOT/docker-compose.yml" 2>/dev/null; then
  RESULT=$(python3 - "$PDF2BPMN_SRC" <<'PYEOF'
import re
import sys
from pathlib import Path

src_dir = Path(sys.argv[1])
targets = [
    src_dir / "graph" / "neo4j_client.py",
    src_dir / "api" / "main.py",
    src_dir / "graph" / "vector_search.py",
]
# Neo4j 맵 프로젝션: `x {.*}` 또는 `x {.f1, .f2, ...}` → `properties(x)`
pattern = re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\{\s*\.(?:\*|[a-zA-Z_][a-zA-Z0-9_]*(?:\s*,\s*\.[a-zA-Z_][a-zA-Z0-9_]*)*)\s*\}")
total = 0
for f in targets:
    if not f.exists():
        continue
    text = f.read_text()
    new_text, n = pattern.subn(lambda m: f"properties({m.group(1)})", text)
    if n:
        f.write_text(new_text)
        total += n
print(f"PATCHED:{total}" if total else "NOMATCH")
PYEOF
)
  case "$RESULT" in
    PATCHED:0|NOMATCH) skip "bpmn-extractor Cypher {.*} 문법" ;;
    PATCHED:*) note "bpmn-extractor — Cypher 맵 프로젝션(${RESULT#PATCHED:}곳)을 properties()로 치환" ;;
    *) echo "  [WARN] bpmn-extractor Cypher 자동패치 확인 필요 (결과: $RESULT)" ;;
  esac
else
  skip "bpmn-extractor Cypher {.*} 문법 (age-postgres 미사용)"
fi

echo
if [ "$CHANGED" = "1" ]; then
  echo "== 완료: 일부 파일이 수정되었습니다. 이후 'docker compose up' 순서대로 진행하세요. =="
else
  echo "== 완료: 이미 전부 반영되어 있어 변경 사항 없음. =="
fi
