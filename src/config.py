"""Configuration for PVE Net Broker."""

import os

# API
API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("API_PORT", "7100"))

# Network
PVE_HOST_IP = os.getenv("PVE_HOST_IP", "10.231.184.162")
VMBR1_SUBNET = os.getenv("VMBR1_SUBNET", "10.10.10.0/24")
VMBR1_GATEWAY = os.getenv("VMBR1_GATEWAY", "10.10.10.1")

# Homey Slave ports (UART serial, Zigbee, Z-Wave, Thread, IR, etc.)
SLAVE_PORTS = [10000, 10002, 10003, 10005, 10006, 10007, 20006, 20024, 20025]

# Homey USB identification
HOMEY_USB_VENDOR_ID = "0bda"  # placeholder — update when actual Homey is connected
HOMEY_USB_PRODUCT_ID = "8152"  # placeholder — update when actual Homey is connected

# Slave network prefix: Homey slaves get IPs like 10.1.X.1
SLAVE_IP_PREFIX = "10.1"

# State persistence
STATE_DB_PATH = os.getenv("STATE_DB_PATH", "/opt/pve-net-broker/data/state.db")

# TTL for auto-release (seconds, 0 = disabled)
RESERVATION_TTL = int(os.getenv("RESERVATION_TTL", "7200"))  # 2 hours
