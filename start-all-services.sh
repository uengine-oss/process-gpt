#!/usr/bin/env bash
# =====================================================================
# Process-GPT - Interactive Service Launcher (bash)
# ---------------------------------------------------------------------
#   ./start-all-services.sh                       # interactive
#   ./start-all-services.sh all                   # everything
#   ./start-all-services.sh frontend memento ...  # explicit services
#   ./start-all-services.sh --last                # repeat last selection
#   ./start-all-services.sh --preset dev          # load saved preset
# =====================================================================

set -e

cd "$(dirname "$0")"

ROOT="$(pwd)"
ENV_FILE="${ROOT}/.env"
COMPOSE_FILES=(
    # The first -f MUST be the empty root file: Compose v2 anchors every
    # relative bind-mount path in the layered files to the directory of
    # the first -f, so that ./infra/volumes/... resolves at the repo root.
    "-f" "${ROOT}/docker-compose.yml"
    "-f" "${ROOT}/infra/docker-compose.yml"
    "-f" "${ROOT}/compose/docker-compose.yml"
    "-f" "${ROOT}/gateway/docker-compose.yml"
)

STATE_DIR="${ROOT}/.process-gpt-state"
LAST_SELECTION_FILE="${STATE_DIR}/last-selection.txt"
PRESETS_DIR="${STATE_DIR}/presets"

# ---- CLI flags -------------------------------------------------------
USE_LAST=0
PRESET=""
SAVE_AS=""
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--last)   USE_LAST=1; shift ;;
        -p|--preset) PRESET="$2"; shift 2 ;;
        -s|--save-as) SAVE_AS="$2"; shift 2 ;;
        -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

ensure_state_dir() {
    mkdir -p "$STATE_DIR" "$PRESETS_DIR"
}

save_selection() {
    local path="$1"; shift
    ensure_state_dir
    : > "$path"
    for n in "$@"; do echo "$n" >> "$path"; done
}

load_selection() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    grep -E -v '^\s*(#|$)' "$path" || true
}

list_presets() {
    ensure_state_dir
    [[ -d "$PRESETS_DIR" ]] || return 0
    ( cd "$PRESETS_DIR" && ls -1 2>/dev/null | sed -n 's/\.txt$//p' )
}

# ---- Service catalog (display label | compose service name) ----------
# Infra (db, supabase, neo4j, litellm) and the gateway (nginx) are ALWAYS
# started automatically, so they are NOT listed here.
ALL_SERVICES=(
    "Frontend (Vue 3)|frontend"
    "Completion (LangChain chat / form gen)|completion"
    "Polling Service|polling-service"
    "Memento (RAG / vector store)|memento"
    "Instance Classifier (요청 자동분류 · Top List)|instance-classifier"
    "Strategy Board (BSC 전략맵 · KPI 성과수집)|strategy"
    "Glossary Backend|robo-data-glossary-backend"
    "CrewAI Action (multi-agent tasks)|crewai-action"
    "CrewAI Deep Research|crewai-deep-research"
    "OpenAI Deep Research|openai-deep-research"
    "Browser-Use|browser-use"
    "A2A Orchestrator|a2a-orch"
    "Agent Router|agent-router"
    "React Voice Agent|react-voice-agent"
    "Base Agent (LangChain ReAct)|base-agent-langchain-react"
    "Claude Skills|claude-skills"
    "Computer-Use|computer-use"
    "Agent Feedback|agent-feedback"
    "Analytics (ETL)|process-gpt-analytic"
    "LangChain ReAct|langchain-react"
    "BPMN Extractor (PDF -> BPMN)|bpmn-extractor"
    "Office MCP|office-mcp"
    "Deep Research|deep-research"
    "DeepAgents|deepagents"
    "MCP Proxy|mcp-proxy"
)

INFRA_STACK=(
    litellm-db litellm-proxy
    db kong auth rest realtime storage
    imgproxy meta functions analytics studio
    neo4j
)
GATEWAY_STACK=( nginx )

# ---- Helpers ---------------------------------------------------------
have_compose() {
    if docker compose version >/dev/null 2>&1; then return 0; fi
    if docker-compose version >/dev/null 2>&1; then return 0; fi
    return 1
}

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}" "$@"
    else
        docker-compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}" "$@"
    fi
}

ensure_env_file() {
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
}

print_header() {
    cat <<'EOF'

  ____                                       ____ ____ _____
 |  _ \ _ __ ___   ___ ___  ___ ___    ___  / ___|  _ \_   _|
 | |_) | '__/ _ \ / __/ _ \/ __/ __|  / _ \| |  _| |_) || |
 |  __/| | | (_) | (_|  __/\__ \__ \ | (_) | |_| |  __/ | |
 |_|   |_|  \___/ \___\___||___/___/  \___/ \____|_|    |_|

EOF
}

read_key() {
    # Read a single keypress and translate to a logical name.
    local key seq
    IFS= read -rsn1 key 2>/dev/null || return
    case "$key" in
        $'\e')
            # Escape sequence (arrow keys, etc.)
            IFS= read -rsn2 -t 0.005 seq 2>/dev/null || seq=""
            case "$seq" in
                '[A') echo UP ;;
                '[B') echo DOWN ;;
                '[5'|'[5~') echo PGUP ;;
                '[6'|'[6~') echo PGDN ;;
                '[H'|'OH') echo HOME ;;
                '[F'|'OF') echo END ;;
                '') echo ESC ;;
                *) echo OTHER ;;
            esac
            ;;
        '') echo ENTER ;;
        ' ') echo SPACE ;;
        a|A) echo TOGGLE_ALL ;;
        q|Q) echo QUIT ;;
        *) echo OTHER ;;
    esac
}

CHOSEN=()
PRECHECK_NAMES=()  # set this BEFORE calling checkbox_menu to pre-check items

checkbox_menu() {
    # Renders an interactive checkbox menu.
    # Sets the global CHOSEN array with selected compose service names.
    local title="$1"
    local count="${#ALL_SERVICES[@]}"
    local -a sel
    local cursor=0
    local i picked any
    CHOSEN=()
    for ((i=0; i<count; i++)); do
        sel[i]=0
        local svc_name="${ALL_SERVICES[$i]##*|}"
        for pre in "${PRECHECK_NAMES[@]}"; do
            if [[ "$svc_name" == "$pre" ]]; then sel[i]=1; break; fi
        done
    done

    # Hide cursor for cleaner rendering; always restore on exit.
    printf '\e[?25l'
    trap 'printf "\e[?25h"' EXIT INT TERM

    while true; do
        clear
        printf '\e[36m%s\e[0m\n\n' "$title"
        printf '\e[90m  [Up/Down] move   [Space] toggle   [A] all/none   [Enter] confirm   [Q] cancel\e[0m\n'
        picked=0
        for ((i=0; i<count; i++)); do [[ "${sel[i]}" == "1" ]] && picked=$((picked+1)); done
        printf '\e[90m  Selected: %d / %d\e[0m\n\n' "$picked" "$count"

        for ((i=0; i<count; i++)); do
            local label="${ALL_SERVICES[$i]%%|*}"
            local mark="[ ]"
            [[ "${sel[i]}" == "1" ]] && mark=$'[\xe2\x9c\x93]'  # [✓]
            if (( i == cursor )); then
                printf '\e[33m  > %s %2d) %s\e[0m\n' "$mark" $((i+1)) "$label"
            elif [[ "${sel[i]}" == "1" ]]; then
                printf '\e[32m    %s %2d) %s\e[0m\n' "$mark" $((i+1)) "$label"
            else
                printf '    %s %2d) %s\n' "$mark" $((i+1)) "$label"
            fi
        done

        case "$(read_key)" in
            UP)
                if (( cursor > 0 )); then cursor=$((cursor-1)); else cursor=$((count-1)); fi
                ;;
            DOWN)
                if (( cursor < count - 1 )); then cursor=$((cursor+1)); else cursor=0; fi
                ;;
            HOME)  cursor=0 ;;
            END)   cursor=$((count-1)) ;;
            PGUP)  cursor=$(( cursor - 5 )); (( cursor < 0 )) && cursor=0 ;;
            PGDN)  cursor=$(( cursor + 5 )); (( cursor > count - 1 )) && cursor=$((count-1)) ;;
            SPACE)
                if [[ "${sel[cursor]}" == "1" ]]; then sel[cursor]=0; else sel[cursor]=1; fi
                ;;
            TOGGLE_ALL)
                any=0
                for ((i=0; i<count; i++)); do [[ "${sel[i]}" == "1" ]] && any=1; done
                for ((i=0; i<count; i++)); do
                    if (( any )); then sel[i]=0; else sel[i]=1; fi
                done
                ;;
            ENTER)
                for ((i=0; i<count; i++)); do
                    if [[ "${sel[i]}" == "1" ]]; then
                        CHOSEN+=("${ALL_SERVICES[$i]##*|}")
                    fi
                done
                break
                ;;
            QUIT|ESC)
                CHOSEN=()
                break
                ;;
        esac
    done

    printf '\e[?25h'
    trap - EXIT INT TERM
}

start_infra() {
    echo
    echo ">>> Starting infra stack (db, supabase, neo4j, litellm) and waiting for HEALTHY..."
    # --wait blocks until every started container is healthy / running.
    # supabase-db needs ~30-60s on first boot to finish init-scripts.
    compose up -d --wait "${INFRA_STACK[@]}"
}

start_gateway() {
    echo
    echo ">>> Starting gateway (nginx)..."
    compose up -d "${GATEWAY_STACK[@]}"
}

start_services() {
    local services=("$@")

    if [ "${#services[@]}" -gt 0 ]; then
        save_selection "$LAST_SELECTION_FILE" "${services[@]}"
    fi

    start_infra

    if [ "${#services[@]}" -gt 0 ]; then
        echo
        echo ">>> Starting selected services: ${services[*]}"
        compose up -d "${services[@]}"
    fi

    start_gateway

    echo
    echo "Done. Running containers:"
    compose ps
    echo
    echo "Gateway (Nginx): http://localhost:8088"
    echo "Supabase Studio: http://localhost:\${STUDIO_PORT:-3001}"
    echo "Neo4j Browser:   http://localhost:\${NEO4J_HTTP_PORT:-7474}"
}

# ---- Entry point -----------------------------------------------------
print_header

if ! have_compose; then
    echo "ERROR: docker compose not found. Install Docker Desktop or docker compose plugin." >&2
    exit 1
fi

ensure_env_file

# ---- Non-interactive shortcuts --------------------------------------
# --last
if [ "$USE_LAST" -eq 1 ]; then
    mapfile -t names < <(load_selection "$LAST_SELECTION_FILE")
    if [ "${#names[@]}" -eq 0 ]; then
        echo "No previous selection found. Run interactively first." >&2
        exit 1
    fi
    echo "Mode: Last selection -> ${names[*]}"
    start_services "${names[@]}"
    exit 0
fi

# --preset NAME
if [ -n "$PRESET" ]; then
    mapfile -t names < <(load_selection "${PRESETS_DIR}/${PRESET}.txt")
    if [ "${#names[@]}" -eq 0 ]; then
        echo "Preset '$PRESET' not found or empty (${PRESETS_DIR}/${PRESET}.txt)." >&2
        exit 1
    fi
    echo "Mode: Preset '$PRESET' -> ${names[*]}"
    start_services "${names[@]}"
    exit 0
fi

# ./start-all-services.sh all  |  ./start-all-services.sh svc1 svc2 ...
if [ "${#ARGS[@]}" -gt 0 ]; then
    if [ "${ARGS[0]}" = "all" ]; then
        echo "Mode: ALL services (non-interactive)"
        compose pull
        start_infra
        compose up -d
        start_gateway
        compose ps
        exit 0
    fi
    echo "Mode: explicit services from CLI: ${ARGS[*]}"
    if [ -n "$SAVE_AS" ]; then
        save_selection "${PRESETS_DIR}/${SAVE_AS}.txt" "${ARGS[@]}"
        echo "Saved preset '$SAVE_AS'."
    fi
    start_services "${ARGS[@]}"
    exit 0
fi

# ---- Interactive mode -----------------------------------------------
mapfile -t LAST_NAMES < <(load_selection "$LAST_SELECTION_FILE")
mapfile -t PRESET_NAMES < <(list_presets)

cat <<'MENU'

Infra (db / supabase / neo4j / litellm) and the gateway (nginx) are always
started automatically. You only choose which microservices to add.

Choose a start mode:
  1) ALL microservices (everything)
  2) Pick microservices (multi-select checkbox)
  3) Infra + gateway only (no microservices)
MENU

if [ "${#LAST_NAMES[@]}" -gt 0 ]; then
    preview="${LAST_NAMES[*]}"
    [ "${#preview}" -gt 70 ] && preview="${preview:0:70}..."
    echo "  4) Repeat last selection [${preview}]"
fi
if [ "${#PRESET_NAMES[@]}" -gt 0 ]; then
    echo "  5) Load named preset      [${PRESET_NAMES[*]}]"
fi
echo "  q) Quit"
echo

read -r -p "Selection [1/2/3/4/5/q]: " MODE
echo

case "${MODE}" in
    1|all|ALL)
        echo ">>> Pulling images (this may take a while)..."
        compose pull
        start_infra
        echo ">>> Starting all microservices..."
        compose up -d
        start_gateway
        echo
        compose ps
        # Persist "all" as last selection too.
        ALL_NAMES=()
        for entry in "${ALL_SERVICES[@]}"; do ALL_NAMES+=("${entry##*|}"); done
        save_selection "$LAST_SELECTION_FILE" "${ALL_NAMES[@]}"
        ;;
    2)
        PRECHECK_NAMES=("${LAST_NAMES[@]}")
        checkbox_menu "Process-GPT - select microservices to start"
        if [ "${#CHOSEN[@]}" -eq 0 ]; then
            echo "No services selected. Exiting."
            exit 0
        fi
        echo "Selected: ${CHOSEN[*]}"
        start_services "${CHOSEN[@]}"
        read -r -p "Save this selection as a named preset? (empty to skip): " preset_name
        if [ -n "$preset_name" ]; then
            clean="$(echo "$preset_name" | tr -c 'A-Za-z0-9._-' '_' )"
            if [ -n "$clean" ]; then
                save_selection "${PRESETS_DIR}/${clean}.txt" "${CHOSEN[@]}"
                echo "Saved preset '${clean}'."
            fi
        fi
        ;;
    3)
        start_infra
        start_gateway
        compose ps
        ;;
    4)
        if [ "${#LAST_NAMES[@]}" -eq 0 ]; then
            echo "No previous selection on file." >&2
            exit 1
        fi
        echo "Repeating: ${LAST_NAMES[*]}"
        start_services "${LAST_NAMES[@]}"
        ;;
    5)
        if [ "${#PRESET_NAMES[@]}" -eq 0 ]; then
            echo "No saved presets in ${PRESETS_DIR}." >&2
            exit 1
        fi
        echo "Available presets:"
        for i in "${!PRESET_NAMES[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${PRESET_NAMES[$i]}"
        done
        read -r -p "Preset number: " pick
        if ! [[ "$pick" =~ ^[0-9]+$ ]]; then echo "Invalid." >&2; exit 1; fi
        idx=$((pick - 1))
        if (( idx < 0 || idx >= ${#PRESET_NAMES[@]} )); then echo "Out of range." >&2; exit 1; fi
        chosen_preset="${PRESET_NAMES[$idx]}"
        mapfile -t names < <(load_selection "${PRESETS_DIR}/${chosen_preset}.txt")
        if [ "${#names[@]}" -eq 0 ]; then echo "Preset empty." >&2; exit 1; fi
        echo "Loaded preset '${chosen_preset}': ${names[*]}"
        start_services "${names[@]}"
        ;;
    q|Q)
        echo "Bye."
        exit 0
        ;;
    *)
        echo "Unknown option: ${MODE}" >&2
        exit 1
        ;;
esac
