"""API tests for PVE Net Broker — 문지기(키·호스트 한정)와 vm_ip 대장 검증까지.

설정은 **import 전에** 환경변수로 준다(config.py 가 import 시점에 읽는다):
  · API_KEY        = 시험용 키 (없으면 예약 경로가 503 으로 닫힌다 — 그 fail-closed 도 아래에서 잰다)
  · STATE_DB_PATH  = 임시 디렉터리 (호스트의 /opt 경로를 건드리지 않는다)
  · DHCP_HOSTS_PATH= 이 저장소의 network/dhcp-hosts.conf (진짜 대장으로 검증한다)
iptables 는 시험 환경에 없으므로 규칙 적용 함수를 무력화한다 — 여기서 재는 것은 API 의 판정이지 iptables 가 아니다.
"""

import os
import pathlib
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[1]
os.environ.setdefault("API_KEY", "test-key")
os.environ.setdefault("STATE_DB_PATH", os.path.join(tempfile.mkdtemp(prefix="pnb-test-"), "state.db"))
os.environ.setdefault("DHCP_HOSTS_PATH", str(REPO / "network" / "dhcp-hosts.conf"))

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402

import src.iptables_manager as ipt  # noqa: E402
from src.fixed_ips import known_fixed_ips  # noqa: E402
from src.main import app  # noqa: E402
from src.state import init_db  # noqa: E402

KEY = {"X-Api-Key": "test-key"}
GATEWAY = "10.10.10.1"  # 호스트 자신이 바인드 주소로 자기를 부를 때의 출발지


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture(autouse=True)
async def _db_and_no_iptables(monkeypatch):
    """ASGITransport 는 lifespan 을 안 돌리므로 DB 초기화를 직접 한다. iptables 호출은 무력화."""
    await init_db()
    monkeypatch.setattr(ipt, "add_slave_rules", lambda vm_ip, slave_ip: None)
    monkeypatch.setattr(ipt, "remove_slave_rules", lambda vm_ip, slave_ip: None)


def client(source: str = "10.10.10.5") -> AsyncClient:
    """출발지 주소를 정해 부른다 — 기본은 vmbr1 안의 VM(호스트 자신이 아님)."""
    return AsyncClient(transport=ASGITransport(app=app, client=(source, 12345)), base_url="http://test")


async def _register(c: AsyncClient, n: int):
    r = await c.post(
        "/internal/slaves/register",
        json={"id": f"homey-{n}", "ip": f"10.1.{n}.1", "usb_interface": f"usb{n}"},
    )
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.anyio
async def test_health():
    async with client() as c:
        resp = await c.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert "version" in data


@pytest.mark.anyio
async def test_get_slave_not_found():
    async with client() as c:
        resp = await c.get("/slaves/nonexistent")
        assert resp.status_code == 404


# ── /internal 은 호스트 자신만 ──

@pytest.mark.anyio
async def test_internal_register_rejects_vm_source():
    async with client("10.10.10.5") as c:
        r = await c.post(
            "/internal/slaves/register", json={"id": "homey-90", "ip": "10.1.90.1", "usb_interface": "usb90"}
        )
        assert r.status_code == 403


@pytest.mark.anyio
async def test_internal_register_accepts_host_local():
    async with client(GATEWAY) as c:
        data = await _register(c, 91)
        assert data["status"] == "available"
    async with client("127.0.0.1") as c:
        r = await c.post("/internal/slaves/homey-91/unregister")
        assert r.status_code == 200 and r.json()["status"] == "offline"


# ── 예약·해제는 API 키 ──

@pytest.mark.anyio
async def test_reserve_requires_api_key():
    async with client(GATEWAY) as c:
        await _register(c, 92)
    good_ip = sorted(known_fixed_ips())[0]
    async with client() as c:
        r = await c.post("/slaves/homey-92/reserve", json={"requester": "t", "vm_ip": good_ip})
        assert r.status_code == 401
        r = await c.post(
            "/slaves/homey-92/reserve", json={"requester": "t", "vm_ip": good_ip}, headers={"X-Api-Key": "wrong"}
        )
        assert r.status_code == 401
        r = await c.post("/slaves/homey-92/release", json={})
        assert r.status_code == 401


@pytest.mark.anyio
async def test_reserve_is_closed_when_key_unconfigured(monkeypatch):
    monkeypatch.setattr("src.auth.API_KEY", "")
    good_ip = sorted(known_fixed_ips())[0]
    async with client() as c:
        r = await c.post("/slaves/homey-92/reserve", json={"requester": "t", "vm_ip": good_ip}, headers=KEY)
        assert r.status_code == 503


# ── vm_ip 는 고정 IP 대장에 있는 주소만 ──

@pytest.mark.anyio
async def test_reserve_rejects_vm_ip_outside_ledger():
    async with client(GATEWAY) as c:
        await _register(c, 93)
    async with client() as c:
        for bad in ("10.10.10.250", "192.168.1.5", "not-an-ip", "10.10.10.1"):
            r = await c.post("/slaves/homey-93/reserve", json={"requester": "t", "vm_ip": bad}, headers=KEY)
            assert r.status_code == 400, (bad, r.text)


@pytest.mark.anyio
async def test_reserve_accepts_ledger_ip_and_release():
    ledger = known_fixed_ips()
    assert ledger, "network/dhcp-hosts.conf 에 fixed-address 가 있어야 한다"
    good_ip = sorted(ledger)[0]
    async with client(GATEWAY) as c:
        await _register(c, 94)
    async with client() as c:
        r = await c.post("/slaves/homey-94/reserve", json={"requester": "t", "vm_ip": good_ip}, headers=KEY)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["status"] == "reserved" and body["vm_ip"] == good_ip
        r = await c.post("/slaves/homey-94/release", json={"lease_id": body["lease_id"]}, headers=KEY)
        assert r.status_code == 200 and r.json()["status"] == "available"
