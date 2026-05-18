#!/usr/bin/env bash
# =====================================================================
# Process-GPT - Submodule Initializer (bash)
# ---------------------------------------------------------------------
# Adds every Process-GPT subproject under services/ as a git submodule.
# Re-running is safe; already-added submodules are skipped.
#
# Usage:
#   ./scripts/init-submodules.sh            # default branch
#   ./scripts/init-submodules.sh -b main    # pin branch
# =====================================================================

set -e

BRANCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch) BRANCH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

cd "$(dirname "$0")/.."

SUBMODULES=(
    "services/execution|https://github.com/uengine-oss/process-gpt-execution.git"
    "services/memento|https://github.com/uengine-oss/process-gpt-memento.git"
    "services/crewai-action|https://github.com/uengine-oss/process-gpt-crewai-action.git"
    "services/crewai-deep-research|https://github.com/uengine-oss/process-gpt-crewai-deep-research.git"
    "services/openai-deep-research|https://github.com/uengine-oss/process-gpt-openai-deep-research.git"
    "services/react-voice-agent|https://github.com/uengine-oss/process-gpt-react-voice-agent.git"
    "services/frontend|https://github.com/uengine-oss/process-gpt-vue3.git"
    "services/completion|https://github.com/uengine-oss/process-gpt-completion.git"
    "services/autonomous-execution|https://github.com/uengine-oss/process-gpt-autonomous-execution.git"
    "services/agents.github.io|https://github.com/uengine-oss/process-gpt-agents.github.io.git"
    "services/generic-agent|https://github.com/uengine-oss/process-gpt-generic-agent.git"
    "services/agent-feedback|https://github.com/uengine-oss/process-gpt-agent-feedback.git"
    "services/mcp-validator|https://github.com/uengine-oss/process-gpt-mcp-validator.git"
    "services/agent-sdk|https://github.com/uengine-oss/process-gpt-agent-sdk.git"
    "services/langchain-react|https://github.com/uengine-oss/process-gpt-langchain-react.git"
    "services/a2a-orch|https://github.com/uengine-oss/process-gpt-a2a-orch.git"
    "services/agent-utils|https://github.com/uengine-oss/process-gpt-agent-utils.git"
    "services/bpmn-extractor|https://github.com/uengine-oss/process-gpt-bpmn-extractor.git"
    "services/computer-use|https://github.com/uengine-oss/process-gpt-computer-use.git"
    "services/claude-skills|https://github.com/uengine-oss/process-gpt-claude-skills.git"
    "services/deep-research|https://github.com/uengine-oss/process-gpt-deep-research.git"
    "services/office-mcp|https://github.com/uengine-oss/process-gpt-office-mcp.git"
    "services/docs|https://github.com/uengine-oss/process-gpt-docs.github.io.git"
)

echo "Process-GPT Submodule Initializer"
echo "Adding ${#SUBMODULES[@]} submodules under services/ ..."
echo

added=0
skipped=0
failed=0

for entry in "${SUBMODULES[@]}"; do
    path="${entry%%|*}"
    url="${entry##*|}"
    name="$(basename "$path")"

    printf "[%s] " "$name"

    if [ -d "$path" ]; then
        echo "already exists -> skip"
        skipped=$((skipped + 1))
        continue
    fi

    if [ -n "$BRANCH" ]; then
        if git submodule add -b "$BRANCH" "$url" "$path" >/dev/null 2>&1; then
            echo "added"
            added=$((added + 1))
        else
            echo "FAILED"
            failed=$((failed + 1))
        fi
    else
        if git submodule add "$url" "$path" >/dev/null 2>&1; then
            echo "added"
            added=$((added + 1))
        else
            echo "FAILED"
            failed=$((failed + 1))
        fi
    fi
done

echo
echo "Summary:"
echo "  Added   : $added"
echo "  Skipped : $skipped"
echo "  Failed  : $failed"
echo

if [ "$failed" -gt 0 ]; then
    echo "Some submodules failed. Check your GitHub access and re-run." >&2
    exit 1
fi

echo "All done. Don't forget to commit .gitmodules + services/ entries."
