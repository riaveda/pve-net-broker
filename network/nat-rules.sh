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

# 대표 주소 — **vmbr0 에 실제로 붙어 있는 주소를 읽는다**(적어 둔 값은 마지막 폴백).
# ⚠️ 아래 포워딩이 **전부** 이 값에 걸린다(외부·hairpin 양쪽). 예전엔 hairpin 만 썼기에 값이
#   틀려도 "밖에선 되는데 안에서만 안 되는" 정도였지만, 이제 틀리면 **밖에서도 안 들어온다.**
#   그래서 손으로 적은 값을 진실원으로 삼지 않는다 — 사내 IP 가 바뀌는 날 전부 조용히 끊긴다.
HOST_IP="$(ip -4 -o addr show dev vmbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
HOST_IP="${HOST_IP:-10.231.184.162}"
SUBNET="10.10.10.0/24"

PRE="PVE-NET-BROKER-STATIC"        # nat PREROUTING  관리 체인 (DNAT)
POST="PVE-NET-BROKER-STATIC-POST"  # nat POSTROUTING 관리 체인 (MASQUERADE)

# ── 서비스 포워딩 정의: "외부포트:VM_IP:내부포트" ──
SERVICES=(
    "80:10.10.10.42:80"   # Reverse Proxy (HTTP)
    "443:10.10.10.42:443" # Reverse Proxy (HTTPS/HTTP2) — tls-enabled 활성화와 함께 사용
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
#
# ⚠️ **양쪽 다 `-d "$HOST_IP"` 를 붙인다 — 포워딩 대상은 "우리 대표 주소로 온 것" 뿐이다.**
#   목적지 조건이 없으면 그 인터페이스로 들어온 **모든** 같은 포트 트래픽이 끌려간다. 지금은
#   vmbr0 로 오는 것이 사실상 우리 주소 앞이라 무해하지만, PVE 가 다른 대역의 경로가 되는 순간
#   그 대역의 443·22XX 가 통째로 우리 VM 으로 빨려 들어간다(눈치채기 어렵고 되돌리기도 늦다).
#   예전엔 내부(vmbr1) 줄에만 조건이 있어 **의도인지 누락인지 코드만 봐선 알 수 없었다** —
#   두 줄을 같은 모양으로 맞춰 규칙이 스스로를 설명하게 한다.
for svc in "${SERVICES[@]}"; do
    IFS=':' read -r EXT_PORT VM_IP INT_PORT <<< "$svc"
    iptables -t nat -A "$PRE"  -i vmbr0 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat -A "$PRE"  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat -A "$POST" -s "$SUBNET" -d "$VM_IP" -p tcp --dport "$INT_PORT" -j MASQUERADE
done

# ── SSH 포워딩: 포트 22XX → 10.10.10.XX:22 (외부 vmbr0 + 내부 hairpin vmbr1) ──
# 내부 VM(vmbr1)에서 공용 주소(HOST_IP)로 22XX 접속 시에도 도달하도록 SERVICES 루프와
# 동일하게 hairpin DNAT + return MASQUERADE 를 함께 건다. (예: .6 계정에서 gitlab .36:22 clone)
for i in $(seq 2 50); do
    EXT_PORT=$((2200 + i))
    VM_IP="10.10.10.$i"
    iptables -t nat -A "$PRE"  -i vmbr0 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat -A "$PRE"  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat -A "$POST" -s "$SUBNET" -d "$VM_IP" -p tcp --dport 22 -j MASQUERADE
done
