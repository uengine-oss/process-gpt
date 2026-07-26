#!/usr/bin/env bash
# =====================================================================
# docker-infra - 순수 인프라 스택 기동 (Supabase 전체 + Apache AGE + neo4j
# + LiteLLM). 앱 서비스(frontend/completion/... services/<name>)는 이
# 스택에 포함되지 않는다 — 각자 npm run dev / 개별 docker build로 실행할 것.
#
#   ./up.sh          # 전체 기동 + healthy 대기
# =====================================================================

set -e

cd "$(dirname "$0")"

ROOT="$(pwd)"
ENV_FILE="${ROOT}/.env"

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose --env-file "${ENV_FILE}" -f "${ROOT}/docker-compose.yml" "$@"
    else
        docker-compose --env-file "${ENV_FILE}" -f "${ROOT}/docker-compose.yml" "$@"
    fi
}

if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${ROOT}/.env.example" ]; then
        echo "  .env not found -> copying from .env.example"
        cp "${ROOT}/.env.example" "${ENV_FILE}"
        echo "  IMPORTANT: edit .env and fill in real secrets before reusing."
    else
        echo "ERROR: no .env or .env.example. Create one first." >&2
        exit 1
    fi
fi

echo "Starting docker-infra (Supabase + Apache AGE + neo4j + LiteLLM)..."
compose up -d --wait
compose ps
