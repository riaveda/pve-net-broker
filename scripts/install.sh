#!/bin/bash
# PVE Net Broker — Installation script
# Run on PVE host: sudo bash /opt/pve-net-broker/scripts/install.sh

set -e

PROJECT_DIR="/opt/pve-net-broker"

echo "=== PVE Net Broker — Install ==="

# 1. Create venv and install dependencies
echo "[1/5] Setting up Python virtual environment..."
cd "$PROJECT_DIR"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .

# 2. Create data directory
echo "[2/5] Creating data directory..."
mkdir -p "$PROJECT_DIR/data"

# 3. Symlink systemd service
echo "[3/5] Installing systemd service..."
ln -sf "$PROJECT_DIR/systemd/pve-net-broker.service" /etc/systemd/system/pve-net-broker.service
systemctl daemon-reload

# 4. Symlink udev rules
echo "[4/5] Installing udev rules..."
ln -sf "$PROJECT_DIR/udev/99-homey-slave.rules" /etc/udev/rules.d/99-homey-slave.rules
udevadm control --reload-rules

# 5. Symlink nat-rules.sh
echo "[5/5] Linking NAT rules script..."
# Backup original if exists and not already a symlink
if [ -f /etc/network/nat-rules.sh ] && [ ! -L /etc/network/nat-rules.sh ]; then
    cp /etc/network/nat-rules.sh /etc/network/nat-rules.sh.bak
    echo "  → Backed up original to /etc/network/nat-rules.sh.bak"
fi
ln -sf "$PROJECT_DIR/network/nat-rules.sh" /etc/network/nat-rules.sh
chmod +x "$PROJECT_DIR/network/nat-rules.sh"

# 5b. Install DHCP config into /etc/dhcp (COPY, not symlink)
#     dhcpd is AppArmor-confined to /etc/dhcp, so a symlink to /opt is denied.
echo "[5b] Installing DHCP config..."
if [ -f /etc/dhcp/dhcpd.conf ] && [ ! -L /etc/dhcp/dhcpd.conf ] && [ ! -f /etc/dhcp/dhcpd.conf.bak ]; then
    cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
    echo "  → Backed up original to /etc/dhcp/dhcpd.conf.bak"
fi
rm -f /etc/dhcp/dhcpd.conf   # drop any pre-existing symlink
cp "$PROJECT_DIR/network/dhcpd.conf" /etc/dhcp/dhcpd.conf
cp "$PROJECT_DIR/network/dhcp-hosts.conf" /etc/dhcp/dhcp-hosts.conf

# Make scripts executable
chmod +x "$PROJECT_DIR/scripts/"*.sh
chmod +x "$PROJECT_DIR/scripts/pnbctl"

# Install CLI tool
echo "[6/6] Installing pnbctl CLI..."
ln -sf "$PROJECT_DIR/scripts/pnbctl" /usr/local/bin/pnbctl

# Enable and start service
echo ""
echo "=== Enabling service ==="
systemctl enable --now pve-net-broker

echo ""
echo "=== Installation complete ==="
echo "  Service: systemctl status pve-net-broker"
echo "  Logs:    journalctl -u pve-net-broker -f"
echo "  API:     http://10.10.10.1:7100/health"
