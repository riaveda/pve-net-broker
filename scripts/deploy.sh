#!/bin/bash
# PVE Net Broker — Deploy (git pull + restart)
set -e

cd /opt/pve-net-broker
git pull origin main
.venv/bin/pip install -e . --quiet
# env 파일·API_KEY 를 갖춘다(멱등) — 재시작 전에 있어야 예약·해제 API 가 열린다.
bash scripts/ensure-env.sh
systemctl daemon-reload
systemctl restart pve-net-broker

echo "Deployed. Status:"
systemctl status pve-net-broker --no-pager -l
