"""PVE Net Broker — FastAPI application entry point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.routes import router
from src.state import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize DB on startup."""
    await init_db()
    yield


app = FastAPI(
    title="PVE Net Broker",
    description="PVE host network broker: NAT, USB device brokering, exclusive port forwarding",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(router)
