#!/bin/bash
# PVE Net Broker — Static NAT rules (chain-based, convergent)
#
# 관리 규칙을 전용 nat 체인에 담고, apply 마다 그 체인을 flush 후 재적재한다.
#   PVE-NET-BROKER-STATIC       ← nat PREROUTING DNAT (서비스 포워딩 + SSH 22XX)
#   PVE-NET-BROKER-STATIC-POST  ← nat POSTROUTING MASQUERADE (기본 + 서비스/SSH return)
# base 체인(PREROUTING/POSTROUTING)엔 이 체인으로의 jump 만 1개씩 둔다.
#
# 왜: append/delete 개별 관리(옛 방식)는 IP 변경 시 옛 룰을 못 지우고(-D 파라미터 불일치)
#     reload 마다 중복이 쌓여 "라이브 ≠ 레포" 로 드리프트했다(고아·중복). 전용 체인을
#     flush→재적재하면 apply 결과가 항상 레포와 동일하게 수렴한다(idempotent). 고아·중복
#     원천 차단. 동적 USB 예약(PVE-NET-BROKER / -POST, src/iptables_manager.py)과 완전 분리.
#
# Called by:
#   - /etc/network/interfaces (post-up: `nat-rules.sh up`, post-down: `nat-rules.sh down`)
#   - pnbctl nat reload         (→ `nat-rules.sh up`, 수렴 재적재)
#
# DO NOT EDIT /etc/network/nat-rules.sh directly (symlink → repo).
# Edit this file, commit/push, then run: pnbctl nat reload

set -u
ACTION="${1:-up}"

HOST_IP="10.231.184.162"
SUBNET="10.10.10.0/24"

PRE="PVE-NET-BROKER-STATIC"        # nat PREROUTING  관리 체인 (DNAT)
POST="PVE-NET-BROKER-STATIC-POST"  # nat POSTROUTING 관리 체인 (MASQUERADE)

# ── 서비스 포워딩 정의: "외부포트:VM_IP:내부포트" ──
SERVICES=(
    "80:10.10.10.42:80"   # Reverse Proxy (HTTP)
    "443:10.10.10.42:443" # Reverse Proxy (HTTPS/HTTP2)
    "3500:10.10.10.5:3500"    # ReferencePlatform
    "3501:10.10.10.5:3501"
    "3502:10.10.10.5:3502"
    "3503:10.10.10.5:3503"
    "3504:10.10.10.5:3504"
    "3505:10.10.10.5:3505"
    "3506:10.10.10.5:3506"
    "3507:10.10.10.5:3507"
    "3508:10.10.10.5:3508"
    "3509:10.10.10.5:3509"
    "3510:10.10.10.5:3510"
    "3511:10.10.10.5:3511"
    "3512:10.10.10.5:3512"
    "3513:10.10.10.5:3513"
    "3514:10.10.10.5:3514"
    "3515:10.10.10.5:3515"
    "4000:10.10.10.40:4000"   # MultiBizpack
    "4001:10.10.10.40:4001"   # MultiBizpack (dev)
    "4050:10.10.10.41:4050"   # Build-Platform
    "4051:10.10.10.41:4051"   # Build-Platform (dev)
    "5000:10.10.10.6:5000"    # Agent-Platform
    "5001:10.10.10.6:5001"    # Agent-Platform (dev)
    "5003:10.10.10.6:5003"    # Agent-Platform (langfuse)
    "5004:10.10.10.6:5004"    # Agent-Platform (langfuse-dev)
    "5050:10.10.10.36:5050"   # GitLab
)

# ── down: base 에서 jump 제거 → 관리 체인 flush → 삭제 (없어도 무해) ──
if [ "$ACTION" = "down" ]; then
    iptables -t nat -D PREROUTING  -j "$PRE"  2>/dev/null || true
    iptables -t nat -D POSTROUTING -j "$POST" 2>/dev/null || true
    iptables -t nat -F "$PRE"  2>/dev/null || true
    iptables -t nat -F "$POST" 2>/dev/null || true
    iptables -t nat -X "$PRE"  2>/dev/null || true
    iptables -t nat -X "$POST" 2>/dev/null || true
    exit 0
fi

# ── up / reapply (수렴) ──
echo 1 > /proc/sys/net/ipv4/ip_forward

# 관리 체인 보장 + base 에서 jump 정확히 1개씩
iptables -t nat -N "$PRE"  2>/dev/null || true
iptables -t nat -N "$POST" 2>/dev/null || true
iptables -t nat -C PREROUTING  -j "$PRE"  2>/dev/null || iptables -t nat -A PREROUTING  -j "$PRE"
iptables -t nat -C POSTROUTING -j "$POST" 2>/dev/null || iptables -t nat -A POSTROUTING -j "$POST"

# 관리 체인 비우기 → 고아·중복 원천 제거 (여기부터 재적재 = 레포와 동일 상태로 수렴)
iptables -t nat -F "$PRE"
iptables -t nat -F "$POST"

# ── 기본 NAT (VM → 인터넷) ──
iptables -t nat -A "$POST" -s "$SUBNET" -o vmbr0 -j MASQUERADE

# ── 서비스 포워딩 (외부 vmbr0 + 내부 hairpin vmbr1 + return MASQUERADE) ──
for svc in "${SERVICES[@]}"; do
    IFS=':' read -r EXT_PORT VM_IP INT_PORT <<< "$svc"
    iptables -t nat -A "$PRE"  -i vmbr0 -p tcp --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat -A "$PRE"  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat -A "$POST" -s "$SUBNET" -d "$VM_IP" -p tcp --dport "$INT_PORT" -j MASQUERADE
done

# ── SSH 포워딩: 포트 22XX → 10.10.10.XX:22 (외부 vmbr0 + 내부 hairpin vmbr1) ──
# 내부 VM(vmbr1)에서 공용 주소(HOST_IP)로 22XX 접속 시에도 도달하도록 SERVICES 루프와
# 동일하게 hairpin DNAT + return MASQUERADE 를 함께 건다. (예: .6 계정에서 gitlab .36:22 clone)
for i in $(seq 2 50); do
    EXT_PORT=$((2200 + i))
    VM_IP="10.10.10.$i"
    iptables -t nat -A "$PRE"  -i vmbr0 -p tcp --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat -A "$PRE"  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat -A "$POST" -s "$SUBNET" -d "$VM_IP" -p tcp --dport 22 -j MASQUERADE
done
