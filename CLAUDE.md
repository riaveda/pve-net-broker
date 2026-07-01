# CLAUDE.md

이 저장소에서 Claude(=나)가 무엇을 하는 녀석이고, 어떤 작업을 어떻게 처리하는지에 대한 가이드입니다.
새 세션에서 이 파일을 읽으면 아래 워크플로를 바로 이어서 수행할 수 있습니다.

## 이 저장소(pve-net-broker)의 역할

PVE(Proxmox) 호스트를 **관리 노드**로 삼는 인프라 설정 저장소. 주로 L3/L4 계층 +
reverse-proxy VM 앱 설정의 원격 배포까지 담당합니다.

- **NAT** — VM↔인터넷 MASQUERADE, 서비스 포트 포워딩, VM별 SSH 포워딩
- **고정 IP** — ISC dhcpd 고정 IP 예약을 git으로 관리
- **USB 브로커링** — Homey Pro 배타적 할당(예약/해제)
- **동적 iptables** — 디바이스 예약 시 포트 포워딩 자동 생성/제거
- **Reverse-Proxy 배포** — `swp-iot.lge.com` 안내 홈페이지 + nginx 라우팅을 관리하고
  SSH로 `10.10.10.42` VM에 배포 (아래 3번)

**하지 않는 것:** 라우팅 대상 서비스 *자체*(GitLab, Build-Platform, Agent-Platform 앱 등).
그 앱들은 각자 VM/소스 소관 — 이 저장소는 그 앞단의 프록시·포워딩·IP만 다룬다.

## 개발 방법론 (핵심 원칙)

1. **이 git 레포가 모든 설정의 Single Source of Truth다.** 시스템/원격 파일을 직접 고치지 않고,
   **항상 레포에서 수정 → 커밋/푸시**한다. 시스템 파일은 레포로 연결된다:
   - 심볼릭 링크: `nat-rules.sh`, systemd, udev, pnbctl
   - 복사: dhcp (dhcpd가 AppArmor로 `/etc/dhcp` 밖을 못 읽어 심볼릭 불가 → `pnbctl`이 복사)
   - 원격 rsync: reverse-proxy (`.42` VM 홈 폴더가 nginx에 심볼릭으로 물려 있음)
2. **적용은 사용자가 PVE에서 `pnbctl` 한 명령으로.** (`git pull && pnbctl <...>`) — 아래 요약표 참조.
   각 reload 명령은 **적용 전 검증**(`dhcpd -t`, `nginx -t`)을 하고 통과 시에만 반영한다.
3. **Claude(나)는 레포만 수정하고, 사용자에게 적용 명령·주의점을 항상 안내한다.**
   비밀번호/자격증명은 받지 않는다 (sudo 비번은 사용자가 직접 입력하거나 NOPASSWD로 사전 위임).

## 내가(Claude) 처리하는 작업

### 1. 새 VM 고정 IP 할당  ← 가장 자주 요청됨

사용자가 **이름 + MAC 주소**만 주면 내가:

1. `network/dhcp-hosts.conf`에서 **현재 사용 중인 옥텟을 스캔**하고, **가장 낮은 빈 번호를 순서대로 자동 배정**한다.
   (모든 VM이 고정 IP를 쓰므로, 사용자는 IP 번호를 지정하지 않아도 된다.)
2. MAC 중복 여부를 확인한다 (중복이면 중단하고 알린다).
3. `dhcp-hosts.conf`에 host 블록을 추가한다:
   ```
   host <이름> {
     hardware ethernet <MAC>;
     fixed-address 10.10.10.<빈번호>;
     option domain-name-servers 10.231.3.11;
     option routers 10.10.10.1;
     option subnet-mask 255.255.255.0;
     option broadcast-address 10.10.10.255;
   }
   ```
4. 커밋 후 지정 브랜치로 푸시한다.

**사용자는 그다음 PVE 호스트에서 이것만 하면 된다:**
```bash
cd /opt/pve-net-broker && git pull && pnbctl dhcp reload
```
`pnbctl dhcp reload`가 `dhcpd -t`로 문법을 검증한 뒤 통과 시에만 `isc-dhcp-server`를 재시작한다.

**SSH 접속은 별도 작업 불필요 (자동):**
IP가 `10.10.10.N`이면 `nat-rules.sh`가 외부포트 `22NN → 10.10.10.N:22`를 이미 매핑한다.
예) `.6` VM → `ssh -p 2206 ...`. (`network/nat-rules.sh`의 `seq 2 50` 루프)

> ⚠️ 자동 SSH/IP 범위는 **`.2 ~ .50`**. `.51` 이상을 쓰려면 `nat-rules.sh`의 루프 상한과
> `dhcpd.conf`의 `subnet ... range`를 함께 늘려야 한다.

### 2. 서비스 포트 포워딩 추가

외부포트 → VM 서비스로 노출하려면 `network/nat-rules.sh`의 `SERVICES` 배열에
`"외부포트:10.10.10.N:내부포트"` 한 줄 추가 → 커밋/푸시 → PVE에서 `pnbctl nat reload`(=`ifreload -a`).

### 3. Reverse-Proxy(홈페이지 + 라우팅) 원격 배포

`swp-iot.lge.com` 안내 홈페이지와 `/gitlab /build /agent` nginx 라우팅을 이 레포에서 관리하고,
**PVE를 관리 노드로 삼아 SSH로 reverse-proxy VM(`10.10.10.42`)에 배포**한다.

- **프론트엔드는 Vite + React** (`reverse-proxy/frontend/` 가 소스):
  - 소스 수정 → `cd reverse-proxy/frontend && npm run build` → 산출물이 `reverse-proxy/html/` 로 나감
  - `html/`(빌드 결과)은 **git에 커밋**한다 → 배포는 정적 파일 rsync라 `.42`에 Node 불필요
  - Claude가 프론트 수정 시 **반드시 build 후 html/까지 커밋**한다 (안 하면 서버에 stale 반영)
  - 서비스 카드 추가/변경은 `frontend/src/services.js` 배열만 수정
- nginx conf 원본: `reverse-proxy/nginx/reverse-proxy.conf`
- **`.42`의 심볼릭 구조 (핵심 — 이래서 파일 배포에 sudo가 필요 없음):**
  ```
  /var/www/reverse-proxy                       → /home/riaveda/reverse-proxy/html
  /etc/nginx/sites-enabled/reverse-proxy.conf  → /home/riaveda/reverse-proxy/nginx/reverse-proxy.conf
  ```
  nginx가 riaveda 홈 폴더를 직접 물고 있으므로, 그 폴더에 rsync만 하면 즉시 반영된다.
- 배포: `pnbctl proxy deploy` →
  ① `riaveda@.42`로 레포 `html/`·`nginx/`를 `/home/riaveda/reverse-proxy/`에 **rsync --delete** (권한 불필요)
     → `--delete`라 레포에서 지운 파일은 서버에서도 제거 (레포=서버 완전 미러)
  ② 원격 `sudo nginx -t` 검증 → 통과 시 `sudo systemctl reload nginx` (**reload만 root 필요**)
- env로 조정: `PROXY_HOST`(기본 10.10.10.42) / `PROXY_USER`(기본 **riaveda** — .42는 root 로그인 불가) /
  `PROXY_STAGE`(기본 /home/riaveda/reverse-proxy) / `PROXY_SUDO`(기본 "sudo", 필요 없으면 "")
- 전제 (둘 다 1회 세팅, 완료됨):
  1. PVE→`.42` 무암호 SSH: `ssh-copy-id riaveda@10.10.10.42`
  2. reload 무인화: `.42`의 `/etc/sudoers.d/reverse-proxy-reload` 에
     `riaveda ALL=(root) NOPASSWD: /usr/sbin/nginx -t, /usr/bin/systemctl reload nginx`
     (미설정 시 `pnbctl proxy deploy`가 sudo 비번을 대화형으로 물어봄 — 비번은 사용자가 직접 입력하며, Claude는 비번을 받지 않는다.)

> 이건 L3/L4 범위를 넘어 **원격 VM 앱 설정 배포**까지 겸하는 부분이라 `reverse-proxy/`로 분리해 둔다.
> IP/포트를 바꿀 때는 nat-rules.sh(포워딩)와 이 nginx conf(HTTP 라우팅)가 **함께** 맞아야 한다.

### 4. USB(Homey) 브로커링 / API

FastAPI 서비스(`src/`)와 `pnbctl reserve/release`로 처리. 상세는 `README.md`, `docs/INTEGRATION.md`.

## 적용 명령 요약 (사용자용)

| 무엇 | 명령 (PVE 호스트) |
|------|-------------------|
| 고정 IP 변경 반영 | `git pull && pnbctl dhcp reload` |
| NAT/포워딩 변경 반영 | `git pull && pnbctl nat reload` |
| 홈페이지/프록시 반영 | `git pull && pnbctl proxy deploy` (SSH로 .42 배포+reload) |
| 서비스 코드 반영 | `make deploy` (git pull + pip + restart) |

## 파일 지도

```
network/nat-rules.sh      정적 NAT + SSH 22XX 포워딩   (→ /etc/network/nat-rules.sh, symlink)
network/dhcpd.conf        DHCP base (안 건드림, include만)  (→ /etc/dhcp/dhcpd.conf, 복사)
network/dhcp-hosts.conf   고정 IP host 예약 ← VM 추가 시 여기만 수정  (→ /etc/dhcp/, 복사)
                          ※ dhcpd는 AppArmor로 /etc/dhcp 밖을 못 읽어 심볼릭 대신 복사.
                            `pnbctl dhcp reload`가 레포→/etc/dhcp 복사 후 검증·재시작.
reverse-proxy/frontend/   안내 홈페이지 소스 (Vite+React) ← 여기서 개발, npm run build
reverse-proxy/html/       빌드 산출물(커밋됨)         → .42:/var/www/reverse-proxy
reverse-proxy/nginx/      reverse-proxy.conf (라우팅) → .42 nginx conf
scripts/pnbctl            CLI (dhcp reload / nat reload / proxy deploy / reserve ...)
src/                      FastAPI 브로커
```

## 작업 시 반드시 해줘야 하는 가이드 (중요)

포워딩/IP를 바꿀 때는 **코드만 고치고 끝내지 말고, 아래를 항상 사용자에게 먼저 짚어준다.**
이걸 빠뜨리면 "일부만 옮겨져서 서비스가 반쪽만 동작"하는 사고가 난다.

1. **공용 서버 경고 — 필요한 줄만 옮긴다.**
   한 IP(VM)가 여러 서비스를 같이 돌리는 경우가 많다. 대상 서비스 줄만 바꾸고 나머지는 그대로 둔다.
   > 예) `10.10.10.41`(homey-cicd)은 **Build-Platform(4050/4051)도 같이** 돌린다.
   > Agent-Platform을 옮길 땐 `nat-rules.sh`의 Agent-Platform 4줄(5000/5001/5003/5004)만 `.6`으로 바꾸고,
   > **Build-Platform 줄은 `.41`에 그대로 둬야 한다.**
   → 작업 전 대상 IP가 어떤 서비스들을 공유하는지 `nat-rules.sh`에서 확인하고, 안 건드릴 줄을 명시한다.

2. **이 레포 밖(다른 소스) 의존 지점을 반드시 알려준다.**
   포트 포워딩(`nat-rules.sh`)만 바꿔서는 끝이 아니다. 같은 서비스가 다른 소스에서도 IP를 참조하면
   그쪽도 바꿔야 실제로 넘어간다. **이 레포에서 커밋할 수 없는 부분은 "여기 소관 아님 + 어디를 어떻게 고쳐야 함"을 분명히 안내한다.**
   > 예) `swp-iot.lge.com/agent` HTTP 라우팅은 리버스 프록시 VM `10.10.10.42`의 `reverse-proxy.conf`:
   > ```nginx
   > location /agent {
   >     proxy_pass http://10.10.10.41:5000;   # ← 이것도 .6으로 바꿔야 함
   > ```
   > 이건 별도 소스라 이 레포에서 커밋 못 함 → 사용자에게 "그 VM에서 직접 수정 필요"라고 안내한다.

3. **파생되어 자동 처리되는 부분은 "안 해도 됨"을 알려준다.**
   불필요한 수동 작업을 막는다.
   > 예) SSH `22XX → .XX:22`는 `nat-rules.sh` 루프가 IP 기준으로 자동 생성 → 변경 불필요.

4. **적용 명령을 항상 함께 준다.** (IP → `git pull && pnbctl dhcp reload`, 포워딩 → `... pnbctl nat reload`)

## 작업 규칙

- 지정된 개발 브랜치에서만 작업하고, 커밋 메시지는 명확하게, 완료 시 푸시한다.
- 고정 IP는 항상 `dhcp-hosts.conf`에서 **빈 번호를 낮은 순으로** 배정한다 (요청에 특정 번호가 명시되면 그 번호 우선).
- base `dhcpd.conf`는 수정하지 않는다 (전역 옵션 + subnet + include 전용).
- 리버스 프록시/웹 등 다른 소스 소관은 이 레포에서 건드리지 않는다.
