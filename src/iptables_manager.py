"""iptables rule management for PVE Net Broker.

Manages dynamic DNAT/MASQUERADE rules for Homey slave devices.
Uses a dedicated chain (PVE-NET-BROKER) to avoid conflicts with static NAT rules.
"""

import logging
import subprocess

from src.config import SLAVE_PORTS

logger = logging.getLogger(__name__)

CHAIN_NAME = "PVE-NET-BROKER"


def _run_iptables(args: list[str]) -> bool:
    """Execute an iptables command. Returns True on success."""
    cmd = ["iptables"] + args
    logger.info("iptables: %s", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error("iptables failed: %s", result.stderr.strip())
        return False
    return True


def ensure_chain():
    """Ensure our custom chain exists in nat table."""
    # Create chain if not exists
    subprocess.run(
        ["iptables", "-t", "nat", "-N", CHAIN_NAME],
        capture_output=True,
    )
    # Ensure jump from PREROUTING to our chain (idempotent check)
    check = subprocess.run(
        ["iptables", "-t", "nat", "-C", "PREROUTING", "-j", CHAIN_NAME],
        capture_output=True,
    )
    if check.returncode != 0:
        _run_iptables(["-t", "nat", "-A", "PREROUTING", "-j", CHAIN_NAME])

    # Same for POSTROUTING
    subprocess.run(
        ["iptables", "-t", "nat", "-N", f"{CHAIN_NAME}-POST"],
        capture_output=True,
    )
    check = subprocess.run(
        ["iptables", "-t", "nat", "-C", "POSTROUTING", "-j", f"{CHAIN_NAME}-POST"],
        capture_output=True,
    )
    if check.returncode != 0:
        _run_iptables(["-t", "nat", "-A", "POSTROUTING", "-j", f"{CHAIN_NAME}-POST"])


def add_slave_rules(vm_ip: str, slave_ip: str):
    """Add DNAT + MASQUERADE rules for all slave ports."""
    ensure_chain()
    for port in SLAVE_PORTS:
        # DNAT: VM → Slave
        _run_iptables([
            "-t", "nat", "-A", CHAIN_NAME,
            "-s", vm_ip, "-p", "tcp", "--dport", str(port),
            "-j", "DNAT", "--to-destination", f"{slave_ip}:{port}",
        ])
        # MASQUERADE for return traffic
        _run_iptables([
            "-t", "nat", "-A", f"{CHAIN_NAME}-POST",
            "-d", slave_ip, "-p", "tcp", "--dport", str(port),
            "-j", "MASQUERADE",
        ])
    logger.info("Added slave rules: %s → %s", vm_ip, slave_ip)


def remove_slave_rules(vm_ip: str, slave_ip: str):
    """Remove DNAT + MASQUERADE rules for all slave ports."""
    for port in SLAVE_PORTS:
        _run_iptables([
            "-t", "nat", "-D", CHAIN_NAME,
            "-s", vm_ip, "-p", "tcp", "--dport", str(port),
            "-j", "DNAT", "--to-destination", f"{slave_ip}:{port}",
        ])
        _run_iptables([
            "-t", "nat", "-D", f"{CHAIN_NAME}-POST",
            "-d", slave_ip, "-p", "tcp", "--dport", str(port),
            "-j", "MASQUERADE",
        ])
    logger.info("Removed slave rules: %s → %s", vm_ip, slave_ip)


def flush_all_dynamic_rules():
    """Flush all dynamic rules (service shutdown cleanup)."""
    subprocess.run(["iptables", "-t", "nat", "-F", CHAIN_NAME], capture_output=True)
    subprocess.run(["iptables", "-t", "nat", "-F", f"{CHAIN_NAME}-POST"], capture_output=True)
    logger.info("Flushed all dynamic slave rules")
