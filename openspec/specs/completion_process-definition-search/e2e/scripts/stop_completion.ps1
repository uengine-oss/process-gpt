# Flush coverage and stop the source-run completion process gracefully.
# POSTs to the wrapper's /save endpoint (coverage_wrapper.py listens on
# 127.0.0.1:8001), then frees the :8000 listener.
$ErrorActionPreference = 'Continue'
try {
    Invoke-WebRequest -UseBasicParsing -Method POST -Uri http://127.0.0.1:8001/save -TimeoutSec 10 | Out-Null
    Write-Output "coverage saved"
} catch {
    Write-Output "coverage save endpoint unreachable: $($_.Exception.Message)"
}
Start-Sleep -Milliseconds 500
$conns = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
}
Write-Output "completion stopped"
