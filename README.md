# PVE Net Broker

PVE(Proxmox) 호스트를 관리 노드로 하는 네트워크 및 물리 디바이스 브로커.
NAT/포워딩·DHCP 고정 IP·HTTP 리버스프록시(nginx) 라우팅·USB 디바이스 배타 할당을 담당합니다.

## 기능

- **정적 NAT 관리** — VM↔인터넷 MASQUERADE, 서비스 포트 포워딩, SSH 포워딩
- **고정 IP 관리** — DHCP(ISC dhcpd) 고정 IP 예약을 git으로 관리
- **HTTP 리버스프록시 라우팅** — `swp-iot.lge.com/<경로>` → 내부 서비스 nginx 라우팅 conf를
  관리하고 `.42` 리버스프록시 VM에 배포 (`pnbctl proxy deploy`)
- **USB 디바이스 브로커링** — 물리 Homey Pro 자동 감지 및 exclusive access 관리
- **동적 iptables** — 예약 시 VM↔디바이스 포트 포워딩 자동 생성/제거
- **배타적 잠금** — UART/안테나 자원의 single-master 보장

## 담당 범위 (Scope)

이 레포는 **설정의 단일 원본 + 제어 CLI**이고, 실제 동작은 각 노드에서 일어난다.

| 담당 | 계층/성격 | 위치 | 명령 |
|---|---|---|---|
| NAT·포트포워딩·SSH 22XX | L3/L4 IP 라우팅 | `network/nat-rules.sh` (PVE) | `pnbctl nat reload` |
| DHCP 고정 IP | IP 할당 | `network/dhcp-hosts.conf` (PVE) | `pnbctl dhcp reload` |
| HTTP 리버스프록시 라우팅 | L7 (nginx conf 관리·배포) | `reverse-proxy/nginx/` → `.42` | `pnbctl proxy deploy` |
| USB(Homey) 브로커링 | 장치 배타 할당 (FastAPI) | `src/` (PVE) | `pnbctl reserve/release` |

**담당하지 않는 것:**
- **포털 UI(안내 홈페이지, Vite+React)** — 2026-07 별도 분리됨. 소스는 사내 GitLab private 레포
  **`riaveda/swp-iot-portal-frontend`**, `.42`의 **`portal-frontend`** 계정이 clone→build→serve 한다.
  이 레포는 그 앞단 **HTTP 라우팅(nginx conf)만** 관리한다.
- 라우팅 대상 서비스 *자체*(GitLab, Build-Platform, Agent-Platform 앱 등) — 각 VM/소스 소관.

## 아키텍처

```
PVE Host (10.10.10.1:7100)  ── 관리 노드
├── pve-net-broker (FastAPI)     ← 이 서비스 (USB 브로커 API)
├── nat-rules.sh                 ← 정적 NAT (부팅 시 적용)
├── iptables PVE-NET-BROKER 체인 ← 동적 규칙 (런타임)
├── dhcpd (고정 IP)              ← DHCP 예약
├── udev 규칙                    ← USB 자동 감지
└── pnbctl proxy deploy ──rsync/ssh──▶ .42 리버스프록시 VM (nginx)
                                         ├── nginx conf   ← riaveda (이 레포가 배포)
                                         └── 포털 UI(dist) ← portal-frontend 계정
                                                             (GitLab swp-iot-portal-frontend, 별도 소관)
```

## 설치

### 요구사항

- PVE 호스트 (Proxmox VE)
- Python 3.11+
- iptables
- root 권한

### 설치 위치

```
/opt/pve-net-broker/    ← git clone 위치 (고정)
```

### 최초 설치

```bash
# 1. Clone
cd /opt
git clone <repo-url> pve-net-broker
cd pve-net-broker

# 2. Install (venv 생성, systemd 등록, symlink 설정)
make install
```

`make install`이 수행하는 작업:
- `/opt/pve-net-broker/.venv/` 에 Python 가상환경 생성
- pip 의존성 설치
- `/etc/systemd/system/pve-net-broker.service` → 심볼릭 링크
- `/etc/udev/rules.d/99-homey-slave.rules` → 심볼릭 링크
- `/etc/network/nat-rules.sh` → 심볼릭 링크 (기존 파일 백업)
- `/etc/dhcp/dhcpd.conf`, `/etc/dhcp/dhcp-hosts.conf` → **복사** (기존 파일 백업)
  - dhcpd는 AppArmor로 `/etc/dhcp` 밖을 못 읽어 심볼릭 링크가 아닌 복사 사용
- systemd 서비스 활성화 및 시작

### 배포 (업데이트)

```bash
cd /opt/pve-net-broker
make deploy
# = git pull + pip install + systemctl restart
```

### 제거

```bash
make uninstall
```

## 프로젝트 구조

```
pve-net-broker/
├── src/
│   ├── main.py              # FastAPI 엔트리포인트
│   ├── routes.py            # API 라우트
│   ├── models.py            # Pydantic 모델
│   ├── state.py             # SQLite 상태 영속화
│   ├── iptables_manager.py  # 동적 iptables 규칙 관리
│   └── config.py            # 설정
├── network/
│   ├── nat-rules.sh         # 정적 NAT 규칙 (→ /etc/network/nat-rules.sh)
│   ├── dhcpd.conf           # DHCP base 설정 (→ /etc/dhcp/dhcpd.conf)
│   └── dhcp-hosts.conf      # 고정 IP host 예약 (dhcpd.conf가 include)
├── systemd/
│   ├── pve-net-broker.service  # systemd unit (→ /etc/systemd/system/)
│   └── pve-net-broker.env      # 환경변수 (.gitignore됨)
├── udev/
│   └── 99-homey-slave.rules   # USB 감지 규칙 (→ /etc/udev/rules.d/)
├── scripts/
│   ├── pnbctl               # CLI 제어 도구 (→ /usr/local/bin/pnbctl)
│   ├── install.sh           # 초기 설치
│   ├── uninstall.sh         # 제거
│   ├── deploy.sh            # git pull + restart
│   └── on-usb-event.sh      # udev에서 호출하는 USB 이벤트 핸들러
├── docs/
│   └── INTEGRATION.md       # AI 에이전트 연동 가이드
├── tests/
├── pyproject.toml
├── Makefile
└── .gitignore
```

## 심볼릭 링크 구조

설치 후 시스템 파일과의 관계:

```
/etc/network/nat-rules.sh           → /opt/pve-net-broker/network/nat-rules.sh   (symlink)
/etc/systemd/system/pve-net-broker.service → /opt/pve-net-broker/systemd/pve-net-broker.service (symlink)
/etc/udev/rules.d/99-homey-slave.rules     → /opt/pve-net-broker/udev/99-homey-slave.rules (symlink)
/usr/local/bin/pnbctl                      → /opt/pve-net-broker/scripts/pnbctl (symlink)

/etc/dhcp/dhcpd.conf        ← copy of network/dhcpd.conf       (dhcpd는 AppArmor로 심볼릭 불가)
/etc/dhcp/dhcp-hosts.conf   ← copy of network/dhcp-hosts.conf  (dhcpd.conf가 include)
```

> DHCP만 예외로 **복사**입니다. dhcpd는 AppArmor 프로파일로 `/etc/dhcp` 밖(예: `/opt/...`)을
> 읽지 못하므로 심볼릭 링크가 거부됩니다. `pnbctl dhcp reload`가 레포 파일을 `/etc/dhcp`로
> 복사한 뒤 검증·재시작합니다.

**모든 설정의 Single Source of Truth는 이 git 레포입니다.**

## API 명세

**Base URL**: `http://10.10.10.1:7100` (vmbr1 내부 VM에서 접근)

### Public Endpoints

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 서비스 상태 |
| GET | `/slaves` | 전체 디바이스 목록 + env_vars |
| GET | `/slaves/{id}` | 특정 디바이스 상세 + env_vars |
| POST | `/slaves/{id}/reserve` | 배타적 예약 (iptables 자동 설정) |
| POST | `/slaves/{id}/release` | 해제 (iptables 자동 제거) |

### Internal Endpoints (PVE 호스트 내부용)

| Method | Path | 설명 |
|--------|------|------|
| POST | `/internal/slaves/register` | USB 연결 시 slave 등록 |
| POST | `/internal/slaves/{id}/unregister` | USB 분리 시 offline 처리 |

### 응답 예시

#### `GET /slaves`

```json
[
  {
    "id": "homey-0",
    "ip": "10.1.0.1",
    "status": "available",
    "requester": null,
    "vm_ip": null,
    "reserved_at": null,
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
  }
]
```

#### `POST /slaves/{id}/reserve`

Request:
```json
{"requester": "container-xyz", "vm_ip": "10.10.10.2"}
```

Success (200):
```json
{
  "id": "homey-0",
  "ip": "10.1.0.1",
  "status": "reserved",
  "requester": "container-xyz",
  "vm_ip": "10.10.10.2",
  "reserved_at": "2026-05-27T10:30:00Z",
  "env_vars": { ... }
}
```

Conflict (409) — 이미 다른 곳에서 사용 중:
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

#### `POST /internal/slaves/register`

Request (udev 스크립트가 호출):
```json
{"id": "homey-0", "ip": "10.1.0.1", "usb_interface": "usb0"}
```

### VHS에서 사용하는 흐름

```python
import httpx

BROKER = "http://10.10.10.1:7100"

# 1. 사용 가능한 slave 확인
resp = await httpx.AsyncClient().get(f"{BROKER}/slaves")
slaves = [s for s in resp.json() if s["status"] == "available"]

# 2. slave 예약
resp = await httpx.AsyncClient().post(
    f"{BROKER}/slaves/{slaves[0]['id']}/reserve",
    json={"requester": "my-container", "vm_ip": "10.10.10.2"}
)
slave = resp.json()

# 3. env_vars를 docker-compose.override.yml에 inject
#    slave["env_vars"]를 그대로 environment: 에 넣으면 됨

# 4. 컨테이너 종료 시 해제
await httpx.AsyncClient().post(f"{BROKER}/slaves/{slave['id']}/release")
```

### OpenAPI (Swagger) 문서

서비스 실행 중일 때 자동 생성:
- Swagger UI: http://10.10.10.1:7100/docs
- OpenAPI JSON: http://10.10.10.1:7100/openapi.json

상세 연동 가이드: [docs/INTEGRATION.md](docs/INTEGRATION.md)

## 운영 명령

### pnbctl (CLI 제어 도구)

어디서든 `pnbctl` 명령으로 서비스를 제어할 수 있습니다:

```bash
pnbctl status                          # 서비스 상태 + slave 요약
pnbctl slaves                          # 전체 slave 목록 (테이블)
pnbctl slave homey-0                   # 특정 slave 상세 정보
pnbctl reserve homey-0 container-1 10.10.10.2   # slave 예약
pnbctl release homey-0                 # slave 해제
pnbctl logs                            # 최근 로그 50줄
pnbctl logs -f                         # 실시간 로그 follow
pnbctl restart                         # 서비스 재시작
pnbctl nat reload                      # 정적 NAT 규칙 리로드 (ifreload -a)
pnbctl dhcp reload                     # 고정 IP 설정 검증 후 리로드 (isc-dhcp-server)
pnbctl version                         # 버전 확인
```

출력 예시:
```
$ pnbctl status
PVE Net Broker
  Service:  active
  API:      responding
  Version:  0.1.0
  Slaves:   2 total, 1 available, 1 reserved

$ pnbctl slaves
ID           IP             STATUS       REQUESTER            VM IP
------------------------------------------------------------------------
homey-0      10.1.0.1       available    -                    -
homey-1      10.1.1.1       reserved     container-xyz        10.10.10.2
```

### make 타겟

```bash
make status   # = pnbctl status
make logs     # 로그 실시간 확인
make restart  # 서비스 재시작
make deploy   # git pull + restart
make test     # 테스트 실행
```

## 환경변수

`systemd/pve-net-broker.env` (`.gitignore` 됨, 직접 생성 필요):

```env
API_HOST=0.0.0.0
API_PORT=7100
LOG_LEVEL=info
STATE_DB_PATH=/opt/pve-net-broker/data/state.db
RESERVATION_TTL=7200
```

## NAT 규칙 수정

`network/nat-rules.sh`를 수정 후:

```bash
git add -A && git commit -m "Add port forwarding for new service"
git push
# PVE에서:
ifreload -a   # nat-rules.sh 재실행 (= pnbctl nat reload)
```

## 고정 IP 추가 (새 VM)

고정 IP 예약은 **`network/dhcp-hosts.conf` 한 곳**에서만 관리합니다.
(`network/dhcpd.conf` base는 이 파일을 `include`만 하므로 건드릴 필요 없음.)

새 VM에 고정 IP를 주려면 `dhcp-hosts.conf`에 host 블록을 추가:

```
host <이름> {
  hardware ethernet <VM MAC>;
  fixed-address 10.10.10.<번호>;
  option domain-name-servers 10.231.3.11;
  option routers 10.10.10.1;
  option subnet-mask 255.255.255.0;
  option broadcast-address 10.10.10.255;
}
```

적용:

```bash
git add -A && git commit -m "Add fixed IP for <이름>"
git push
# PVE에서:
cd /opt/pve-net-broker && git pull && pnbctl dhcp reload
```

`pnbctl dhcp reload`는 `dhcpd -t`로 문법을 먼저 검증한 뒤 문제가 없을 때만
`isc-dhcp-server`를 재시작합니다 (오류 시 재시작하지 않고 중단).

## 라이선스

Internal use only.
