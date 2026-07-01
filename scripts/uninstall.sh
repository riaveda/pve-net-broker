#!/bin/bash
# PVE Net Broker — Uninstall script
set -e

echo "=== PVE Net Broker — Uninstall ==="

systemctl disable --now pve-net-broker 2>/dev/null || true

rm -f /etc/systemd/system/pve-net-broker.service
rm -f /etc/udev/rules.d/99-homey-slave.rules

# Restore original nat-rules.sh if backup exists
if [ -f /etc/network/nat-rules.sh.bak ]; then
    mv /etc/network/nat-rules.sh.bak /etc/network/nat-rules.sh
    echo "  → Restored original nat-rules.sh"
else
    rm -f /etc/network/nat-rules.sh
fi

# Restore original dhcpd.conf if backup exists; drop copied hosts file
rm -f /etc/dhcp/dhcpd.conf /etc/dhcp/dhcp-hosts.conf
if [ -f /etc/dhcp/dhcpd.conf.bak ]; then
    mv /etc/dhcp/dhcpd.conf.bak /etc/dhcp/dhcpd.conf
    echo "  → Restored original dhcpd.conf"
fi

systemctl daemon-reload
udevadm control --reload-rules

echo "=== Uninstall complete ==="
echo "  Project files remain at /opt/pve-net-broker/"
echo "  Remove manually: rm -rf /opt/pve-net-broker"
