@echo off
chcp 65001 >nul
setlocal
REM ─────────────────────────────────────────────────────────────
REM 사내 루트 인증서 원클릭 설치 (현재 사용자 · 관리자 권한 불요)
REM   이 파일을 내려받아 더블클릭하면, 루트 인증서를 자동으로 받아
REM   "신뢰할 수 있는 루트 인증 기관"(현재 사용자)에 설치한다.
REM   설치 후 http://swp-iot.lge.com 서비스가 경고 없이 https 로 열린다.
REM ─────────────────────────────────────────────────────────────
set "CRT_URL=http://swp-iot.lge.com/setup/rootca/rootCA.crt"
set "TMP_CRT=%TEMP%\swp-iot-rootCA.crt"

echo 사내 루트 인증서를 내려받는 중...
certutil -urlcache -split -f "%CRT_URL%" "%TMP_CRT%" >nul 2>&1
if not exist "%TMP_CRT%" (
  echo.
  echo [실패] 인증서를 내려받지 못했습니다.
  echo        http://swp-iot.lge.com/setup/rootca 에서 rootCA.crt 를 직접 받아
  echo        더블클릭 - 인증서 설치 - 현재 사용자 - "신뢰할 수 있는 루트 인증 기관" 으로 설치하세요.
  echo.
  pause
  exit /b 1
)

echo 신뢰 저장소에 설치하는 중 (현재 사용자)...
certutil -user -addstore Root "%TMP_CRT%"
set "RC=%ERRORLEVEL%"
del "%TMP_CRT%" >nul 2>&1

echo.
if "%RC%"=="0" (
  echo [완료] 설치했습니다. 브라우저를 완전히 종료 후 다시 여세요.
  echo        ※ Firefox 사용자는 Firefox 설정 - 개인정보 및 보안 - 인증서 보기 - 인증 기관
  echo          에서 rootCA.crt 를 별도로 가져와야 합니다 ^(Firefox 는 자체 저장소 사용^).
) else (
  echo [실패] 설치에 실패했습니다 ^(코드 %RC%^). http://swp-iot.lge.com/setup 의 수동 안내를 따르세요.
)
echo.
pause
endlocal
