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
    "reserved_at": null
  },
  {
    "id": "homey-1",
    "ip": "10.1.1.1",
    "status": "reserved",
    "requester": "container-xyz",
    "vm_ip": "10.10.10.2",
    "reserved_at": "2026-05-27T10:30:00Z"
  }
]
```

### 3.3 Get Slave Detail

```
GET /slaves/{slave_id}
```

### 3.4 Reserve Slave (예약 — 배타적 잠금)

```
POST /slaves/{slave_id}/reserve
Content-Type: application/json

{
  "requester": "container-xyz",
  "vm_ip": "10.10.10.2"
}
```

**성공 (200)**:
```json
{
  "id": "homey-0",
  "ip": "10.1.0.1",
  "status": "reserved",
  "requester": "container-xyz",
  "vm_ip": "10.10.10.2",
  "reserved_at": "2026-05-27T10:30:00Z"
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

### 3.5 Release Slave (해제)

```
POST /slaves/{slave_id}/release
```

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
import httpx

BROKER_URL = "http://10.10.10.1:7100"

async def acquire_homey_slave(container_id: str, vm_ip: str = "10.10.10.2"):
    """사용 가능한 slave를 찾아 예약한다."""
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
            json={"requester": container_id, "vm_ip": vm_ip}
        )
        
        if resp.status_code == 200:
            return resp.json()  # {"id": "homey-0", "ip": "10.1.0.1", ...}
        elif resp.status_code == 409:
            raise RuntimeError(f"Slave already taken: {resp.json()}")
        else:
            resp.raise_for_status()
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
async def release_homey_slave(slave_id: str):
    async with httpx.AsyncClient() as client:
        await client.post(f"{BROKER_URL}/slaves/{slave_id}/release")
```

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

| 포트 | 용도 |
|------|------|
| 10000 | Zigbee UART |
| 10002 | Z-Wave UART |
| 10003 | Thread (802.15.4) |
| 10005 | IR Blaster |
| 10006 | BLE (Bluetooth Low Energy) |
| 10007 | Sub-GHz |
| 20006 | Homey internal service |
| 20024 | Homey internal service |
| 20025 | Homey internal service |

---

## 9. 에러 처리 가이드

| 상황 | HTTP Code | 대응 |
|------|-----------|------|
| Slave 없음 | 404 | slave ID 확인, /slaves로 목록 조회 |
| 이미 예약됨 | 409 | 응답의 requester/reserved_at 확인, 해당 사용자의 해제 대기 또는 강제 해제 요청 |
| Slave 오프라인 | 503 | USB 연결 확인, 디바이스 물리 상태 점검 |
| Broker 응답 없음 | Connection Error | PVE에서 `systemctl status pve-net-broker` 확인 |

---

## 10. 향후 확장 (Phase 2/3)

- **WebSocket 실시간 이벤트**: `WS /slaves/events` — 상태 변경 push 알림
- **TTL 자동 해제**: 2시간 미활동 시 자동 release
- **다중 디바이스 타입**: Homey 외 다른 USB 디바이스도 같은 패턴으로 관리 가능
- **Web UI**: 디바이스 상태 대시보드
