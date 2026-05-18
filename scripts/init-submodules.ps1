# =====================================================================
# Process-GPT - Submodule Initializer (PowerShell)
# ---------------------------------------------------------------------
# Adds every Process-GPT subproject under services/ as a git submodule.
# Re-running is safe; already-added submodules are skipped.
#
# Usage:
#   .\scripts\init-submodules.ps1                # default: master/main
#   .\scripts\init-submodules.ps1 -Branch main   # pin branch
# =====================================================================

param(
    [string]$Branch = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$submodules = @(
    @{ Path = "services/execution";             Url = "https://github.com/uengine-oss/process-gpt-execution.git" },
    @{ Path = "services/memento";               Url = "https://github.com/uengine-oss/process-gpt-memento.git" },
    @{ Path = "services/crewai-action";         Url = "https://github.com/uengine-oss/process-gpt-crewai-action.git" },
    @{ Path = "services/crewai-deep-research";  Url = "https://github.com/uengine-oss/process-gpt-crewai-deep-research.git" },
    @{ Path = "services/openai-deep-research";  Url = "https://github.com/uengine-oss/process-gpt-openai-deep-research.git" },
    @{ Path = "services/react-voice-agent";     Url = "https://github.com/uengine-oss/process-gpt-react-voice-agent.git" },
    @{ Path = "services/frontend";              Url = "https://github.com/uengine-oss/process-gpt-vue3.git" },
    @{ Path = "services/completion";            Url = "https://github.com/uengine-oss/process-gpt-completion.git" },
    @{ Path = "services/autonomous-execution";  Url = "https://github.com/uengine-oss/process-gpt-autonomous-execution.git" },
    @{ Path = "services/agents.github.io";      Url = "https://github.com/uengine-oss/process-gpt-agents.github.io.git" },
    @{ Path = "services/generic-agent";         Url = "https://github.com/uengine-oss/process-gpt-generic-agent.git" },
    @{ Path = "services/agent-feedback";        Url = "https://github.com/uengine-oss/process-gpt-agent-feedback.git" },
    @{ Path = "services/mcp-validator";         Url = "https://github.com/uengine-oss/process-gpt-mcp-validator.git" },
    @{ Path = "services/agent-sdk";             Url = "https://github.com/uengine-oss/process-gpt-agent-sdk.git" },
    @{ Path = "services/langchain-react";       Url = "https://github.com/uengine-oss/process-gpt-langchain-react.git" },
    @{ Path = "services/a2a-orch";              Url = "https://github.com/uengine-oss/process-gpt-a2a-orch.git" },
    @{ Path = "services/agent-utils";           Url = "https://github.com/uengine-oss/process-gpt-agent-utils.git" },
    @{ Path = "services/bpmn-extractor";        Url = "https://github.com/uengine-oss/process-gpt-bpmn-extractor.git" },
    @{ Path = "services/computer-use";          Url = "https://github.com/uengine-oss/process-gpt-computer-use.git" },
    @{ Path = "services/claude-skills";         Url = "https://github.com/uengine-oss/process-gpt-claude-skills.git" },
    @{ Path = "services/deep-research";         Url = "https://github.com/uengine-oss/process-gpt-deep-research.git" },
    @{ Path = "services/office-mcp";            Url = "https://github.com/uengine-oss/process-gpt-office-mcp.git" },
    @{ Path = "services/docs";                  Url = "https://github.com/uengine-oss/process-gpt-docs.github.io.git" }
)

Write-Host "Process-GPT Submodule Initializer" -ForegroundColor Cyan
Write-Host "Adding $($submodules.Count) submodules under services/ ..." -ForegroundColor Cyan
Write-Host ""

$added = 0
$skipped = 0
$failed = 0

foreach ($s in $submodules) {
    $path = $s.Path
    $url = $s.Url
    $name = Split-Path -Leaf $path

    Write-Host "[$name] " -NoNewline -ForegroundColor Yellow

    if (Test-Path -Path $path) {
        Write-Host "already exists -> skip" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    $args = @("submodule", "add")
    if ($Branch) { $args += @("-b", $Branch) }
    $args += @($url, $path)

    try {
        & git @args
        if ($LASTEXITCODE -ne 0) { throw "git submodule add failed (code $LASTEXITCODE)" }
        Write-Host "added" -ForegroundColor Green
        $added++
    } catch {
        Write-Host "FAILED -> $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Added   : $added"
Write-Host "  Skipped : $skipped"
Write-Host "  Failed  : $failed"
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Some submodules failed. Check your GitHub access and re-run." -ForegroundColor Yellow
    exit 1
}

Write-Host "All done. Don't forget to commit .gitmodules + services/ entries." -ForegroundColor Green
