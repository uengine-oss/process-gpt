#!/usr/bin/env bash
# =====================================================================
# Process-GPT - Stop services (bash)
# ---------------------------------------------------------------------
#   ./stop-all-services.sh              # stop everything
#   ./stop-all-services.sh frontend     # stop selected service(s)
#   ./stop-all-services.sh --volumes    # stop everything AND remove volumes
#   ./stop-all-services.sh --wipe       # --volumes + wipe bind-mounts
#                                       #   (infra/volumes/db/data, /storage, /logs)
#                                       #   USE if Postgres is stuck in a restart loop.
# =====================================================================

set -e

cd "$(dirname "$0")"

ROOT="$(pwd)"
ENV_FILE="${ROOT}/.env"
COMPOSE_FILES=(
    "-f" "${ROOT}/docker-compose.yml"
    "-f" "${ROOT}/infra/docker-compose.yml"
    "-f" "${ROOT}/compose/docker-compose.yml"
    "-f" "${ROOT}/gateway/docker-compose.yml"
)

REMOVE_VOLUMES=0
WIPE=0
SERVICES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--volumes) REMOVE_VOLUMES=1; shift ;;
        -w|--wipe)    REMOVE_VOLUMES=1; WIPE=1; shift ;;
        -h|--help)
            sed -n '1,14p' "$0"
            exit 0
            ;;
        *) SERVICES+=("$1"); shift ;;
    esac
done

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}" "$@"
    else
        docker-compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}" "$@"
    fi
}

if [ "${#SERVICES[@]}" -gt 0 ]; then
    echo ">>> Stopping selected services: ${SERVICES[*]}"
    compose stop "${SERVICES[@]}"
    compose rm -f "${SERVICES[@]}"
    exit 0
fi

if [ "${REMOVE_VOLUMES}" -eq 1 ]; then
    echo ">>> Stopping ALL services and removing volumes..."
    compose down -v --remove-orphans
else
    echo ">>> Stopping ALL services..."
    compose down --remove-orphans
fi

if [ "${WIPE}" -eq 1 ]; then
    echo ">>> Wiping bind-mount directories (db data / storage / logs)..."
    for p in "infra/volumes/db/data" "infra/volumes/storage" "infra/volumes/logs"; do
        if [ -d "${ROOT}/${p}" ]; then
            rm -rf "${ROOT}/${p}" && echo "    removed: ${p}" || echo "    FAILED: ${p}"
        else
            echo "    skipped: ${p} (does not exist)"
        fi
    done
    echo "Done. Next boot will re-run all init-scripts on a clean db."
fi
