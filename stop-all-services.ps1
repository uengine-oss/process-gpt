# =====================================================================
# Process-GPT - Stop services (PowerShell)
# ---------------------------------------------------------------------
#   .\stop-all-services.ps1                       # stop everything
#   .\stop-all-services.ps1 -Services frontend    # stop selected
#   .\stop-all-services.ps1 -Volumes              # also remove named volumes
#   .\stop-all-services.ps1 -Wipe                 # -Volumes + wipe bind-mounts
#                                                 #   (infra/volumes/db/data, /storage, /logs)
#                                                 #   USE THIS if Postgres gets stuck in a
#                                                 #   restart loop with messages like
#                                                 #   "Database directory appears to contain a database;
#                                                 #    Skipping initialization" + "could not open directory".
# =====================================================================

[CmdletBinding()]
param(
    [string[]]$Services = @(),
    [switch]$Volumes,
    [switch]$Wipe
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$Root = $PSScriptRoot
$EnvFile = Join-Path $Root ".env"
$ComposeFiles = @(
    "-f", ((Join-Path $Root "docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "infra/docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "compose/docker-compose.yml") -replace '\\','/'),
    "-f", ((Join-Path $Root "gateway/docker-compose.yml") -replace '\\','/')
)

function Invoke-Compose {
    # Hand-off via a temp .cmd file so cmd.exe parses the command line and
    # PowerShell 5.x cannot mangle our path arguments.
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

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & cmd.exe /c $tmpBat 2>&1 | ForEach-Object { Write-Host $_ }
    } finally {
        $ErrorActionPreference = $prev
        Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed (code $LASTEXITCODE)" }
}

if ($Services.Count -gt 0) {
    Write-Host (">>> Stopping selected services: " + ($Services -join ", ")) -ForegroundColor Cyan
    Invoke-Compose stop @Services
    Invoke-Compose rm -f @Services
    exit 0
}

if ($Wipe -or $Volumes) {
    Write-Host ">>> Stopping ALL services and removing volumes..." -ForegroundColor Yellow
    Invoke-Compose down -v --remove-orphans
} else {
    Write-Host ">>> Stopping ALL services..." -ForegroundColor Cyan
    Invoke-Compose down --remove-orphans
}

if ($Wipe) {
    Write-Host ">>> Wiping bind-mount directories (db data / storage / logs)..." -ForegroundColor Yellow
    foreach ($p in @("infra/volumes/db/data", "infra/volumes/storage", "infra/volumes/logs")) {
        $full = Join-Path $Root $p
        if (Test-Path $full) {
            try {
                Remove-Item -Recurse -Force $full -ErrorAction Stop
                Write-Host "    removed: $p" -ForegroundColor DarkGreen
            } catch {
                Write-Host "    FAILED to remove $p -> $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "    skipped: $p (does not exist)" -ForegroundColor DarkGray
        }
    }
    Write-Host "Done. Next boot will re-run all init-scripts on a clean db." -ForegroundColor Green
}
