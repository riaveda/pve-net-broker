"""vm_ip 검증 — 고정 IP 대장(network/dhcp-hosts.conf)에 있는 주소만 예약할 수 있다.

왜 필요한가: 예약은 그 주소를 **출발지로 하는 DNAT** 를 PVE nat 테이블에 넣는다. 대장 밖 주소를 받으면
  임의 출발지 규칙이 호스트에 쌓인다(감사 B-01 ④). 대장은 이 저장소가 유일한 정본이므로(CLAUDE.md §1
  "고정 IP 는 dhcp-hosts.conf 에서만") 검증도 그 파일 하나만 읽는다 — 사본 목록을 두지 않는다.

fail-closed: 대장을 못 읽거나 비어 있으면 **아무 주소도 통과하지 않는다.** "대장이 없으니 일단 허용" 은
  검증이 없는 것과 같다.
"""

import ipaddress
import re

from src.config import DHCP_HOSTS_PATH, VMBR1_SUBNET

# dhcpd 문법: `  fixed-address 10.10.10.35;`
_FIXED = re.compile(r"^\s*fixed-address\s+([0-9.]+)\s*;")


def known_fixed_ips(path: str = DHCP_HOSTS_PATH) -> set[str]:
    """대장의 fixed-address 전부. 파일을 못 읽으면 빈 집합(= 아무것도 통과 안 함)."""
    try:
        with open(path, encoding="utf-8") as f:
            return {m.group(1) for m in map(_FIXED.match, f) if m}
    except OSError:
        return set()


def validate_vm_ip(vm_ip: str, path: str = DHCP_HOSTS_PATH) -> None:
    """통과하면 None, 아니면 ValueError(사유). 형식 → 대역 → 대장 순으로 본다."""
    try:
        ip = ipaddress.IPv4Address(vm_ip)
    except ValueError:
        raise ValueError(f"vm_ip is not an IPv4 address: {vm_ip!r}") from None
    if ip not in ipaddress.IPv4Network(VMBR1_SUBNET):
        raise ValueError(f"vm_ip {vm_ip} is outside {VMBR1_SUBNET}")
    known = known_fixed_ips(path)
    if not known:
        raise ValueError(f"fixed-IP ledger is unreadable or empty: {path}")
    if vm_ip not in known:
        raise ValueError(f"vm_ip {vm_ip} is not a fixed-address in {path} — add the VM there first")
