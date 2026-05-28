# Source-run helper: start the Vite dev server with sourcemaps on :8081.
# Run from repo root:
#   pwsh -NoProfile -File openspec/specs/completion_process-definition-search/e2e/scripts/start_frontend.ps1
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path "$PSScriptRoot/../../../../..").Path
Set-Location (Join-Path $Repo "services/frontend")

# Vite's existing config already has build.sourcemap = true; dev server
# emits sourcemaps automatically.
$env:VITE_GS_MODE = "false"
npx vite --host 127.0.0.1 --port 8081 --strictPort
