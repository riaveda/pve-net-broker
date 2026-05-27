#!/bin/bash
# PVE Net Broker — Deploy (git pull + restart)
set -e

cd /opt/pve-net-broker
git pull origin main
.venv/bin/pip install -e . --quiet
systemctl restart pve-net-broker

echo "Deployed. Status:"
systemctl status pve-net-broker --no-pager -l
