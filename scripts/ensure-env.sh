#!/bin/bash
# PVE Net Broker — env 파일 준비(멱등). install.sh·deploy.sh 가 부른다.
#   · 파일이 없으면 example 에서 만든다
#   · API_KEY 가 없거나 비어 있으면 생성한다 — 예약·해제 API 가 fail-closed 라 없으면 그 경로가 전부 503 이다
#   · 키가 든 파일이므로 0600 으로 조인다
# 사람이 손으로 만들지 않는다 — 서버를 옮긴 날 아무도 기억하지 못한다(재현 가능한 배포).
set -e

DIR="${PNB_DIR:-/opt/pve-net-broker}"
ENV_FILE="$DIR/systemd/pve-net-broker.env"
EXAMPLE="$DIR/systemd/pve-net-broker.env.example"

if [ ! -f "$ENV_FILE" ]; then
    cp "$EXAMPLE" "$ENV_FILE"
    echo "ensure-env: created $ENV_FILE from example"
fi

if ! grep -qE '^API_KEY=.+' "$ENV_FILE"; then
    key="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    if grep -qE '^API_KEY=' "$ENV_FILE"; then
        sed -i "s|^API_KEY=.*|API_KEY=$key|" "$ENV_FILE"
    else
        printf '\n# reserve/renew/release 용 X-Api-Key (ensure-env.sh 생성)\nAPI_KEY=%s\n' "$key" >> "$ENV_FILE"
    fi
    echo "ensure-env: generated API_KEY in $ENV_FILE"
fi

chmod 600 "$ENV_FILE"
