#!/bin/bash
# PVE Net Broker — USB event handler
# Called by udev rule: /etc/udev/rules.d/99-homey-slave.rules
# Usage: on-usb-event.sh <add|remove> <interface_name>

set -e

ACTION=$1
IFACE=$2
BROKER_URL="http://127.0.0.1:7100"

if [ -z "$ACTION" ] || [ -z "$IFACE" ]; then
    echo "Usage: $0 <add|remove> <interface_name>"
    exit 1
fi

# Derive slave ID from interface name (usb0 → homey-0, usb1 → homey-1)
SLAVE_NUM="${IFACE//[!0-9]/}"
SLAVE_ID="homey-${SLAVE_NUM}"

# Derive slave IP from interface (usb0 → 10.1.0.1, usb1 → 10.1.1.1)
SLAVE_IP="10.1.${SLAVE_NUM}.1"

if [ "$ACTION" = "add" ]; then
    # Wait for interface to be ready
    sleep 2
    # Register slave via API
    curl -sf -X POST "${BROKER_URL}/internal/slaves/register" \
        -H "Content-Type: application/json" \
        -d "{\"id\": \"${SLAVE_ID}\", \"ip\": \"${SLAVE_IP}\", \"usb_interface\": \"${IFACE}\"}" \
        || echo "WARNING: Failed to register slave ${SLAVE_ID}"
elif [ "$ACTION" = "remove" ]; then
    # Unregister slave via API
    curl -sf -X POST "${BROKER_URL}/internal/slaves/${SLAVE_ID}/unregister" \
        || echo "WARNING: Failed to unregister slave ${SLAVE_ID}"
fi
