# PVE Net Broker

PVE(Proxmox) 호스트에서 동작하는 네트워크 및 물리 디바이스 브로커.
BYOH 인프라의 NAT 관리, USB 디바이스 배타적 할당, 동적 포트 포워딩을 담당합니다.

## 기능

- **정적 NAT 관리** — VM↔인터넷 MASQUERADE, 서비스 포트 포워딩, SSH 포워딩
- **USB 디바이스 브로커링** — 물리 Homey Pro 자동 감지 및 exclusive access 관리
- **동적 iptables** — 예약 시 VM↔디바이스 포트 포워딩 자동 생성/제거
- **배타적 잠금** — UART/안테나 자원의 single-master 보장

## 아키텍처

```
PVE Host (10.10.10.1:7100)
├── pve-net-broker (FastAPI)     ← 이 서비스
├── nat-rules.sh                 ← 정적 NAT (부팅 시 적용)
├── iptables PVE-NET-BROKER 체인 ← 동적 규칙 (런타임)
└── udev 규칙                    ← USB 자동 감지
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
│   └── nat-rules.sh         # 정적 NAT 규칙 (→ /etc/network/nat-rules.sh)
├── systemd/
│   ├── pve-net-broker.service  # systemd unit (→ /etc/systemd/system/)
│   └── pve-net-broker.env      # 환경변수 (.gitignore됨)
├── udev/
│   └── 99-homey-slave.rules   # USB 감지 규칙 (→ /etc/udev/rules.d/)
├── scripts/
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
/etc/network/nat-rules.sh           → /opt/pve-net-broker/network/nat-rules.sh
/etc/systemd/system/pve-net-broker.service → /opt/pve-net-broker/systemd/pve-net-broker.service
/etc/udev/rules.d/99-homey-slave.rules     → /opt/pve-net-broker/udev/99-homey-slave.rules
```

**모든 설정의 Single Source of Truth는 이 git 레포입니다.**

## API

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 서비스 상태 |
| GET | `/slaves` | 전체 디바이스 목록 |
| GET | `/slaves/{id}` | 특정 디바이스 상세 |
| POST | `/slaves/{id}/reserve` | 배타적 예약 |
| POST | `/slaves/{id}/release` | 해제 |

상세 API 명세: [docs/INTEGRATION.md](docs/INTEGRATION.md)

## 운영 명령

```bash
make status   # 서비스 상태 + health API 확인
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
ifreload -a   # nat-rules.sh 재실행
```

## 라이선스

Internal use only.
