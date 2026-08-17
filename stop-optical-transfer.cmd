@echo off
setlocal
chcp 65001 >nul

powershell -NoProfile -Command "$listeners = @(Get-NetTCPConnection -LocalPort 4173 -State Listen -ErrorAction SilentlyContinue); if ($listeners.Count -eq 0) { exit 2 }; $ids = @($listeners.OwningProcess | Select-Object -Unique); foreach ($processId in $ids) { Stop-Process -Id $processId -Force -ErrorAction Stop }"

if errorlevel 2 (
  echo UniClipboard optical-transfer service is not running.
  exit /b 0
)
if errorlevel 1 (
  echo [ERROR] Failed to stop the service.
  pause
  exit /b 1
)

echo UniClipboard optical-transfer service stopped.
exit /b 0
