"""API routes for PVE Net Broker."""

from fastapi import APIRouter, HTTPException
from src.models import (
    HealthResponse,
    ReserveRequest,
    Slave,
    SlaveResponse,
    SlaveStatus,
)
from src.state import get_all_slaves, get_slave, reserve_slave, release_slave

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health():
    slaves = await get_all_slaves()
    return HealthResponse(
        status="ok",
        version="0.1.0",
        slaves_total=len(slaves),
        slaves_available=sum(1 for s in slaves if s.status == SlaveStatus.available),
        slaves_reserved=sum(1 for s in slaves if s.status == SlaveStatus.reserved),
    )


@router.get("/slaves", response_model=list[SlaveResponse])
async def list_slaves():
    slaves = await get_all_slaves()
    return [SlaveResponse(**s.model_dump()) for s in slaves]


@router.get("/slaves/{slave_id}", response_model=SlaveResponse)
async def get_slave_detail(slave_id: str):
    slave = await get_slave(slave_id)
    if not slave:
        raise HTTPException(status_code=404, detail=f"Slave '{slave_id}' not found")
    return SlaveResponse(**slave.model_dump())


@router.post("/slaves/{slave_id}/reserve", response_model=SlaveResponse)
async def reserve(slave_id: str, req: ReserveRequest):
    slave = await get_slave(slave_id)
    if not slave:
        raise HTTPException(status_code=404, detail=f"Slave '{slave_id}' not found")
    if slave.status == SlaveStatus.reserved:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "Slave already reserved",
                "requester": slave.requester,
                "vm_ip": slave.vm_ip,
                "reserved_at": slave.reserved_at.isoformat() if slave.reserved_at else None,
            },
        )
    if slave.status == SlaveStatus.offline:
        raise HTTPException(status_code=503, detail="Slave is offline")

    updated = await reserve_slave(slave_id, req.requester, req.vm_ip)
    return SlaveResponse(**updated.model_dump())


@router.post("/slaves/{slave_id}/release", response_model=SlaveResponse)
async def release(slave_id: str):
    slave = await get_slave(slave_id)
    if not slave:
        raise HTTPException(status_code=404, detail=f"Slave '{slave_id}' not found")
    if slave.status != SlaveStatus.reserved:
        raise HTTPException(status_code=400, detail="Slave is not reserved")

    updated = await release_slave(slave_id)
    return SlaveResponse(**updated.model_dump())
