#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 사내 내부 CA + 서버(leaf) 인증서 생성기
#
# 목적: swp-iot.lge.com 등 내부 .lge.com 서비스에 "브라우저-신뢰 HTTPS(HTTP/2)" 를 제공.
#   - 루트 CA 는 name-constrained(.lge.com 만 서명 가능) — 유출돼도 타 도메인 위장 불가(안전).
#   - 루트 인증서(공개)를 각 PC 신뢰저장소에 1회 설치하면, 이 CA 가 발급한 모든 leaf 가 자동 신뢰됨.
#   - 루트 개인키·leaf 개인키는 git 에 올리지 않는다(ssl/ 는 .gitignore). 키는 "외부 주입 자산".
#
# 사용:
#   ./gen-certs.sh                 # 루트 CA(없으면 생성) + swp-iot.lge.com leaf 발급
#   ./gen-certs.sh pve.lge.com     # 같은 루트로 다른 호스트 leaf 발급(예: PVE 관리 페이지)
#
# 전체 배포 절차·인수인계 문서: reverse-proxy/docs/tls-setup.md
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HOST="${1:-swp-iot.lge.com}"
DIR="$(cd "$(dirname "$0")/.." && pwd)/ssl"   # reverse-proxy/ssl (gitignored)
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
LEAF_KEY="$DIR/$HOST.key"
LEAF_CSR="$DIR/$HOST.csr"
LEAF_CRT="$DIR/$HOST.crt"

echo "[*] leaf 발급: $HOST (${DAYS_LEAF}일)"
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

다음 단계 (상세: reverse-proxy/docs/tls-setup.md):
  1) 루트 배포(팀 PC 1회):  $CA_CRT  → 각 PC 신뢰 루트에 설치
  2) leaf 배치(.42 1회):    $LEAF_CRT + $LEAF_KEY  → .42:/etc/nginx/ssl/  (sudo, key 는 600)
  3) HTTPS 활성화:          reverse-proxy/nginx/tls-available/$HOST.conf → tls-enabled/ 로 복사
  4) 반영:                  git pull && pnbctl nat reload && pnbctl proxy deploy
  5) 검증:                  https://$HOST 접속 → 경고 없음 + 개발자도구 Network Protocol=h2
NEXT
