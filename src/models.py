"""Pydantic models for PVE Net Broker."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel

from src.config import VMBR1_GATEWAY


class SlaveStatus(str, Enum):
    available = "available"
    reserved = "reserved"
    offline = "offline"


class Slave(BaseModel):
    id: str  # e.g. "homey-0", "homey-1"
    ip: str  # e.g. "10.1.0.1"
    usb_interface: str  # e.g. "usb0"
    status: SlaveStatus = SlaveStatus.offline
    requester: Optional[str] = None  # container ID
    vm_ip: Optional[str] = None  # requesting VM IP
    reserved_at: Optional[datetime] = None


class ReserveRequest(BaseModel):
    requester: str  # container ID
    vm_ip: str  # e.g. "10.10.10.2"


class RegisterRequest(BaseModel):
    id: str  # e.g. "homey-0"
    ip: str  # e.g. "10.1.0.1"
    usb_interface: str  # e.g. "usb0"


def build_slave_env_vars(gateway_ip: str = VMBR1_GATEWAY) -> dict[str, str]:
    """Homey slave 연결용 환경변수. VHS가 docker-compose에 그대로 inject 가능."""
    return {
        "HOMEY_DBUS_PATH": f"tcp:host={gateway_ip},port=10000",
        "HOMEY_CM4_GPIO_RESET_PATH": f"tcp:{gateway_ip}:20006",
        "HOMEY_COPROCESSOR_GPIO_BOOT_PATH": f"tcp:{gateway_ip}:20024",
        "HOMEY_COPROCESSOR_GPIO_RESET_PATH": f"tcp:{gateway_ip}:20025",
        "HOMEY_COPROCESSOR_UART_CTRL_PATH": f"tcp:{gateway_ip}:10002",
        "HOMEY_COPROCESSOR_UART_PROG_PATH": f"tcp:{gateway_ip}:10003",
        "HOMEY_OTBR_CTL_PATH": f"tcp:{gateway_ip}:10007",
        "HOMEY_Z3GATEWAY_RPC_SOCKET_PATH": f"tcp:{gateway_ip}:10006",
    }


class SlaveResponse(BaseModel):
    id: str
    ip: str
    status: SlaveStatus
    requester: Optional[str] = None
    vm_ip: Optional[str] = None
    reserved_at: Optional[datetime] = None
    env_vars: Optional[dict[str, str]] = None  # docker-compose inject용


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"
    slaves_total: int = 0
    slaves_available: int = 0
    slaves_reserved: int = 0
