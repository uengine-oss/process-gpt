# =====================================================================
# Process-GPT - Interactive Service Launcher (PowerShell)
# ---------------------------------------------------------------------
#   .\start-all-services.ps1                                # interactive
#   .\start-all-services.ps1 -All                           # everything
#   .\start-all-services.ps1 -InfraOnly                     # just infra+gateway
#   .\start-all-services.ps1 -Services frontend,memento     # explicit list
#   .\start-all-services.ps1 -Last                          # repeat last selection
#   .\start-all-services.ps1 -Preset dev                    # load saved preset
# =====================================================================

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$InfraOnly,
    [string[]]$Services = @(),
    [switch]$Last,
    [string]$Preset,
    [string]$SaveAs
)

$ErrorActionPreference = "Stop"

# Force UTF-8 console I/O so the check-mark glyph renders correctly,
# even on Korean (cp949) Windows.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch { }

Set-Location -Path $PSScriptRoot

$Root = $PSScriptRoot
$EnvFile = Join-Path $Root ".env"
$ComposeFiles = @(
    # First -f MUST be the root docker-compose.yml so that Compose v2 anchors
    # all `./infra/...`, `./gateway/...`, `./services/...` bind paths to the
    # repository root. The remaining -f files layer additional services in.
    "-f", ((Join-Path $Root "docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "infra/docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "compose/docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "gateway/docker-compose.yml") -replace '\\','/')
)
# --------- selection persistence (last-used / named presets) ---------
$StateDir         = Join-Path $Root ".process-gpt-state"
$LastSelectionFile = Join-Path $StateDir "last-selection.txt"
$PresetsDir       = Join-Path $StateDir "presets"

function Ensure-StateDir {
    if (-not (Test-Path $StateDir))   { New-Item -ItemType Directory -Path $StateDir   | Out-Null }
    if (-not (Test-Path $PresetsDir)) { New-Item -ItemType Directory -Path $PresetsDir | Out-Null }
}

function Save-Selection {
    param([string[]]$Names, [string]$Path)
    Ensure-StateDir
    $Names | Set-Content -Path $Path -Encoding UTF8
}

function Load-Selection {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $lines = Get-Content -Path $Path -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { return @() }
    return @($lines | Where-Object { $_ -and $_.Trim() -and -not $_.StartsWith("#") })
}

function Get-PresetNames {
    Ensure-StateDir
    if (-not (Test-Path $PresetsDir)) { return @() }
    return @(Get-ChildItem -Path $PresetsDir -Filter "*.txt" -File -ErrorAction SilentlyContinue |
             ForEach-Object { $_.BaseName })
}

# User-selectable microservices.
# NOTE: infra (db, supabase, neo4j, litellm) and the gateway (nginx)
# are ALWAYS started, so they are NOT listed here.
$Catalog = @(
    @{ Label = "Frontend (Vue 3)";                       Name = "frontend" },
    @{ Label = "Completion (LangChain chat / form gen)"; Name = "completion" },
    @{ Label = "Polling Service";                        Name = "polling-service" },
    @{ Label = "Memento (RAG / vector store)";           Name = "memento" },
    @{ Label = "Glossary Backend";                       Name = "robo-data-glossary-backend" },
    @{ Label = "CrewAI Action (multi-agent tasks)";      Name = "crewai-action" },
    @{ Label = "CrewAI Deep Research";                   Name = "crewai-deep-research" },
    @{ Label = "OpenAI Deep Research";                   Name = "openai-deep-research" },
    @{ Label = "Browser-Use";                            Name = "browser-use" },
    @{ Label = "A2A Orchestrator";                       Name = "a2a-orch" },
    @{ Label = "Agent Router";                           Name = "agent-router" },
    @{ Label = "React Voice Agent";                      Name = "react-voice-agent" },
    @{ Label = "Base Agent (LangChain ReAct)";           Name = "base-agent-langchain-react" },
    @{ Label = "Claude Skills";                          Name = "claude-skills" },
    @{ Label = "Computer-Use";                           Name = "computer-use" },
    @{ Label = "Agent Feedback";                         Name = "agent-feedback" },
    @{ Label = "Analytics (ETL)";                        Name = "process-gpt-analytic" },
    @{ Label = "LangChain ReAct";                        Name = "langchain-react" },
    @{ Label = "BPMN Extractor (PDF -> BPMN)";           Name = "bpmn-extractor" },
    @{ Label = "Office MCP";                             Name = "office-mcp" },
    @{ Label = "Deep Research";                          Name = "deep-research" },
    @{ Label = "DeepAgents";                             Name = "deepagents" },
    @{ Label = "MCP Proxy";                              Name = "mcp-proxy" }
)

# Always-on stack: infra + gateway. Started before any microservice and
# waited on (--wait) so that db is HEALTHY before dependents come up.
$InfraStack = @(
    "litellm-db", "litellm-proxy",
    "db", "kong", "auth", "rest", "realtime", "storage",
    "imgproxy", "meta", "functions", "analytics", "studio",
    "neo4j"
)
$GatewayStack = @("nginx")

function Test-DockerCompose {
    try {
        & docker compose version *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    } catch { }
    return $false
}

function Invoke-Compose {
    # Use the automatic $args variable so callers can pass naked arguments,
    # e.g. `Invoke-Compose up -d @InfraStack` (note the @ splat).
    # --project-directory pins ALL relative paths in every -f file to $Root,
    # otherwise Compose v2 anchors them to the directory of the first -f file
    # and you get surprising bind mounts (e.g. infra/nginx/nginx.conf).
    #
    # PowerShell 5.x mangles native-command arguments that contain Windows
    # path tokens (e.g. it silently drops a backslash, so docker ends up
    # looking for `C:\Users\user\Desktop\.env`). We dodge it ENTIRELY by
    # writing the command into a temp .cmd file and letting cmd.exe parse it.
    $rootFwd    = $Root.Replace('\','/')
    $envFileFwd = $EnvFile.Replace('\','/')
    $quotedArgs = @()
    $quotedArgs += '"--project-directory=' + $rootFwd + '"'
    $quotedArgs += '"--env-file=' + $envFileFwd + '"'
    foreach ($cf in $ComposeFiles) { $quotedArgs += '"' + $cf + '"' }
    foreach ($a in $args)          { $quotedArgs += '"' + $a  + '"' }
    $cmdline = "docker compose " + ($quotedArgs -join ' ')

    $tmpBat = Join-Path $env:TEMP ("process-gpt-compose-" + [Guid]::NewGuid().ToString("N") + ".cmd")
    Set-Content -Path $tmpBat -Value "@echo off`r`n$cmdline`r`nexit /b %ERRORLEVEL%" -Encoding ASCII

    if ($env:COMPOSE_DEBUG) {
        Write-Host "DEBUG tmpBat=$tmpBat" -ForegroundColor Magenta
        Write-Host "DEBUG cmdline: $cmdline" -ForegroundColor Magenta
        Write-Host "DEBUG --- contents of $tmpBat ---" -ForegroundColor Magenta
        Get-Content $tmpBat | ForEach-Object { Write-Host "  $_" -ForegroundColor Magenta }
        Write-Host "DEBUG --- end contents ---" -ForegroundColor Magenta
    }

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & cmd.exe /c $tmpBat 2>&1 | ForEach-Object { Write-Host $_ }
    } finally {
        $ErrorActionPreference = $prev
        if (-not $env:COMPOSE_DEBUG) {
            Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "DEBUG kept $tmpBat for inspection" -ForegroundColor Magenta
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed (code $LASTEXITCODE)" }
}

function Ensure-EnvFile {
    if (-not (Test-Path $EnvFile)) {
        $example = Join-Path $Root ".env.example"
        if (Test-Path $example) {
            Write-Host "  .env not found -> copying from .env.example" -ForegroundColor Yellow
            Copy-Item $example $EnvFile
            Write-Host "  IMPORTANT: edit .env and fill in real secrets before reusing." -ForegroundColor Yellow
        } else {
            throw ".env and .env.example are both missing. Create one first."
        }
    }
}

function Write-Header {
    @"

  ____                                       ____ ____ _____
 |  _ \ _ __ ___   ___ ___  ___ ___    ___  / ___|  _ \_   _|
 | |_) | '__/ _ \ / __/ _ \/ __/ __|  / _ \| |  _| |_) || |
 |  __/| | | (_) | (_|  __/\__ \__ \ | (_) | |_| |  __/ | |
 |_|   |_|  \___/ \___\___||___/___/  \___/ \____|_|    |_|

"@ | Write-Host -ForegroundColor Cyan
}

function Show-CheckboxMenu {
    param(
        [array]$Items,
        [string]$Title = "Select services",
        [hashtable]$PreChecked = @{}
    )

    if (-not $Items -or $Items.Count -eq 0) { return @() }

    $count = $Items.Count
    $selected = New-Object 'bool[]' $count
    for ($i = 0; $i -lt $count; $i++) {
        if ($PreChecked.ContainsKey($Items[$i].Name) -and $PreChecked[$Items[$i].Name]) {
            $selected[$i] = $true
        }
    }
    $cursor = 0
    $confirmed = $false

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host $Title -ForegroundColor Cyan
            Write-Host
            Write-Host "  [Up/Down] move   [Space] toggle   [A] all/none   [Enter] confirm   [Q] cancel" -ForegroundColor DarkGray
            $picked = 0
            foreach ($s in $selected) { if ($s) { $picked++ } }
            Write-Host ("  Selected: {0} / {1}" -f $picked, $count) -ForegroundColor DarkGray
            Write-Host

            for ($i = 0; $i -lt $count; $i++) {
                $check = if ($selected[$i]) { "[" + ([char]0x2713) + "]" } else { "[ ]" }
                $arrow = if ($i -eq $cursor) { ">" } else { " " }
                $line = "  {0} {1} {2,2}) {3}" -f $arrow, $check, ($i + 1), $Items[$i].Label
                if ($i -eq $cursor) {
                    Write-Host $line -ForegroundColor Yellow
                } elseif ($selected[$i]) {
                    Write-Host $line -ForegroundColor Green
                } else {
                    Write-Host $line
                }
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { if ($cursor -gt 0)         { $cursor-- } else { $cursor = $count - 1 } }
                'DownArrow' { if ($cursor -lt $count -1) { $cursor++ } else { $cursor = 0 } }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $count - 1 }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - 5) }
                'PageDown'  { $cursor = [Math]::Min($count - 1, $cursor + 5) }
                'Spacebar'  { $selected[$cursor] = -not $selected[$cursor] }
                'A' {
                    $anyOn = $false
                    foreach ($s in $selected) { if ($s) { $anyOn = $true; break } }
                    for ($i = 0; $i -lt $count; $i++) { $selected[$i] = -not $anyOn }
                }
                'Enter'  { $confirmed = $true }
                'Q'      { $confirmed = $false; break }
                'Escape' { $confirmed = $false; break }
            }

            if ($key.Key -eq 'Enter')  { break }
            if ($key.Key -eq 'Q')      { break }
            if ($key.Key -eq 'Escape') { break }
        }
    } finally {
        [Console]::CursorVisible = $true
    }

    if (-not $confirmed) { return @() }

    $chosen = @()
    for ($i = 0; $i -lt $count; $i++) {
        if ($selected[$i]) { $chosen += $Items[$i].Name }
    }
    return ,$chosen
}

function Start-InfraStack {
    Write-Host
    Write-Host ">>> Starting infra stack (db, supabase, neo4j, litellm) and waiting for HEALTHY..." -ForegroundColor Cyan
    # --wait blocks until every started container is healthy / running.
    # Without this, depends_on: condition: service_healthy can fail because
    # supabase-db needs ~30-60s to finish its init-scripts on first boot.
    Invoke-Compose up -d --wait @InfraStack
}

function Start-Gateway {
    Write-Host
    Write-Host ">>> Starting gateway (nginx)..." -ForegroundColor Cyan
    Invoke-Compose up -d @GatewayStack
}

function Start-Selected {
    param([string[]]$Names)

    # Remember this selection for next time (mode "Last selection").
    if ($Names.Count -gt 0) {
        Save-Selection -Names $Names -Path $LastSelectionFile
    }

    Start-InfraStack
    if ($Names.Count -gt 0) {
        Write-Host
        Write-Host (">>> starting selected services: " + ($Names -join ", ")) -ForegroundColor Cyan
        Invoke-Compose up -d @Names
    }
    Start-Gateway
    Write-Host
    Invoke-Compose ps
    Write-Host
    Write-Host "Tip: Gateway (Nginx)       -> http://localhost:8088" -ForegroundColor Green
    Write-Host "Tip: Supabase Studio       -> http://localhost:`$STUDIO_PORT" -ForegroundColor Green
    Write-Host "Tip: Neo4j Browser         -> http://localhost:`$NEO4J_HTTP_PORT" -ForegroundColor Green
}

# ---- Entry point ----------------------------------------------------
Write-Header

if (-not (Test-DockerCompose)) {
    Write-Error "docker compose not found. Install Docker Desktop or the docker compose plugin."
    exit 1
}

Ensure-EnvFile

if ($All) {
    Write-Host "Mode: ALL services (non-interactive)" -ForegroundColor Cyan
    Invoke-Compose pull
    Start-InfraStack
    Invoke-Compose up -d
    Start-Gateway
    Invoke-Compose ps
    $allNames = $Catalog | ForEach-Object { $_.Name }
    Save-Selection -Names $allNames -Path $LastSelectionFile
    exit 0
}

if ($InfraOnly) {
    Start-InfraStack
    Start-Gateway
    Invoke-Compose ps
    exit 0
}

if ($Services.Count -gt 0) {
    Write-Host ("Mode: explicit services -> " + ($Services -join ", ")) -ForegroundColor Cyan
    if ($SaveAs) {
        Ensure-StateDir
        Save-Selection -Names $Services -Path (Join-Path $PresetsDir ($SaveAs + ".txt"))
        Write-Host ("Saved preset '$SaveAs'.") -ForegroundColor Green
    }
    Start-Selected -Names $Services
    exit 0
}

if ($Last) {
    $names = Load-Selection -Path $LastSelectionFile
    if (-not $names -or $names.Count -eq 0) {
        Write-Error "No previous selection found. Run interactively first."
        exit 1
    }
    Write-Host ("Mode: Last selection -> " + ($names -join ", ")) -ForegroundColor Cyan
    Start-Selected -Names $names
    exit 0
}

if ($Preset) {
    $path = Join-Path $PresetsDir ($Preset + ".txt")
    $names = Load-Selection -Path $path
    if (-not $names -or $names.Count -eq 0) {
        Write-Error "Preset '$Preset' not found or empty. (Looked in $path)"
        exit 1
    }
    Write-Host ("Mode: Preset '$Preset' -> " + ($names -join ", ")) -ForegroundColor Cyan
    Start-Selected -Names $names
    exit 0
}

# ---- interactive mode -----------------------------------------------
$lastNames    = Load-Selection -Path $LastSelectionFile
$presetNames  = Get-PresetNames

$banner = @"

Infra (db / supabase / neo4j / litellm) and the gateway (nginx) are always
started automatically. You only choose which microservices to add.

Choose a start mode:
  1) ALL microservices (everything)
  2) Pick microservices (multi-select checkbox)
  3) Infra + gateway only (no microservices)
"@
Write-Host $banner

if ($lastNames.Count -gt 0) {
    $preview = ($lastNames -join ", ")
    if ($preview.Length -gt 70) { $preview = $preview.Substring(0, 70) + "..." }
    Write-Host ("  4) Repeat last selection [" + $preview + "]")
}
if ($presetNames.Count -gt 0) {
    Write-Host ("  5) Load named preset      [" + ($presetNames -join ", ") + "]")
}
Write-Host "  q) Quit"
Write-Host

$mode = Read-Host "Selection [1/2/3/4/5/q]"
Write-Host

switch -Regex ($mode) {
    '^(1|all|ALL)$' {
        Write-Host ">>> Pulling images..." -ForegroundColor Cyan
        Invoke-Compose pull
        Start-InfraStack
        Write-Host ">>> Starting all microservices..." -ForegroundColor Cyan
        Invoke-Compose up -d
        Start-Gateway
        Invoke-Compose ps
        $allNames = $Catalog | ForEach-Object { $_.Name }
        Save-Selection -Names $allNames -Path $LastSelectionFile
    }
    '^2$' {
        # Pre-check whatever was last picked, for faster re-runs.
        $preChecked = @{}
        foreach ($n in $lastNames) { $preChecked[$n] = $true }
        $names = Show-CheckboxMenu -Items $Catalog -Title "Process-GPT - select microservices to start" -PreChecked $preChecked
        if (-not $names -or $names.Count -eq 0) {
            Write-Host "No services selected. Exiting." -ForegroundColor Yellow
            exit 0
        }
        Write-Host ("Selected: " + ($names -join ", ")) -ForegroundColor Green
        Start-Selected -Names $names

        # Offer to also save it as a named preset.
        $ask = Read-Host "Save this selection as a named preset? (empty to skip)"
        if ($ask) {
            $clean = ($ask -replace '[^a-zA-Z0-9._-]', '_').Trim()
            if ($clean) {
                Save-Selection -Names $names -Path (Join-Path $PresetsDir ($clean + ".txt"))
                Write-Host ("Saved preset '$clean'.") -ForegroundColor Green
            }
        }
    }
    '^3$' {
        Start-InfraStack
        Start-Gateway
        Invoke-Compose ps
    }
    '^4$' {
        if ($lastNames.Count -eq 0) {
            Write-Error "No previous selection on file."
            exit 1
        }
        Write-Host ("Repeating: " + ($lastNames -join ", ")) -ForegroundColor Cyan
        Start-Selected -Names $lastNames
    }
    '^5$' {
        if ($presetNames.Count -eq 0) {
            Write-Error "No saved presets in $PresetsDir."
            exit 1
        }
        Write-Host "Available presets:"
        for ($i = 0; $i -lt $presetNames.Count; $i++) {
            Write-Host ("  {0}) {1}" -f ($i + 1), $presetNames[$i])
        }
        $pick = Read-Host "Preset number"
        if ($pick -notmatch '^\d+$') { Write-Error "Invalid selection."; exit 1 }
        $idx = [int]$pick - 1
        if ($idx -lt 0 -or $idx -ge $presetNames.Count) { Write-Error "Out of range."; exit 1 }
        $chosenPreset = $presetNames[$idx]
        $names = Load-Selection -Path (Join-Path $PresetsDir ($chosenPreset + ".txt"))
        if ($names.Count -eq 0) { Write-Error "Preset '$chosenPreset' is empty."; exit 1 }
        Write-Host ("Loaded preset '$chosenPreset': " + ($names -join ", ")) -ForegroundColor Cyan
        Start-Selected -Names $names
    }
    '^(q|Q)$' {
        Write-Host "Bye."
        exit 0
    }
    default {
        Write-Error "Unknown option: $mode"
        exit 1
    }
}
