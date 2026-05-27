"""PVE Net Broker — FastAPI application entry point."""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.routes import router
from src.state import init_db, lease_sweeper_loop, sweep_expired_leases

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize DB on startup, start lease sweeper."""
    await init_db()
    # Sweep once immediately on boot (recover from restart)
    await sweep_expired_leases()
    # Start background sweeper
    task = asyncio.create_task(lease_sweeper_loop())
    yield
    task.cancel()


app = FastAPI(
    title="PVE Net Broker",
    description="PVE host network broker: NAT, USB device brokering, exclusive port forwarding",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(router)
