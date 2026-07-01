#!/bin/bash
# PVE Net Broker — Static NAT rules
# Called by: /etc/network/interfaces (vmbr1 post-up/post-down)
# Managed by: git repo /opt/pve-net-broker
#
# DO NOT EDIT /etc/network/nat-rules.sh directly.
# Edit this file and run: make deploy

ACTION=$1  # up or down

if [ "$ACTION" = "up" ]; then
    OP="-A"; echo 1 > /proc/sys/net/ipv4/ip_forward
else
    OP="-D"
fi

HOST_IP="10.231.184.162"
SUBNET="10.10.10.0/24"

# ── 기본 NAT (VM → 인터넷) ──
iptables -t nat $OP POSTROUTING -s "$SUBNET" -o vmbr0 -j MASQUERADE

# ── 서비스 포워딩 정의: "외부포트:VM_IP:내부포트" ──
# 수정후 $ ifreload -a
SERVICES=(
    "80:10.10.10.42:80" # Reverse Proxy
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

for svc in "${SERVICES[@]}"; do
    IFS=':' read -r EXT_PORT VM_IP INT_PORT <<< "$svc"
    iptables -t nat $OP PREROUTING  -i vmbr0 -p tcp --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat $OP PREROUTING  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:$INT_PORT"
    iptables -t nat $OP POSTROUTING -s "$SUBNET" -d "$VM_IP" -p tcp --dport "$INT_PORT" -j MASQUERADE
done

# ── SSH 포워딩: 포트 22XX → 10.10.10.XX:22 (외부 vmbr0 + 내부 hairpin vmbr1) ──
# 내부 VM(vmbr1)에서 공용 주소(HOST_IP)로 22XX 접속 시에도 도달하도록 SERVICES 루프와
# 동일하게 hairpin DNAT + return MASQUERADE 를 함께 건다. (예: .6 계정에서 gitlab .36:22 clone)
for i in $(seq 2 50); do
    EXT_PORT=$((2200 + i))
    VM_IP="10.10.10.$i"
    iptables -t nat $OP PREROUTING  -i vmbr0 -p tcp --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat $OP PREROUTING  -i vmbr1 -p tcp -d "$HOST_IP" --dport "$EXT_PORT" -j DNAT --to "$VM_IP:22"
    iptables -t nat $OP POSTROUTING -s "$SUBNET" -d "$VM_IP" -p tcp --dport 22 -j MASQUERADE
done
