# Source-run helper: start the completion FastAPI under coverage.py.
# - Loads .env values silently (no transcript echo), overrides DB host/port
#   so the host process reaches the Dockerized infra on 127.0.0.1.
# - Sets ENV=production so completion's main.py skips its own dotenv loader
#   (we already populated the process env ourselves).
# - Listens on 127.0.0.1:8000 (gateway proxies /completion/* to this).
# Run from repo root:
#   pwsh -NoProfile -File openspec/specs/completion_process-definition-search/e2e/scripts/start_completion.ps1
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path "$PSScriptRoot/../../../../..").Path
$Suite = Join-Path $Repo "openspec/specs/completion_process-definition-search/e2e"
$CovDir = Join-Path $Suite "results/backend-coverage"
New-Item -ItemType Directory -Force -Path $CovDir | Out-Null
$env:COVERAGE_FILE = Join-Path $CovDir ".coverage"

# Silently load every KEY=VALUE line from repo .env into the current process
# env, without writing secrets to stdout.
Get-Content (Join-Path $Repo ".env") | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
        $name  = $Matches[1]
        $value = $Matches[2]
        if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
        Set-Item -Path "env:$name" -Value $value
    }
}

# Host-side overrides so the source-run completion reaches Dockerized infra.
$env:ENV = "production"
$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = "54322"
$env:DB_NAME = "postgres"
$env:DB_USER = "supabase_admin"
$env:OPENAI_BASE_URL = "http://127.0.0.1:8899/v1"
$env:OPENAI_API_KEY  = "e2e-mock-key"
$env:LLM_PROXY_URL   = "http://127.0.0.1:8899/v1"
$env:LLM_PROXY_API_KEY = "e2e-mock-key"
$env:LLM_EMBEDDING_MODEL = "text-embedding-3-small"
$env:SUPABASE_URL = "http://127.0.0.1:54321"
# database.py reads SUPABASE_KEY; .env exposes the service-role JWT under
# SERVICE_ROLE_KEY (Supabase self-hosting convention). Mirror it so the
# Supabase client can be initialized.
if (-not $env:SUPABASE_KEY) {
    if ($env:SERVICE_ROLE_KEY) { $env:SUPABASE_KEY = $env:SERVICE_ROLE_KEY }
    elseif ($env:SUPABASE_SERVICE_ROLE_KEY) { $env:SUPABASE_KEY = $env:SUPABASE_SERVICE_ROLE_KEY }
}

Set-Location (Join-Path $Repo "services/completion")
# Use the spec-local wrapper so coverage.save() can be triggered over HTTP
# before the PowerShell harness kills the python process (Windows
# TerminateProcess skips atexit handlers).
$wrapper = Join-Path $Repo "openspec/specs/completion_process-definition-search/e2e/scripts/coverage_wrapper.py"
python -X utf8 $wrapper
