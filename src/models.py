"""Pydantic models for PVE Net Broker."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, field_validator

from src.config import VMBR1_GATEWAY, LEASE_DEFAULT_TTL, LEASE_MIN_TTL, LEASE_MAX_TTL


class SlaveStatus(str, Enum):
    available = "available"
    reserved = "reserved"
    offline = "offline"


class Slave(BaseModel):
    id: str
    ip: str
    usb_interface: str
    status: SlaveStatus = SlaveStatus.offline
    requester: Optional[str] = None
    vm_ip: Optional[str] = None
    reserved_at: Optional[datetime] = None
    lease_id: Optional[str] = None
    expires_at: Optional[datetime] = None


class ReserveRequest(BaseModel):
    requester: str
    vm_ip: str
    ttl: int = LEASE_DEFAULT_TTL

    @field_validator("ttl")
    @classmethod
    def clamp_ttl(cls, v: int) -> int:
        return max(LEASE_MIN_TTL, min(v, LEASE_MAX_TTL))


class RenewRequest(BaseModel):
    lease_id: str
    ttl: int = LEASE_DEFAULT_TTL

    @field_validator("ttl")
    @classmethod
    def clamp_ttl(cls, v: int) -> int:
        return max(LEASE_MIN_TTL, min(v, LEASE_MAX_TTL))


class ReleaseRequest(BaseModel):
    lease_id: Optional[str] = None


class RegisterRequest(BaseModel):
    id: str
    ip: str
    usb_interface: str


def build_slave_env_vars(gateway_ip: str = VMBR1_GATEWAY) -> dict[str, str]:
    """Homey slave 연결용 환경변수. VHS가 docker-compose에 그대로 inject 가능.
    
    포트 출처: homey-pro-linux/stages/stagehomey-dev/30-startup/files/usr/bin/slave-socat
    """
    return {
        "HOMEY_DBUS_PATH": f"tcp:host={gateway_ip},port=10000",
        "HOMEY_CM4_GPIO_RESET_PATH": f"tcp:{gateway_ip}:20006",
        "HOMEY_COPROCESSOR_GPIO_BOOT_PATH": f"tcp:{gateway_ip}:20024",
        "HOMEY_COPROCESSOR_GPIO_RESET_PATH": f"tcp:{gateway_ip}:20025",
        "HOMEY_COPROCESSOR_UART_CTRL_PATH": f"tcp:{gateway_ip}:10002",
        "HOMEY_COPROCESSOR_UART_PROG_PATH": f"tcp:{gateway_ip}:10003",
        "HOMEY_ZIGBEE_UART_PATH": f"tcp:{gateway_ip}:10004",
    }


class SlaveResponse(BaseModel):
    id: str
    ip: str
    status: SlaveStatus
    requester: Optional[str] = None
    vm_ip: Optional[str] = None
    reserved_at: Optional[datetime] = None
    lease_id: Optional[str] = None
    expires_at: Optional[datetime] = None
    env_vars: Optional[dict[str, str]] = None


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"
    slaves_total: int = 0
    slaves_available: int = 0
    slaves_reserved: int = 0
