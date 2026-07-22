#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 사내 루트 인증서 설치 (macOS · 로그인 키체인 = 관리자 권한 불요)
#   더블클릭이 안 되면 터미널에서:  bash install-root.command
#   (내려받은 .command 는 실행권한이 없을 수 있음 → 위처럼 bash 로 실행)
# ─────────────────────────────────────────────────────────────
set -e
CRT_URL="http://swp-iot.lge.com/rootCA.crt"
TMP_CRT="/tmp/swp-iot-rootCA.crt"

echo "사내 루트 인증서를 내려받는 중..."
curl -fsSL "$CRT_URL" -o "$TMP_CRT"

echo "로그인 키체인에 신뢰 인증서로 설치하는 중..."
security add-trusted-cert -d -r trustRoot \
  -k "$HOME/Library/Keychains/login.keychain-db" "$TMP_CRT"
rm -f "$TMP_CRT"

echo ""
echo "[완료] 설치했습니다. 브라우저를 재시작하세요."
echo "      (전체 사용자에 설치하려면: sudo security add-trusted-cert -d -r trustRoot \\"
echo "        -k /Library/Keychains/System.keychain <rootCA.crt>)"
