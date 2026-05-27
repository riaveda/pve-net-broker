# PVE Net Broker — Integration Guide for AI Agents

> 이 문서는 Agent Platform, BYOH(VHS), 기타 AI 에이전트가 PVE Net Broker와 통합할 때 참고하는 명세입니다.

## 1. 개요

**PVE Net Broker**는 PVE(Proxmox) 호스트에서 실행되는 네트워크/디바이스 중앙 브로커입니다.

### 역할

| 기능 | 설명 |
|------|------|
| **정적 NAT 관리** | VM→인터넷 MASQUERADE, 서비스 포트 포워딩, SSH 포워딩 |
| **물리 디바이스 브로커링** | USB 연결된 Homey Pro를 감지하고 exclusive access 관리 |
| **동적 포트 포워딩** | 예약된 VM↔디바이스 간 iptables 규칙 자동 생성/제거 |
| **배타적 잠금** | 하나의 디바이스에 동시 1개 VM만 접근 가능 |

### 왜 필요한가?

물리 Homey Pro의 안테나(Zigbee, Z-Wave, Thread, IR)는 **UART 시리얼 1:1 연결**만 가능합니다.
여러 VM/컨테이너가 동시 접근하면 충돌합니다.
PVE Net Broker가 배타적 잠금을 보장하고, 네트워크 경로를 자동으로 열어줍니다.

---

## 2. 네트워크 토폴로지

```
┌─────────────────────── PVE Host (10.231.184.162) ───────────────────────┐
│                                                                          │
│  vmbr0 (10.231.184.162/22) ── 외부 네트워크                              │
│  vmbr1 (10.10.10.1/24)    ── 내부 VM 네트워크                            │
│  usb0  (10.1.0.1)         ── Homey Pro #0 (USB Ethernet)                │
│  usb1  (10.1.1.1)         ── Homey Pro #1 (USB Ethernet)                │
│                                                                          │
│  [PVE Net Broker] ── 0.0.0.0:7100                                       │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  VM: 10.10.10.2  ── VHS (Docker로 Homey OS 컨테이너 실행)               │
│  VM: 10.10.10.41 ── Agent Platform                                       │
│  VM: 10.10.10.40 ── MultiBizpack                                         │
│  VM: 10.10.10.5  ── Reference Platform                                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. API 명세

**Base URL**: `http://10.10.10.1:7100`

### 3.1 Health Check

```
GET /health
```

Response:
```json
{
  "status": "ok",
  "version": "0.1.0",
  "slaves_total": 2,
  "slaves_available": 1,
  "slaves_reserved": 1
}
```

### 3.2 List Slaves (디바이스 목록)

```
GET /slaves
```

Response:
```json
[
  {
    "id": "homey-0",
    "ip": "10.1.0.1",
    "status": "available",
    "requester": null,
    "vm_ip": null,
    "reserved_at": null,
    "lease_id": null,
    "expires_at": null,
    "env_vars": {
      "HOMEY_DBUS_PATH": "tcp:host=10.10.10.1,port=10000",
      "HOMEY_CM4_GPIO_RESET_PATH": "tcp:10.10.10.1:20006",
      "HOMEY_COPROCESSOR_GPIO_BOOT_PATH": "tcp:10.10.10.1:20024",
      "HOMEY_COPROCESSOR_GPIO_RESET_PATH": "tcp:10.10.10.1:20025",
      "HOMEY_COPROCESSOR_UART_CTRL_PATH": "tcp:10.10.10.1:10002",
      "HOMEY_COPROCESSOR_UART_PROG_PATH": "tcp:10.10.10.1:10003",
      "HOMEY_OTBR_CTL_PATH": "tcp:10.10.10.1:10007",
      "HOMEY_Z3GATEWAY_RPC_SOCKET_PATH": "tcp:10.10.10.1:10006"
    }
  },
  {
    "id": "homey-1",
    "ip": "10.1.1.1",
    "status": "reserved",
    "requester": "container-xyz",
    "vm_ip": "10.10.10.2",
    "reserved_at": "2026-05-27T10:30:00Z",
    "lease_id": "a1b2c3d4e5f6...",
    "expires_at": "2026-05-27T10:35:00Z",
    "env_vars": { ... }
  }
]
```

### 3.3 Get Slave Detail

```
GET /slaves/{slave_id}
```

### 3.4 Reserve Slave (예약 — 배타적 잠금 + 리스)

```
POST /slaves/{slave_id}/reserve
Content-Type: application/json

{
  "requester": "container-xyz",
  "vm_ip": "10.10.10.2",
  "ttl": 300
}
```

- `ttl` (선택, 기본 300초): 리스 유효기간. 범위: 60~7200초. 범위 밖이면 자동 clamp.
- 예약 즉시 `lease_id` 발급, `expires_at = now + ttl` 설정.
- VHS는 `lease_id`를 저장해 두고 주기적으로 `renew` 호출해야 함.

**성공 (200)**:
```json
{
  "id": "homey-0",
  "ip": "10.1.0.1",
  "status": "reserved",
  "requester": "container-xyz",
  "vm_ip": "10.10.10.2",
  "reserved_at": "2026-05-27T10:30:00Z",
  "lease_id": "a1b2c3d4e5f67890abcdef1234567890",
  "expires_at": "2026-05-27T10:35:00Z",
  "env_vars": { ... }
}
```

**실패 — 이미 예약됨 (409 Conflict)**:
```json
{
  "detail": {
    "message": "Slave already reserved",
    "requester": "other-container",
    "vm_ip": "10.10.10.41",
    "reserved_at": "2026-05-27T09:00:00Z"
  }
}
```

**실패 — 오프라인 (503)**:
```json
{
  "detail": "Slave is offline"
}
```

### 3.5 Renew Lease (리스 갱신)

```
POST /slaves/{slave_id}/renew
Content-Type: application/json

{
  "lease_id": "a1b2c3d4e5f67890abcdef1234567890",
  "ttl": 300
}
```

- `lease_id` (**필수**): reserve 시 발급받은 ID. 불일치하면 409.
- `ttl` (선택, 기본 300초): 새 유효기간. `expires_at = now + ttl`로 갱신.
- **VHS 권장 패턴**: 60초마다 renew 호출. TTL 300초이면 미갱신 시 최대 ~5분 내 자동 회수.

**성공 (200)**:
```json
{
  "id": "homey-0",
  "status": "reserved",
  "expires_at": "2026-05-27T10:40:00Z",
  ...
}
```

**실패 (409)**: reserved 아님 또는 lease_id 불일치.

### 3.6 Release Slave (해제)

```
POST /slaves/{slave_id}/release
Content-Type: application/json

{
  "lease_id": "a1b2c3d4e5f67890abcdef1234567890"
}
```

- `lease_id` (선택): 제공하면 소유권 검증 후 해제. 불일치 시 409.
- **body 없이 호출** (하위호환): 강제 release (admin, udev 용도).

**성공 (200)**: status → available, lease_id/expires_at null.

### 3.7 자동 회수 (Lease Expiry)

- Background sweeper가 30초마다 `expires_at < now(UTC)`인 slave를 자동 release.
- iptables 규칙 제거도 자동 수행.
- 브로커 재시작 시에도 부팅 직후 1회 sweep → DB에 남은 만료 리스 정리.
- **따라서 VHS가 크래시/네트워크 단절되어도 최대 TTL + 30초 내에 slave 회수.**

---

## 4. 예약 시 자동으로 일어나는 일

`POST /slaves/homey-0/reserve` 호출 시 (vm_ip: 10.10.10.2, slave_ip: 10.1.0.1):

```
1. DB 상태 업데이트: available → reserved
2. iptables 규칙 추가 (각 포트별):
   - DNAT:       10.10.10.2 → 10.1.0.1:{port}
   - MASQUERADE: 10.1.0.1:{port} 리턴 트래픽
3. 해당 포트 목록: 10000, 10002, 10003, 10005, 10006, 10007, 20006, 20024, 20025
```

`POST /slaves/homey-0/release` 호출 시:
```
1. iptables 규칙 제거 (위 규칙의 -D 버전)
2. DB 상태 업데이트: reserved → available
```

---

## 5. BYOH(VHS) 연동 방법

### 5.1 Homey OS 컨테이너 시작 시

```python
import asyncio
import httpx

BROKER_URL = "http://10.10.10.1:7100"

async def acquire_homey_slave(container_id: str, vm_ip: str = "10.10.10.2", ttl: int = 300):
    """사용 가능한 slave를 찾아 예약한다. lease_id를 반환."""
    async with httpx.AsyncClient() as client:
        # 1. 사용 가능한 slave 확인
        resp = await client.get(f"{BROKER_URL}/slaves")
        slaves = resp.json()
        available = [s for s in slaves if s["status"] == "available"]
        
        if not available:
            raise RuntimeError("No available Homey slaves")
        
        # 2. 첫 번째 available slave 예약
        slave = available[0]
        resp = await client.post(
            f"{BROKER_URL}/slaves/{slave['id']}/reserve",
            json={"requester": container_id, "vm_ip": vm_ip, "ttl": ttl}
        )
        
        if resp.status_code == 200:
            data = resp.json()
            # data["lease_id"]를 저장 → renew/release에 사용
            # data["env_vars"]를 docker-compose에 inject
            # data["expires_at"]로 만료 시각 확인
            return data
        elif resp.status_code == 409:
            raise RuntimeError(f"Slave already taken: {resp.json()}")
        else:
            resp.raise_for_status()


async def heartbeat_loop(slave_id: str, lease_id: str, interval: int = 60, ttl: int = 300):
    """주기적으로 renew 호출. VHS 메인 루프에서 background task로 실행."""
    async with httpx.AsyncClient() as client:
        while True:
            await asyncio.sleep(interval)
            resp = await client.post(
                f"{BROKER_URL}/slaves/{slave_id}/renew",
                json={"lease_id": lease_id, "ttl": ttl}
            )
            if resp.status_code != 200:
                break  # lease lost — slave 사용 중단 필요
```

### 5.2 Homey OS 컨테이너에서 slave 사용

예약 성공 후, 컨테이너 내부에서 slave IP로 직접 통신:

```python
# slave_ip = "10.1.0.1" (예약 응답에서 받은 IP)
# 포트 10000: Zigbee UART
# 포트 10002: Z-Wave UART
# 포트 10003: Thread (802.15.4)
# 등등...

import socket

# 예: Zigbee 연결
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("10.1.0.1", 10000))  # PVE broker가 iptables로 라우팅해줌
```

### 5.3 컨테이너 종료 시

```python
async def release_homey_slave(slave_id: str, lease_id: str):
    """정상 종료 시 lease_id와 함께 release. 소유권 검증됨."""
    async with httpx.AsyncClient() as client:
        await client.post(
            f"{BROKER_URL}/slaves/{slave_id}/release",
            json={"lease_id": lease_id}
        )
```

> **비정상 종료(크래시) 시**: release를 못 해도 TTL 만료 후 자동 회수됨.

---

## 6. Agent Platform 연동

Agent Platform(10.10.10.41)에서 디바이스 상태를 모니터링하거나 관리:

```python
# 전체 상태 확인
GET http://10.10.10.1:7100/slaves

# 특정 워크플로에서 slave가 필요한 경우
# → Agent Platform이 VHS에 slave 할당을 지시 (직접 broker 호출 가능)
POST http://10.10.10.1:7100/slaves/homey-0/reserve
{"requester": "agent-platform-workflow-123", "vm_ip": "10.10.10.2"}
```

---

## 7. 디바이스 자동 감지 (USB)

물리 Homey Pro를 PVE 호스트에 USB로 연결하면:

1. Linux에서 USB Ethernet 인터페이스(`usb0`, `usb1`) 자동 생성
2. udev 규칙이 이벤트 감지 → `on-usb-event.sh add usb0` 실행
3. 스크립트가 broker API 호출 → slave 자동 등록 (status: available)
4. USB 분리 시: `on-usb-event.sh remove usb0` → slave offline 처리

**별도 설정 없이 USB 꽂으면 바로 사용 가능.**

---

## 8. 포트 매핑 참조

소스 검증 출처: `homey-pro-linux/stages/stagehomey-dev/30-startup/files/usr/bin/slave-socat`

| 포트 | 용도 | 소스 디바이스 |
|------|------|--------------|
| 10000 | D-Bus (system bus) | `/var/run/dbus/system_bus_socket` |
| 10002 | Coprocessor Control UART | `/dev/ttyAMA2` (115200) |
| 10003 | Coprocessor Debug UART | `/dev/ttyAMA3` (115200) |
| 10004 | Zigbee UART | `/dev/ttyAMA4` (115200) |
| 20006 | GPIO 6 — CM4 Reset | `/sys/class/gpio/gpio6/value` |
| 20024 | GPIO 24 — Coprocessor Boot | `/sys/class/gpio/gpio24/value` |
| 20025 | GPIO 25 — Coprocessor Reset | `/sys/class/gpio/gpio25/value` |

> **이전 포트 목록 오류 수정**: `10005`, `10006`, `10007`은 존재하지 않음. `10004`(Zigbee) 추가.

### Homey USB 식별 정보

| 항목 | 값 | 비고 |
|------|------|------|
| **MAC (host_addr)** | `00:00:00:00:00:01` | udev 식별 기준 (하드코딩) |
| **VID:PID** | `0525:a4a2` | g_ether 기본값 |
| **Manufacturer** | `Athom B.V.` | |
| **Product** | `Homey Pro` | |
| **프로토콜** | RNDIS (g_ether) | |
| **Homey IP** | `10.1.0.1` (고정) | DHCP 서버 역할 |
| **호스트 IP** | `10.1.0.100` (DHCP 할당) | |

---

## 9. 에러 처리 가이드

| 상황 | HTTP Code | 대응 |
|------|-----------|------|
| Slave 없음 | 404 | slave ID 확인, /slaves로 목록 조회 |
| 이미 예약됨 | 409 | 응답의 requester/reserved_at 확인, 해당 사용자의 해제 대기 또는 강제 해제 요청 |
| lease_id 불일치 (renew/release) | 409 | 다른 사용자가 이미 예약 중이거나 lease가 만료됨 |
| Slave 오프라인 | 503 | USB 연결 확인, 디바이스 물리 상태 점검 |
| Broker 응답 없음 | Connection Error | PVE에서 `systemctl status pve-net-broker` 확인 |

---

## 10. 향후 확장 (Phase 3)

- **WebSocket 실시간 이벤트**: `WS /slaves/events` — 상태 변경 push 알림
- **다중 디바이스 타입**: Homey 외 다른 USB 디바이스도 같은 패턴으로 관리 가능
- **Web UI**: 디바이스 상태 대시보드
