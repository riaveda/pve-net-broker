#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# HTTPS(:443 · HTTP/2) 활성화 — **턴키**(PVE 호스트에서 한 번 실행하면 끝).
#
# docs/tls-setup.md §5 의 활성화 절차(인증서 생성 → .42 배치 → tls-enabled → NAT → 배포 → 검증)를
# 사람이 옮겨 적지 않도록 하나로 묶은 것. **멱등** — 이미 된 항목은 아무 일도 하지 않는다.
#
# 왜 스크립트인가: 절차를 문서로만 두면 서버를 옮길 때마다 누군가 한 단계를 빠뜨린다.
#   (레포가 진실원 → 재현은 이 스크립트 하나로.) 비밀(키)은 여전히 git 밖에 남는다.
#
# 사용:
#   ./reverse-proxy/scripts/enable-tls.sh              # 켜기(브라우저 https 유도까지)
#   ./reverse-proxy/scripts/enable-tls.sh --no-redirect  # :443 만 켜고 유도는 나중에
#   ./reverse-proxy/scripts/enable-tls.sh --off        # 끄기(:80 그대로 — 되돌리기)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
NGINX="$REPO/reverse-proxy/nginx"
SSL="$REPO/reverse-proxy/ssl"
HOST_CERT="swp-iot.lge.com"
PROXY_HOST="${PROXY_HOST:-10.10.10.42}"
PROXY_USER="${PROXY_USER:-riaveda}"
REDIRECT=1

for a in "$@"; do
  case "$a" in
    --no-redirect) REDIRECT=0 ;;
    --off)
      echo "[*] HTTPS 끄기 — :443 블록과 브라우저 유도를 내린다(:80 서빙은 그대로)."
      rm -f "$NGINX/tls-enabled/$HOST_CERT.conf" "$NGINX/redirect-enabled/on.conf"
      pnbctl proxy deploy
      echo "[=] 완료 — https 는 꺼졌고 http 는 정상입니다."
      exit 0 ;;
    *) echo "!! 모르는 옵션: $a"; exit 1 ;;
  esac
done

# ── 1) 인증서 (없을 때만 생성 — 루트를 다시 만들면 설치된 신뢰가 깨진다) ──
if [[ -f "$SSL/$HOST_CERT.crt" && -f "$SSL/$HOST_CERT.key" ]]; then
  echo "[=] 인증서 있음: $SSL/$HOST_CERT.crt"
else
  echo "[*] 인증서 생성"
  "$REPO/reverse-proxy/scripts/gen-certs.sh"
fi

# ── 2) .42 배치 (leaf=개인키라 rsync 대상 아님 · rootCA=온보딩 페이지 배포용) ──
# 이미 같은 인증서가 올라가 있으면 아무것도 하지 않는다(멱등) — 공개분(crt)의 해시로 판별한다.
want="$(sha256sum "$SSL/$HOST_CERT.crt" | awk '{print $1}')"
have="$(ssh -o BatchMode=yes "$PROXY_USER@$PROXY_HOST" \
        "sha256sum /etc/nginx/ssl/$HOST_CERT.crt 2>/dev/null | awk '{print \$1}'" 2>/dev/null || true)"
if [[ "$want" == "$have" ]]; then
  echo "[=] .42 에 같은 인증서가 이미 있음 — 배치 생략"
else
  echo "[*] .42 에 인증서 배치"
  # ⚠️ 인증서를 /etc 로 옮기는 것은 **무인화된 sudo 대상이 아니다**(우리 규약상 무인화는 nginx
  #    reload 하나뿐). 그래서 ssh 에 **터미널을 붙여**(-t) .42 계정의 sudo 비밀번호를 그 자리에서
  #    받는다 — 터미널 없이 돌리면 "a terminal is required" 로 멈춘다(실제로 그렇게 멈췄다).
  echo "    → 아래에서 ${PROXY_USER}@${PROXY_HOST} 의 sudo 비밀번호를 물어봅니다(인증서를 /etc/nginx/ssl 로 옮기는 1회 작업)."
  scp -q "$SSL/$HOST_CERT.crt" "$SSL/$HOST_CERT.key" "$SSL/rootCA.crt" "$PROXY_USER@$PROXY_HOST:/tmp/"
  ssh -t "$PROXY_USER@$PROXY_HOST" "sudo mkdir -p /etc/nginx/ssl \
    && sudo mv /tmp/$HOST_CERT.crt /tmp/$HOST_CERT.key /tmp/rootCA.crt /etc/nginx/ssl/ \
    && sudo chown root:root /etc/nginx/ssl/$HOST_CERT.* /etc/nginx/ssl/rootCA.crt \
    && sudo chmod 600 /etc/nginx/ssl/$HOST_CERT.key \
    && sudo chmod 644 /etc/nginx/ssl/$HOST_CERT.crt /etc/nginx/ssl/rootCA.crt"
fi

# ── 3) :443 블록 켜기 (+ 브라우저 유도) ──
cp -f "$NGINX/tls-available/$HOST_CERT.conf" "$NGINX/tls-enabled/"
echo "[=] :443 블록 활성"
if [[ "$REDIRECT" = 1 ]]; then
  cp -f "$NGINX/redirect-available/on.conf" "$NGINX/redirect-enabled/"
  echo "[=] 브라우저 https 유도 활성(루트 CA 미설치 PC 는 안내 페이지로 감)"
fi

# ── 4) 포워딩(443) 보장 — 레포가 진실원이라 이미 들어 있으면 재적용만 한다 ──
grep -q '"443:10.10.10.42:443"' "$REPO/network/nat-rules.sh" \
  || { echo "!! network/nat-rules.sh 에 443 줄이 없습니다 — 레포를 먼저 갱신하세요(git pull)"; exit 1; }
pnbctl nat reload

# ── 5) 배포(검증 포함 — nginx -t 통과해야 reload) ──
pnbctl proxy deploy

# ── 6) 검증 — 자기 인증서로 실제 https 응답을 확인한다(사람 눈 확인 전에 기계가 먼저) ──
echo "[*] 검증"
if curl -sS --cacert "$SSL/rootCA.crt" -o /dev/null -w "   https 응답: %{http_code} · 프로토콜 %{http_version}\n" \
     --resolve "$HOST_CERT:443:$PROXY_HOST" "https://$HOST_CERT/"; then
  echo "[=] HTTPS 활성 완료 — 팀 PC 는 http://swp-iot.lge.com/setup 에서 루트 인증서 1회 설치."
else
  echo "!! https 응답 확인 실패 — .42 에서 'sudo nginx -t' 와 인증서 경로를 확인하세요."
  exit 1
fi
