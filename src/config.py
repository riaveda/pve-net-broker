"""Configuration for PVE Net Broker."""

import os

# API
API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("API_PORT", "7100"))

# Network
PVE_HOST_IP = os.getenv("PVE_HOST_IP", "10.231.184.162")
VMBR1_SUBNET = os.getenv("VMBR1_SUBNET", "10.10.10.0/24")
VMBR1_GATEWAY = os.getenv("VMBR1_GATEWAY", "10.10.10.1")

# Homey Pro slave ports (source-verified from homey-pro-linux/slave-socat)
# 10000: D-Bus (system_bus_socket)
# 10002: Coprocessor Control UART (ttyAMA2, 115200)
# 10003: Coprocessor Debug UART  (ttyAMA3, 115200)
# 10004: Zigbee UART             (ttyAMA4, 115200)
# 20006: GPIO 6  — CM4 Reset
# 20024: GPIO 24 — Coprocessor Boot
# 20025: GPIO 25 — Coprocessor Reset
SLAVE_PORTS = [10000, 10002, 10003, 10004, 20006, 20024, 20025]

# Homey Pro USB identification (g_ether gadget, RNDIS)
# source: homey-pro-linux/stages/stagehomey-dev/50-usb-networking/files/etc/modprobe.d/rndis.conf
HOMEY_USB_MAC = "00:00:00:00:00:01"  # host_addr hardcoded in Homey Pro firmware
HOMEY_USB_VENDOR_ID = "0525"         # Netchip Technology (g_ether default)
HOMEY_USB_PRODUCT_ID = "a4a2"        # g_ether default
HOMEY_USB_MANUFACTURER = "Athom B.V."
HOMEY_USB_PRODUCT = "Homey Pro"

# Slave network prefix: Homey slaves get IPs like 10.1.X.1
SLAVE_IP_PREFIX = "10.1"

# State persistence
STATE_DB_PATH = os.getenv("STATE_DB_PATH", "/opt/pve-net-broker/data/state.db")

# Lease TTL defaults
LEASE_DEFAULT_TTL = int(os.getenv("LEASE_DEFAULT_TTL", "300"))  # 5 min
LEASE_MIN_TTL = 60
LEASE_MAX_TTL = 7200
LEASE_SWEEP_INTERVAL = int(os.getenv("LEASE_SWEEP_INTERVAL", "30"))  # sweep every 30s
