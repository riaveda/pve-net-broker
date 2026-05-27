"""Pydantic models for Homey Slave Manager."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel


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


class SlaveResponse(BaseModel):
    id: str
    ip: str
    status: SlaveStatus
    requester: Optional[str] = None
    vm_ip: Optional[str] = None
    reserved_at: Optional[datetime] = None


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"
    slaves_total: int = 0
    slaves_available: int = 0
    slaves_reserved: int = 0
