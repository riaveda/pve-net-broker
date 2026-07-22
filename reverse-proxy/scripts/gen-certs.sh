#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 사내 내부 CA + 서버(leaf) 인증서 생성기 (준비용 — 생성만, 아무것도 안 켠다)
#
# 목적: swp-iot.lge.com 서비스에 "브라우저-신뢰 HTTPS(HTTP/2)" 를 *언제든 켤 수 있게* 미리 준비.
#   - 루트 CA 는 name-constrained(swp-iot.lge.com 및 그 하위만 서명 가능) — 유출돼도 타 도메인 위장 불가(안전).
#     (전 서비스가 swp-iot.lge.com 하나라 이보다 넓힐 이유 없음. 좁을수록 유출 시 blast radius 작음.)
#   - 기본 leaf = swp-iot.lge.com (단일 호스트). TLS 는 경로/포트 무관·호스트명만 매칭하므로,
#     이 한 장이 리버스프록시 밑 전 경로(/gitlab·/build·/agent…) + 같은 호스트의 다른 포트
#     (예: PVE 관리 UI swp-iot.lge.com:8006)까지 전부 커버한다. → 와일드카드 불필요.
#   - 루트 인증서(공개)를 각 PC 신뢰저장소에 1회 설치하면 이 CA 발급 인증서가 자동 신뢰됨.
#   - 루트 개인키·leaf 개인키는 git 에 올리지 않는다(ssl/ 는 .gitignore). 키는 "외부 주입 자산".
#
# ※ 이 스크립트는 파일만 생성한다 — nginx :443·NAT 등 *활성화는 안 한다*. 켜는 절차는 docs/tls-setup.md.
#
# 사용:
#   ./gen-certs.sh                 # 루트 CA(없으면 생성) + swp-iot.lge.com leaf
#   ./gen-certs.sh other.lge.com   # 다른 .lge.com 호스트가 별도로 필요하면 그 leaf 발급
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HOST="${1:-swp-iot.lge.com}"
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
# 이 CA 는 swp-iot.lge.com(및 그 하위)만 서명 가능 — 유출돼도 그 외 도메인 위장 불가.
# 전 서비스가 swp-iot.lge.com 하나라 이보다 넓힐 이유 없음(좁을수록 유출 blast radius 작음).
nameConstraints      = critical, permitted;DNS:swp-iot.lge.com
EOF
)
  echo "[+] 루트 생성: $CA_CRT   ← 이걸 각 팀 PC 신뢰저장소에 설치·배포한다"
fi

# ── 2) leaf(서버) 인증서 발급 ────────────────────────────────────────────────
LEAF_KEY="$DIR/$HOST.key"
LEAF_CSR="$DIR/$HOST.csr"
LEAF_CRT="$DIR/$HOST.crt"

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
