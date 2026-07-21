# HTTPS / HTTP/2 — 사내 CA (준비 완료 · 비활성) + 활성화 가이드 (인수인계 문서)

내부 `.lge.com` 서비스에 **브라우저-신뢰 HTTPS + HTTP/2** 를 *언제든 켤 수 있도록 미리 준비*해 둔
도구·설정과, 필요해질 때의 활성화 절차를 담는다. 이 문서 하나로 처음 인수받는 사람이
준비·활성화·갱신·확장·장애대응까지 할 수 있도록 자기완결로 작성한다.

> **현재 상태(중요): 아무것도 켜져 있지 않다.** 이 레포엔 *생성 스크립트 + nginx :443 템플릿 + 이 문서*만
> 있고, 실 서빙(`:80`)은 종전과 동일하다. `:443` 은 인증서 배치 + `tls-enabled/` 활성화가 있어야
> 비로소 켜진다(§4). 즉 지금은 **기존 서비스에 영향 0**.

---

## 1. 왜 미리 준비하나 (배경)

- **연결상한(HTTP/2) 트랙 자체는 미채택**(급성 아님·브라우저 전용·전 PC 루트 배포 비용) — 판단 이력은
  box WIP `doc/wip/http2-connection-limit.md`.
- 다만 **"필요해질 때 즉시 켤 수 있는 인프라(사내 CA·와일드카드 인증서·가이드)를 미리 만들어 두는 것"**
  은 기존 서비스에 무영향이고, 나중에 HTTPS(HTTP/2)·PVE 관리 UI 인증서 경고 제거 등이 필요할 때
  준비 시간을 0 으로 만든다. → 그래서 *생성·문서화까지만* 선행한다(활성화는 그때).

## 2. 구조 (한눈에)

```
[내부 CA 1개]  ── name-constrained: .lge.com 만 서명 가능(유출돼도 타 도메인 위장 불가)
    │  이 루트로 와일드카드 leaf 발급
    └─ leaf: *.lge.com  →  swp-iot.lge.com·pve.lge.com 등 서브도메인 전부 한 장으로 커버
[루트 인증서(공개, rootCA.crt)]  →  팀 PC 신뢰저장소에 1회 설치 → 이 CA 발급 전부 자동 신뢰
```

- **TLS 종단은 리버스프록시(.42 nginx :443)** 에서. 브라우저 ↔ .42 는 https(h2), .42 ↔ 백엔드 VM 은
  기존대로 내부 http. 백엔드(gitlab·build·agent)는 바꿀 필요 없다.
- **키 관리**: 루트/leaf 개인키는 git 에 안 올린다(`reverse-proxy/ssl/` 는 `.gitignore`). 레포엔
  *생성 스크립트*·*nginx 설정*만, 실제 키는 PVE/.42 로컬에만.

## 3. 레포에 있는 것 (파일 지도)

| 파일 | 역할 | 상태 |
|---|---|---|
| `reverse-proxy/scripts/gen-certs.sh` | 루트 CA(1회) + 와일드카드 leaf 발급 | 준비됨 |
| `reverse-proxy/nginx/_service-routes.conf` | `:80`·`:443` 공유 라우팅(단일 소스) | 사용 중(:80) |
| `reverse-proxy/nginx/reverse-proxy.conf` | `:80` server + `tls-enabled/*.conf` glob(현재 빈 include) | 사용 중 |
| `reverse-proxy/nginx/tls-available/wildcard.lge.com.conf` | `:443 ssl http2` server 블록(와일드카드) | **비활성(템플릿)** |
| `reverse-proxy/nginx/tls-enabled/` | 활성 `:443` 블록을 담는 곳 | **비어 있음(=HTTPS off)** |
| `reverse-proxy/ssl/` | 생성된 루트/leaf 키·인증서 | **X (gitignore)** |

**활성화 스위치 = `tls-enabled/`**: 비어 있으면 `:443` 블록이 없어 현행 `:80` 그대로. `tls-available/`
템플릿을 `tls-enabled/` 로 복사 + 인증서 배치 + NAT 443 을 해야 켜진다.

## 4. 준비 (지금 — 켜지 않고 생성만)

**인증서 미리 만들어 두기 (PVE 호스트에서 1회)** — 기존 서비스에 무영향:
```bash
cd /opt/pve-net-broker && git pull
./reverse-proxy/scripts/gen-certs.sh          # 루트 CA + 와일드카드 *.lge.com leaf 생성
# 산출물(reverse-proxy/ssl/, gitignore): rootCA.crt, rootCA.key, wildcard.lge.com.crt, wildcard.lge.com.key
```
여기까지 하면 **인프라는 준비 완료·대기 상태.** 아무 서비스도 안 바뀐다. (원하면 rootCA.crt 를
팀에 미리 배포해 둬도 무방 — 설치만으론 아무 효과 없고, 나중에 :443 켤 때 바로 신뢰됨.)

## 5. 활성화 (HTTPS/HTTP2 가 실제로 필요해질 때)

> 순서 핵심: **인증서를 .42 에 먼저 배치** → `tls-enabled/` 켜기 → NAT → 배포. 인증서 없이 `:443`
> 블록만 켜면 `nginx -t` 실패(단 reload 스킵되어 기존 :80 은 무중단 fail-safe).

**① 루트 인증서를 팀 PC 에 설치 (PC 당 1회)** — `reverse-proxy/ssl/rootCA.crt`:
- **Windows**: 더블클릭 → "인증서 설치" → **현재 사용자** → "신뢰할 수 있는 루트 인증 기관" → 완료.
  (Chrome·Edge 자동 커버. **Firefox** 는 자체 저장소라 별도 import.) CLI: `certutil -user -addstore Root rootCA.crt`
- **macOS**: `security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db rootCA.crt`

**② leaf(와일드카드)를 .42 에 배치 (1회)** — 개인키라 rsync 안 함, 직접:
```bash
scp reverse-proxy/ssl/wildcard.lge.com.{crt,key} riaveda@10.10.10.42:/tmp/
ssh riaveda@10.10.10.42 'sudo mkdir -p /etc/nginx/ssl && sudo mv /tmp/wildcard.lge.com.* /etc/nginx/ssl/ \
  && sudo chown root:root /etc/nginx/ssl/wildcard.lge.com.* \
  && sudo chmod 600 /etc/nginx/ssl/wildcard.lge.com.key && sudo chmod 644 /etc/nginx/ssl/wildcard.lge.com.crt'
```

**③ :443 켜기 (tls-enabled 로 복사)**
```bash
cp reverse-proxy/nginx/tls-available/wildcard.lge.com.conf reverse-proxy/nginx/tls-enabled/
```

**④ NAT 443 추가** — `network/nat-rules.sh` 의 `SERVICES` 배열에 한 줄:
```
    "443:10.10.10.42:443" # Reverse Proxy (HTTPS/HTTP2)
```

**⑤ 반영 (PVE 호스트)**
```bash
git pull && pnbctl nat reload && pnbctl proxy deploy
```

**⑥ 검증**
- `https://swp-iot.lge.com` → 자물쇠(경고 없음).
- 개발자도구 → Network → Protocol 열 = `h2`(HTTP/2).
- `/gitlab /build /agent /agent-dev /collab_search` 각 서비스 https 정상 동작.

## 6. 롤아웃 주의 (활성화 시)

- **병행(:80 유지·리다이렉트 없음) 로 시작** — https 깨져도 http 로 폴백, 회귀 0.
- **강제 http→https 리다이렉트는 신중히**: `/agent`·`/build` 등엔 브라우저 외 클라이언트(API·MCP·BYOH·
  curl·CI)도 붙는다. 이들을 https 로 강제하면 그 클라이언트도 루트를 신뢰해야 해 끊길 수 있다.
  연결상한(HTTP/2 이득)은 *브라우저 전용* 이므로, 강제하지 말고 **브라우저가 https 를 쓰게** 두는 게 안전.
- **GitLab `external_url`(GitLab 자체 설정, .36 — 남의 소스)**: https 를 GitLab 에 정식 적용하려면
  `external_url "https://swp-iot.lge.com/gitlab"` + `nginx['listen_https']=false` +
  `gitlab_rails['trusted_proxies']=['10.10.10.42']` → `gitlab-ctl reconfigure`. GitLab 관리자 몫.
- **mixed-content**: https 페이지가 `http://` 서브리소스를 부르면 차단(상대경로면 안전 — agent-platform 은 상대경로 확인됨).
- **HSTS**: 완전 https 기본화 확정 후에만.

## 7. 새 내부 서비스에 HTTPS 추가 (예: PVE 관리 UI)

와일드카드(`*.lge.com`) 인증서 한 장이 서브도메인 전부 커버하므로 **leaf 추가 발급 불요**.
- **리버스프록시를 태우는 서비스**: `tls-available/wildcard.lge.com.conf` 를 복제해 `server_name` 만
  바꿔 `tls-enabled/` 로. (같은 인증서 사용.)
- **PVE 관리 UI(pveproxy, :8006, Proxmox 가 직접 TLS 종단)**: 와일드카드 leaf 를 Proxmox 에 설치:
  ```
  /etc/pve/local/pveproxy-ssl.pem   ← wildcard.lge.com.crt (+ 필요 시 rootCA.crt 체인 append)
  /etc/pve/local/pveproxy-ssl.key   ← wildcard.lge.com.key
  systemctl restart pveproxy
  ```
  - ⚠️ **전제**: PVE 를 **호스트명(`pve.lge.com`)으로 접속**해야 신뢰된다. **IP(`10.10.10.x:8006`)로
    접속하면** DNS 이름 기반 CA·와일드카드로는 신뢰 인증서가 안 된다 → PVE 에 `.lge.com` 호스트명 부여 선결.

## 8. 인증서 갱신 (만료 대응)

- leaf **825일(~2.25년)**, 루트 CA **10년**. 만료 전 leaf 재발급:
  ```bash
  ./reverse-proxy/scripts/gen-certs.sh   # 루트 재사용, 와일드카드 leaf 만 새로 → .42 재배치 → pnbctl proxy deploy
  ```
- **루트는 재생성 금지** — 재생성하면 설치된 모든 PC 신뢰가 깨진다(스크립트도 루트 있으면 재사용).
  루트 만료(10년) 임박 시 새 루트 배포 캠페인 필요(전 PC 재설치).

## 9. 트러블슈팅

| 증상 | 원인·확인 | 조치 |
|---|---|---|
| `pnbctl proxy deploy` 가 `nginx -t` 에서 실패 | `.42:/etc/nginx/ssl/` 인증서 없음/경로 오타 | §5 ② 배치 확인. reload 스킵됐으므로 :80 무중단 |
| 브라우저 "안전하지 않음" | 그 PC 에 rootCA.crt 미설치 / Firefox 별도 저장소 | §5 ① 설치. Firefox 는 자체 import |
| 경고 없는데 :443 안 열림 | NAT 443 누락 | §5 ④ 후 `iptables -t nat -L PVE-NET-BROKER-STATIC -n \| grep 443` |
| Protocol 이 `http/1.1` | nginx http2 미적용/구버전 구문 | `.42` `nginx -v` — 1.25.1+ 면 `listen 443 ssl;`+`http2 on;` 로 |
| `/gitlab` https 링크·리다이렉트 깨짐 | GitLab `external_url` http (남의 소스) | §6 — GitLab 관리자에게 https 로 |
| WebSocket(`/build` 터미널) 끊김 | 업그레이드 헤더 | `_service-routes.conf` Upgrade/Connection 확인(이미 설정). HTTP/2+WS 는 WS 자동 h1 폴백 |

## 10. 보안 메모

- **name constraint(critical, `permitted;DNS:.lge.com`)** 로 이 CA 는 `.lge.com` 외 서명 불가 → 루트
  유출돼도 타 사이트 위장 불가. (구버전 클라이언트가 critical nameConstraints 거부하면 활성화 검증에서
  드러남 — 그때 non-critical 완화 검토.)
- **와일드카드 트레이드오프**: `*.lge.com` 한 장이 편하나, leaf 키 유출 시 *모든* .lge.com 서브도메인
  위장 가능(단 CA name-constraint 로 .lge.com 밖은 여전히 불가). 더 좁히려면 호스트별 leaf(`gen-certs.sh <host>`).
- **루트 개인키(`rootCA.key`)**: PVE 의 `reverse-proxy/ssl/`(gitignore)에만. 유출 시 전 PC 재배포 필요 →
  안전 백업 + 접근 제한. git 커밋 금지(.gitignore 방지). leaf 개인키는 `.42:/etc/nginx/ssl/`(root 600).
