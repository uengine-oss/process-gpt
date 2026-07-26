#!/usr/bin/env bash
# docker-infra 스택 종료. 데이터(볼륨)는 유지된다 — 완전 초기화하려면
# `./down.sh -v`로 named volume까지 지울 것 (db/age-postgres/neo4j 데이터 삭제됨).
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

compose down "$@"
