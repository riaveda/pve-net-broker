# CLAUDE.md

이 저장소에서 Claude(=나)가 무엇을 하는 녀석이고, 어떤 작업을 어떻게 처리하는지에 대한 가이드입니다.
새 세션에서 이 파일을 읽으면 아래 워크플로를 바로 이어서 수행할 수 있습니다.

## 이 저장소(pve-net-broker)의 역할

PVE(Proxmox) 호스트를 **관리 노드**로 삼는 인프라 설정 저장소. 주로 L3/L4 계층 +
reverse-proxy VM 앱 설정의 원격 배포까지 담당합니다.

- **NAT** — VM↔인터넷 MASQUERADE, 서비스 포트 포워딩, VM별 SSH 포워딩
- **고정 IP** — ISC dhcpd 고정 IP 예약을 git으로 관리
- **USB 브로커링** — Homey Pro 배타적 할당(예약/해제)
- **iptables (전용 체인·수렴형)** — 정적/동적 NAT를 각자 전용 체인에 격리하고 apply마다
  flush→재적재해 "라이브==레포"로 수렴시킨다 (아래 "iptables 관리 방법론" 참조)
- **Reverse-Proxy 배포** — `swp-iot.lge.com` **nginx HTTP 라우팅**을 관리하고 SSH로 `10.10.10.42` VM에
  배포 (아래 3번). ※ 포털 UI(안내 홈페이지)는 별도 GitLab 레포로 분리됨(이 레포 아님).

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
4. **PVE 호스트 명령엔 `sudo`를 붙이지 않는다.** PVE 세션은 root라 `iptables`·`ifreload`·`pnbctl` 등
   모든 관리 명령이 그대로 실행된다. Claude가 PVE용 명령을 줄 때 `sudo`를 프리픽스하지 않는다.
   (`.42` reverse-proxy VM처럼 *비-root VM*에 배포하는 원격 명령의 `sudo`는 예외 — 거긴 riaveda 계정이라 필요.)

## iptables 관리 방법론 (전용 체인 + 수렴 재적재 — 항상 준수)

NAT 룰은 **built-in 체인(PREROUTING/POSTROUTING)에 직접 append 하지 않는다.** 관리 대상을
**전용 user chain**에 담고, base 체인엔 그 체인으로의 **jump 1개**만 둔 뒤, apply 때마다
**전용 체인을 flush 후 통째 재적재**한다. 그러면 apply 결과가 항상 레포와 동일하게 **수렴**한다
(idempotent). 체인 구성:

| 성격 | PREROUTING(DNAT) 체인 | POSTROUTING(MASQ) 체인 | 소유 |
|---|---|---|---|
| 정적(서비스 포워딩·SSH) | `PVE-NET-BROKER-STATIC` | `PVE-NET-BROKER-STATIC-POST` | `network/nat-rules.sh` |
| 동적(USB 예약) | `PVE-NET-BROKER` | `PVE-NET-BROKER-POST` | `src/iptables_manager.py` |

규칙:
- **정적 NAT 변경은 `nat-rules.sh` 만 고치고 `pnbctl nat reload`.** reload = `nat-rules.sh up` 직접
  호출(수렴). `ifreload -a` 로 안 돈다 — 변경감지가 훅 재실행을 스킵해 반영 누락·중복을 냈다.
- **built-in 체인에 직접 `-A` 하는 옛 방식 금지.** append/delete 개별 관리는 IP를 바꾸면 옛 룰을
  `-D` 로 못 지워(파라미터 불일치) 고아가 남고, reload마다 중복이 쌓여 드리프트한다.
- 정적·동적 체인은 **서로의 체인을 절대 flush/삭제하지 않는다** (완전 분리). 새 룰류를 추가하면
  자기 전용 체인 + base jump 1개 패턴을 그대로 따른다.

이유: 업계 정석(docker `DOCKER`·k8s `KUBE-SERVICES`·firewalld/ufw 전용 체인 + 원자적 재적재)과
동일. "라이브 == 레포" 수렴이 없으면 스테일·중복이 축적돼 first-match 로 정상 라우팅을 가린다
(2026-07-02 `.41→.6` 마이그레이션 시 옛 `.41:5000/5001` 고아가 위에서 이겨 refused 사고).

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

### 3. Reverse-Proxy(nginx 라우팅) 원격 배포

`/gitlab /build /agent /collab_search` 등 `swp-iot.lge.com` HTTP 경로 라우팅(nginx conf)을 이 레포에서
관리하고, **PVE를 관리 노드로 삼아 SSH로 reverse-proxy VM(`10.10.10.42`)에 배포**한다.

> ⚠️ **포털 UI(frontend)는 이제 이 레포 소관이 아니다** (2026-07 분리). 모듈 경계:
> - **IP 라우팅(L3/L4)** = PVE (`network/`) — 비공개
> - **HTTP 리버스프록시(nginx conf)** = `.42` / `riaveda` (이 레포 `reverse-proxy/nginx/`) — 비공개
> - **포털 UI(frontend)** = `.42` / `portal-frontend` 계정 → **GitLab private 레포 `riaveda/swp-iot-portal-frontend`** (Vite+React) — 공개 소관
>
> 포털 화면을 바꾸려면 → **GitLab 레포 소스 수정** 후 `.42 portal-frontend`에서 pull+`npm run build`.
> `portal-frontend`가 `~/portal` 에 clone → `~/portal/dist` 로 빌드·서빙한다.
> **이 레포에서는 라우팅(nginx conf)만** 다룬다 (frontend/html 폴더 없음).

- nginx conf 원본: `reverse-proxy/nginx/reverse-proxy.conf` (내부 IP 라우팅 — 인프라 소유·비공개)
- **`.42`의 심볼릭 구조:**
  ```
  /etc/nginx/sites-enabled/reverse-proxy.conf  → /home/riaveda/reverse-proxy/nginx/reverse-proxy.conf
  /var/www/reverse-proxy                       → /home/portal-frontend/portal/dist   (포털 빌드 결과)
  ```
  nginx conf 는 riaveda 홈, 포털 정적파일은 portal-frontend 홈을 각각 심볼릭으로 물린다.
- 배포: `pnbctl proxy deploy` →
  ① `riaveda@.42`로 레포 `nginx/`를 `/home/riaveda/reverse-proxy/nginx/`에 **rsync --delete** (권한 불필요)
  ② 원격 `sudo nginx -t` 검증 → 통과 시 `sudo systemctl reload nginx` (**reload만 root 필요**)
  ※ frontend/html 은 더 이상 배포하지 않는다 (포털은 portal-frontend가 자체 build/serve).
- env로 조정: `PROXY_HOST`(기본 10.10.10.42) / `PROXY_USER`(기본 **riaveda** — .42는 root 로그인 불가) /
  `PROXY_STAGE`(기본 /home/riaveda/reverse-proxy) / `PROXY_SUDO`(기본 "sudo", 필요 없으면 "")
- 전제:
  1. PVE→`.42` 무암호 SSH (riaveda), reload 무인화 `/etc/sudoers.d/reverse-proxy-reload`
  2. (포털 분리 1회 세팅) `.42`에서 `/var/www/reverse-proxy` 심볼릭을 portal-frontend dist로 repoint:
     `sudo ln -sfn /home/portal-frontend/portal/dist /var/www/reverse-proxy`
     + nginx가 홈을 통과하게 `chmod o+x /home/portal-frontend`

> IP/포트를 바꿀 때는 nat-rules.sh(포워딩)와 이 nginx conf(HTTP 라우팅)가 **함께** 맞아야 한다.

#### 3-1. HTTPS/HTTP2 인프라 — 준비만 됨(비활성)

사내 자체 CA + 단일 호스트(`swp-iot.lge.com`) 인증서로 `:443`(HTTP/2)을 켤 수 있는 **도구·템플릿·문서가
미리 준비돼 있으나 켜져 있지 않다**(기존 `:80` 서빙 무영향). 문서 둘: **운영 절차(어떻게 켜나) =
[`reverse-proxy/docs/tls-setup.md`](reverse-proxy/docs/tls-setup.md)** · **설계·사유(왜 이렇게) =
[`reverse-proxy/docs/https-transition-rationale.md`](reverse-proxy/docs/https-transition-rationale.md)**.

핵심만:
- **현재 비활성**: `tls-enabled/` 가 비어 있고 `.42`에 인증서도 없어 `:443` 블록이 안 뜬다 → `:80` 그대로.
- **왜 단일 호스트로 충분**: 전 서비스가 `swp-iot.lge.com/<path>` + PVE 관리 UI(`swp-iot.lge.com:8006`)
  — 호스트 하나. TLS 는 경로/포트 무관·호스트명만 매칭하므로 인증서 한 장이 전부 커버(와일드카드 불필요).
- **준비물**: `scripts/gen-certs.sh`(name-constrained 루트 CA + swp-iot.lge.com leaf 생성) · `_service-routes.conf`
  (`:80`·`:443` 공유 라우팅 단일 소스) · `tls-available/swp-iot.lge.com.conf`(:443 템플릿).
- **활성화**(필요 시): 인증서 생성·배치 → `tls-available/*.conf`를 `tls-enabled/`로 복사 → `nat-rules.sh`에
  `443:10.10.10.42:443` 추가 → `pnbctl nat reload && pnbctl proxy deploy`. (docs/tls-setup.md §5.)
- **키·인증서는 git 미포함**(`reverse-proxy/ssl/`·`tls-enabled/*.conf` 는 `.gitignore`).

### 4. USB(Homey) 브로커링 / API

FastAPI 서비스(`src/`)와 `pnbctl reserve/release`로 처리. 상세는 `README.md`, `docs/INTEGRATION.md`.

## 적용 명령 요약 (사용자용)

| 무엇 | 명령 (PVE 호스트) |
|------|-------------------|
| 고정 IP 변경 반영 | `git pull && pnbctl dhcp reload` |
| NAT/포워딩 변경 반영 | `git pull && pnbctl nat reload` |
| nginx 라우팅 반영 | `git pull && pnbctl proxy deploy` (SSH로 .42 nginx conf 배포+reload) |
| 포털 UI 반영 | (이 레포 아님) GitLab `swp-iot-portal-frontend` 수정 → `.42 portal-frontend`에서 `git pull && npm run build` |
| 타임존 통일 (호스트+전 VM/CT = Asia/Seoul) | `git pull && pnbctl tz apply` (멱등 — 새 VM 온보딩 후 1회. 재부팅 대비 아님) |
| 서비스 코드 반영 | `make deploy` (git pull + pip + restart) |

## 파일 지도

```
network/nat-rules.sh      정적 NAT + SSH 22XX 포워딩   (→ /etc/network/nat-rules.sh, symlink)
network/dhcpd.conf        DHCP base (안 건드림, include만)  (→ /etc/dhcp/dhcpd.conf, 복사)
network/dhcp-hosts.conf   고정 IP host 예약 ← VM 추가 시 여기만 수정  (→ /etc/dhcp/, 복사)
                          ※ dhcpd는 AppArmor로 /etc/dhcp 밖을 못 읽어 심볼릭 대신 복사.
                            `pnbctl dhcp reload`가 레포→/etc/dhcp 복사 후 검증·재시작.
reverse-proxy/nginx/      reverse-proxy.conf (HTTP 라우팅) → .42 nginx conf
                          ※ 포털 UI(frontend)는 이 레포에 없음 — 별도 GitLab 레포
                            riaveda/swp-iot-portal-frontend + .42 portal-frontend 계정 소관.
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

- **모든 수정은 `main`에 병합까지 완료한다.** 이 레포는 `main` 단일 브랜치로 운영한다 —
  작업 브랜치에서 개발하더라도 완료 시 반드시 `main`에 병합(fast-forward) 후 `main`을 푸시한다.
  변경을 피처 브랜치에만 남겨두지 않는다. (배포가 PVE의 `git pull`=main 기준이라, `main`에 없으면
  아무것도 반영되지 않는다.) 커밋 메시지는 명확하게 쓴다.
- 고정 IP는 항상 `dhcp-hosts.conf`에서 **빈 번호를 낮은 순으로** 배정한다 (요청에 특정 번호가 명시되면 그 번호 우선).
- base `dhcpd.conf`는 수정하지 않는다 (전역 옵션 + subnet + include 전용).
- 리버스 프록시/웹 등 다른 소스 소관은 이 레포에서 건드리지 않는다.
