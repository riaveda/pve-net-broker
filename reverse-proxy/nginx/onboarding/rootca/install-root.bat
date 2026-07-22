@echo off
setlocal
REM ============================================================
REM  Install internal Root CA into the current-user Trusted Root
REM  store (no admin required). Downloads rootCA.crt and installs
REM  it so https://swp-iot.lge.com works without warnings.
REM  (ASCII-only on purpose: Korean text breaks cmd parsing on
REM   Korean Windows. User-facing guide is on /setup/rootca .)
REM ============================================================
set "CRT_URL=http://swp-iot.lge.com/setup/rootca/rootCA.crt"
set "TMP_CRT=%TEMP%\swp-iot-rootCA.crt"

echo Downloading internal Root CA...
certutil -urlcache -split -f "%CRT_URL%" "%TMP_CRT%" >nul 2>&1
if not exist "%TMP_CRT%" (
  echo.
  echo [FAILED] Could not download the certificate.
  echo   Open  http://swp-iot.lge.com/setup/rootca  and install rootCA.crt manually.
  echo.
  pause
  exit /b 1
)

echo Installing into current-user "Trusted Root Certification Authorities"...
certutil -user -addstore Root "%TMP_CRT%"
set "RC=%ERRORLEVEL%"
del "%TMP_CRT%" >nul 2>&1

echo.
if "%RC%"=="0" (
  echo [DONE] Installed. Please fully restart your browser.
  echo   Firefox uses its own store: import rootCA.crt via Firefox settings.
) else (
  echo [FAILED] Install failed ^(code %RC%^). See http://swp-iot.lge.com/setup/rootca for manual steps.
)
echo.
pause
endlocal
