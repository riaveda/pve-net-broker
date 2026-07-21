#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 사내 내부 CA + 와일드카드 서버 인증서 생성기 (준비용 — 생성만, 아무것도 안 켠다)
#
# 목적: 내부 .lge.com 서비스에 "브라우저-신뢰 HTTPS(HTTP/2)" 를 *언제든 켤 수 있게* 미리 준비.
#   - 루트 CA 는 name-constrained(.lge.com 만 서명 가능) — 유출돼도 타 도메인 위장 불가(안전).
#   - 기본 leaf = 와일드카드 *.lge.com → swp-iot.lge.com·pve.lge.com 등 서브도메인 전부 한 장으로 커버.
#   - 루트 인증서(공개)를 각 PC 신뢰저장소에 1회 설치하면 이 CA 발급 인증서가 전부 자동 신뢰됨.
#   - 루트 개인키·leaf 개인키는 git 에 올리지 않는다(ssl/ 는 .gitignore). 키는 "외부 주입 자산".
#
# ※ 이 스크립트는 파일만 생성한다 — nginx :443·NAT 등 *활성화는 안 한다*. 켜는 절차는 docs/tls-setup.md.
#
# 사용:
#   ./gen-certs.sh                 # 루트 CA(없으면 생성) + 와일드카드 *.lge.com leaf
#   ./gen-certs.sh pve.lge.com     # 특정 호스트 leaf 를 따로 원하면(와일드카드로 이미 커버되나 명시 발급도 가능)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HOST="${1:-*.lge.com}"
FNAME="${HOST/#\*./wildcard.}"                 # *.lge.com → wildcard.lge.com (파일명 안전)
DIR="$(cd "$(dirname "$0")/.." && pwd)/ssl"    # reverse-proxy/ssl (gitignored)
CA_KEY="$DIR/rootCA.key"
CA_CRT="$DIR/rootCA.crt"
DAYS_CA=3650    # 루트 CA 10년
DAYS_LEAF=825   # leaf ~2.25년 (clients 안전 상한)

mkdir -p "$DIR"
chmod 700 "$DIR"

# ── 1) 루트 CA (없을 때만 생성) ──────────────────────────────────────────────
# ⚠️ 루트를 재생성하면 이미 설치된 모든 PC 의 신뢰가 깨진다 → 존재하면 절대 재생성하지 않는다.
if [[ -f "$CA_KEY" && -f "$CA_CRT" ]]; then
  echo "[=] 기존 루트 CA 재사용: $CA_CRT  (재생성 안 함 — 설치된 신뢰 보존)"
else
  echo "[*] 루트 CA 생성 (name-constrained .lge.com, ${DAYS_CA}일)"
  openssl genrsa -out "$CA_KEY" 4096
  chmod 600 "$CA_KEY"
  openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days "$DAYS_CA" \
    -out "$CA_CRT" -subj "/CN=Internal LGE Services Root CA/O=Internal" \
    -extensions v3_ca -config <(cat <<'EOF'
[req]
distinguished_name = dn
[dn]
[v3_ca]
basicConstraints     = critical, CA:TRUE
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
# 이 CA 는 .lge.com 하위 도메인 인증서만 서명 가능 — 유출돼도 타 도메인 위장 불가.
nameConstraints      = critical, permitted;DNS:.lge.com
EOF
)
  echo "[+] 루트 생성: $CA_CRT   ← 이걸 각 팀 PC 신뢰저장소에 설치·배포한다"
fi

# ── 2) leaf(서버) 인증서 발급 ────────────────────────────────────────────────
LEAF_KEY="$DIR/$FNAME.key"
LEAF_CSR="$DIR/$FNAME.csr"
LEAF_CRT="$DIR/$FNAME.crt"

echo "[*] leaf 발급: $HOST  (SAN=DNS:$HOST, ${DAYS_LEAF}일)"
openssl genrsa -out "$LEAF_KEY" 2048
chmod 600 "$LEAF_KEY"
openssl req -new -key "$LEAF_KEY" -out "$LEAF_CSR" -subj "/CN=$HOST"
openssl x509 -req -in "$LEAF_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$LEAF_CRT" -days "$DAYS_LEAF" -sha256 \
  -extfile <(cat <<EOF
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName         = DNS:$HOST
EOF
)
rm -f "$LEAF_CSR"
echo "[+] leaf: $LEAF_CRT  +  $LEAF_KEY"

cat <<NEXT

── 지금은 '생성'만 끝. 아무것도 안 켜져 있음(기존 서비스 무영향). ──
활성화가 필요해지면 docs/tls-setup.md 의 "활성화 절차":
  1) 루트 배포(팀 PC 1회):  $CA_CRT
  2) leaf 배치(.42 1회):    $LEAF_CRT + $LEAF_KEY → .42:/etc/nginx/ssl/ (key 600)
  3) :443 켜기:             tls-available/*.conf → tls-enabled/ 로 복사
  4) NAT 443 추가:          nat-rules.sh 에 "443:10.10.10.42:443" → pnbctl nat reload
  5) 반영·검증:             pnbctl proxy deploy → https://swp-iot.lge.com (Protocol=h2)
NEXT
