# Source-run helper: produce a sourcemapped Vite build and serve via
# `vite preview`. Replaces the cold-start-prone `vite dev` with a static
# server so Playwright's login flow doesn't trip Vue/Vuetify Suspense
# fallbacks. See openspec/e2e/memories/vite-dev-cold-start-login-suspense.md.
#
# Run from repo root (build is idempotent; skip with $env:E2E_SKIP_BUILD=1):
#   powershell -NoProfile -File openspec/specs/completion_process-definition-search/e2e/scripts/build_and_serve_frontend.ps1
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path "$PSScriptRoot/../../../../..").Path
Set-Location (Join-Path $Repo "services/frontend")

# vite.config.ts already sets build.sourcemap=true, so no override needed.
$env:VITE_GS_MODE = "false"
if (-not $env:E2E_SKIP_BUILD) {
    $env:NODE_OPTIONS = "--max-old-space-size=8192"
    npx vite build --minify=false
}

# `vite preview` serves the static dist/ folder. No on-demand compile,
# no Suspense skeleton — the login form mounts as soon as the bundle is
# parsed.
npx vite preview --host 127.0.0.1 --port 8081 --strictPort
