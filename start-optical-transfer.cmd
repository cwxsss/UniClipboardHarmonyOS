@echo off
setlocal
chcp 65001 >nul

set "WEB_ROOT=%~dp0tools\optical-transfer-web"

if not exist "%WEB_ROOT%\package.json" (
  echo [ERROR] Cannot find: %WEB_ROOT%\package.json
  pause
  exit /b 1
)

where npm.cmd >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js/npm is not installed or is not in PATH.
  pause
  exit /b 1
)

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 4173 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo UniClipboard optical-transfer service is already running on port 4173.
  if /I not "%OPTICAL_NO_BROWSER%"=="1" start "" "https://localhost:4173/"
  exit /b 0
)

if not exist "%WEB_ROOT%\node_modules\" (
  echo Installing web dependencies for the first run...
  pushd "%WEB_ROOT%"
  call npm install
  if errorlevel 1 (
    popd
    echo [ERROR] npm install failed.
    pause
    exit /b 1
  )
  popd
)

echo Starting UniClipboard optical-transfer service...
pushd "%WEB_ROOT%"
start "UniClipboard Optical Transfer" /min cmd /c "npm run dev -- --port 4173 1^>vite.out.log 2^>vite.err.log"
popd

powershell -NoProfile -Command "$ready=$false; for($i=0;$i -lt 30;$i++){if(Get-NetTCPConnection -LocalPort 4173 -State Listen -ErrorAction SilentlyContinue){$ready=$true;break};Start-Sleep -Milliseconds 200};if(-not $ready){exit 1}"
if errorlevel 1 (
  echo [ERROR] Service did not start. Check tools\optical-transfer-web\vite.err.log.
  pause
  exit /b 1
)

echo Service started: https://localhost:4173/
if /I not "%OPTICAL_NO_BROWSER%"=="1" start "" "https://localhost:4173/"
exit /b 0
