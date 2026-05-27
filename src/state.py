"""State persistence using SQLite."""

import aiosqlite
from datetime import datetime, timezone
from typing import Optional

from src.config import STATE_DB_PATH
from src.models import Slave, SlaveStatus

DB_PATH = STATE_DB_PATH


async def init_db():
    """Create tables if not exist."""
    import os
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS slaves (
                id TEXT PRIMARY KEY,
                ip TEXT NOT NULL,
                usb_interface TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'offline',
                requester TEXT,
                vm_ip TEXT,
                reserved_at TEXT
            )
        """)
        await db.commit()


async def get_all_slaves() -> list[Slave]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute("SELECT * FROM slaves") as cursor:
            rows = await cursor.fetchall()
            return [_row_to_slave(row) for row in rows]


async def get_slave(slave_id: str) -> Optional[Slave]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute("SELECT * FROM slaves WHERE id = ?", (slave_id,)) as cursor:
            row = await cursor.fetchone()
            return _row_to_slave(row) if row else None


async def register_slave(slave_id: str, ip: str, usb_interface: str) -> Slave:
    """Register or update a slave (called on USB detection)."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            INSERT INTO slaves (id, ip, usb_interface, status)
            VALUES (?, ?, ?, 'available')
            ON CONFLICT(id) DO UPDATE SET
                ip = excluded.ip,
                usb_interface = excluded.usb_interface,
                status = 'available'
        """, (slave_id, ip, usb_interface))
        await db.commit()
    return Slave(id=slave_id, ip=ip, usb_interface=usb_interface, status=SlaveStatus.available)


async def unregister_slave(slave_id: str):
    """Mark slave as offline (called on USB disconnect)."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("UPDATE slaves SET status = 'offline', requester = NULL, vm_ip = NULL, reserved_at = NULL WHERE id = ?", (slave_id,))
        await db.commit()


async def reserve_slave(slave_id: str, requester: str, vm_ip: str) -> Slave:
    """Reserve a slave and apply iptables rules."""
    from src.iptables_manager import add_slave_rules

    now = datetime.now(timezone.utc)
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            UPDATE slaves SET status = 'reserved', requester = ?, vm_ip = ?, reserved_at = ?
            WHERE id = ?
        """, (requester, vm_ip, now.isoformat(), slave_id))
        await db.commit()

    slave = await get_slave(slave_id)
    # Apply iptables rules
    add_slave_rules(vm_ip, slave.ip)
    return slave


async def release_slave(slave_id: str) -> Slave:
    """Release a slave and remove iptables rules."""
    from src.iptables_manager import remove_slave_rules

    slave = await get_slave(slave_id)
    # Remove iptables rules
    remove_slave_rules(slave.vm_ip, slave.ip)

    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            UPDATE slaves SET status = 'available', requester = NULL, vm_ip = NULL, reserved_at = NULL
            WHERE id = ?
        """, (slave_id,))
        await db.commit()

    return await get_slave(slave_id)


def _row_to_slave(row) -> Slave:
    return Slave(
        id=row["id"],
        ip=row["ip"],
        usb_interface=row["usb_interface"],
        status=SlaveStatus(row["status"]),
        requester=row["requester"],
        vm_ip=row["vm_ip"],
        reserved_at=datetime.fromisoformat(row["reserved_at"]) if row["reserved_at"] else None,
    )
