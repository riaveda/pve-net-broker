# HTTPS / HTTP/2 — 사내 CA + 리버스프록시 TLS 종단 (인수인계 문서)

`swp-iot.lge.com`(및 내부 `.lge.com` 서비스)에 **브라우저-신뢰 HTTPS + HTTP/2** 를 제공하는
방법·구성·운영 절차를 담는다. 이 문서 하나로 처음 인수받는 사람이 셋업·갱신·확장·장애대응까지
할 수 있도록 자기완결로 작성한다.

---

## 1. 왜 하는가 (배경)

- **문제**: 브라우저 HTTP/1.1 은 origin(scheme+host+port)당 **동시 연결 ~6개** 로 캡한다(브라우저 강제).
  agent-platform 디버깅 타임라인처럼 상시 SSE 스트림이 많으면 그 6슬롯이 고갈돼 중단(abort)·요청이
  클라이언트 큐에서 굶는다. 이 상한은 서버 설정으로 못 없앤다.
- **근본 해결 = HTTP/2**: 브라우저가 HTTP/2 를 쓰면 연결 1개에 스트림을 무제한 다중화 → origin
  연결상한 자체가 무의미해진다(업계 스트리밍 서비스 전부 HTTP/2 위에서 SSE 를 쓴다).
- **단 브라우저는 HTTP/2 를 HTTPS(TLS) 위에서만 쓴다**(cleartext h2c 미지원) → **HTTPS 종단이 전제**.
- **HTTPS = 신뢰된 인증서 필요**. 공개 CA(Let's Encrypt, DNS 소유증명 필요)·사내 정식 CA(발급 부서 필요)
  경로가 조직 사정으로 막혀, **자체 사내 CA(내부 PKI)** 방식을 택했다.
  - 자체 CA 는 개발용 편법이 아니라, 조직이 fleet 을 통제할 때 **내부 서비스 HTTPS 의 업계 정석**이다
    (step-ca·Vault PKI·AD 인증서 서비스와 동일 계열). 관건은 "루트를 각 PC 가 신뢰하게 만드는 것"뿐.

## 2. 구조 (한눈에)

```
[내부 CA 1개]  ── name-constrained: .lge.com 만 서명 가능(유출돼도 타 도메인 위장 불가)
    │  이 루트로 서비스마다 leaf(개별 서버) 인증서 발급
    ├─ leaf: swp-iot.lge.com  →  .42 nginx :443 (TLS 종단, 내부엔 http 로 프록시)
    └─ leaf: pve.lge.com 등    →  다른 내부 서비스(예: PVE 관리 UI) — 같은 루트 재사용
[루트 인증서(공개, rootCA.crt)]  →  팀 PC 신뢰저장소에 1회 설치 → 위 전부 자동 신뢰
```

- **TLS 종단은 리버스프록시(.42 nginx)에서** 한다. 브라우저 ↔ .42 는 https(h2), .42 ↔ 백엔드 VM 은
  기존대로 내부 http. 백엔드(gitlab·build·agent)는 **아무것도 바꿀 필요 없다**(`X-Forwarded-Proto`
  헤더는 이미 전달 중).
- **키 관리 원칙**: 루트/leaf 개인키는 git 에 올리지 않는다(`reverse-proxy/ssl/` 는 `.gitignore`).
  인증서·키는 "외부 주입 자산" — 레포엔 *생성 스크립트*와 *nginx 설정*만 있고, 실제 키는
  PVE/.42 로컬에만 존재한다.

## 3. 이 레포에 있는 것 (파일 지도)

| 파일 | 역할 | 커밋? |
|---|---|---|
| `reverse-proxy/scripts/gen-certs.sh` | 루트 CA(1회) + leaf 인증서 발급 | O (스크립트) |
| `reverse-proxy/nginx/_service-routes.conf` | `:80`·`:443` 공유 라우팅 본문(단일 소스) | O |
| `reverse-proxy/nginx/reverse-proxy.conf` | `:80` server + `tls-enabled/*.conf` glob include | O |
| `reverse-proxy/nginx/tls-available/swp-iot.lge.com.conf` | `:443 ssl http2` server 블록(원본 템플릿) | O |
| `reverse-proxy/nginx/tls-enabled/` | 활성 `:443` 블록(여기로 복사하면 켜짐) | `.gitkeep` 만 |
| `reverse-proxy/ssl/` | 생성된 루트/leaf 키·인증서 | **X (gitignore)** |
| `network/nat-rules.sh` | `443:10.10.10.42:443` 포워딩 포함 | O |

**활성화 스위치 = `tls-enabled/`**: 비어 있으면 `:443` 블록이 아예 없어 현행 `:80` 그대로다
(인증서 배치 전엔 HTTPS 가 절대 안 켜짐 — 안전). `tls-available/<host>.conf` 를 `tls-enabled/` 로
복사해야 켜진다. dev-routes 와 동일한 "available/enabled" glob 패턴.

## 4. 최초 셋업 (순서 중요)

> 순서 핵심: **인증서를 .42 에 먼저 배치**한 뒤 `tls-enabled/` 를 켜고 배포한다.
> (인증서 없이 `:443` 블록만 켜면 `nginx -t` 가 실패한다. 단 그 경우에도 reload 는 스킵되어
>  기존 :80 은 무중단 — fail-safe.)

**① 인증서 생성 (PVE 호스트에서 1회)**
```bash
cd /opt/pve-net-broker
./reverse-proxy/scripts/gen-certs.sh            # 루트 CA + swp-iot.lge.com leaf 생성
# 산출물(reverse-proxy/ssl/): rootCA.crt, rootCA.key, swp-iot.lge.com.crt, swp-iot.lge.com.key
```

**② 루트 인증서를 팀 PC 에 설치 (PC 당 1회)** — `reverse-proxy/ssl/rootCA.crt` 를 각 PC 로 전달:
- **Windows**: `rootCA.crt` 더블클릭 → "인증서 설치" → **현재 사용자** → "신뢰할 수 있는 루트 인증 기관"
  저장소 선택 → 완료. (Chrome·Edge 는 OS 저장소를 쓰므로 자동 커버.)
  - 관리자면 "로컬 컴퓨터"에 넣어 전체 사용자 커버 가능. **Firefox** 는 자체 신뢰저장소라 Firefox
    설정에서 별도 import(또는 `security.enterprise_roots.enabled=true`).
  - 스크립트 설치: `certutil -user -addstore Root rootCA.crt`
- **macOS**: 키체인 → 로그인/시스템 → "항상 신뢰". CLI: `security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db rootCA.crt`

**③ leaf 를 .42 에 배치 (1회)** — 개인키라 rsync 안 함, 직접 배치:
```bash
# PVE 에서 .42 로 복사 후 root 소유로 이동(예)
scp reverse-proxy/ssl/swp-iot.lge.com.{crt,key} riaveda@10.10.10.42:/tmp/
ssh riaveda@10.10.10.42 'sudo mkdir -p /etc/nginx/ssl && sudo mv /tmp/swp-iot.lge.com.* /etc/nginx/ssl/ \
  && sudo chown root:root /etc/nginx/ssl/swp-iot.lge.com.* \
  && sudo chmod 600 /etc/nginx/ssl/swp-iot.lge.com.key && sudo chmod 644 /etc/nginx/ssl/swp-iot.lge.com.crt'
```

**④ HTTPS 활성화 (레포에서 tls-enabled 로 복사)**
```bash
cp reverse-proxy/nginx/tls-available/swp-iot.lge.com.conf reverse-proxy/nginx/tls-enabled/
```

**⑤ 반영 (PVE 호스트)**
```bash
git pull && pnbctl nat reload && pnbctl proxy deploy
# nat reload: 443→.42:443 포워딩 적용 / proxy deploy: nginx conf rsync + nginx -t + reload
```

**⑥ 검증**
- `https://swp-iot.lge.com` 접속 → 자물쇠(경고 없음).
- 개발자도구 → Network → 요청 우클릭으로 **Protocol 열 표시** → `h2` 인지 확인(= HTTP/2).
- `/gitlab /build /agent /agent-dev` 각 서비스가 https 로 정상 동작하는지.

## 5. 단계적 롤아웃 (무중단 설계)

- **Phase 1 (현재 — 무위험)**: `:443` 을 기존 `:80` 과 **병행**. `:80` 그대로·리다이렉트 없음.
  HTTPS 가 깨져도 http 는 살아 있어 회귀 0. 위 ①~⑥ 이 Phase 1.
- **Phase 2 (검증·루트 배포 완료 후)**: http→https 기본화.
  - `:80` server 블록을 `return 301 https://$host$request_uri;` 로 리다이렉트.
  - `tls-available` 블록에 HSTS(`add_header Strict-Transport-Security ...`) 추가.
  - **mixed-content 점검**: 프론트가 `http://` 절대경로로 부르는 리소스가 있으면 차단됨(대개 상대경로라 무해).
  - ⚠️ **GitLab 주의(남의 소스)**: GitLab 의 `external_url` 은 GitLab 자체 설정(`10.10.10.36`)이다.
    https 기본화 시 `external_url` 을 `https://swp-iot.lge.com/gitlab` 로 바꿔야 clone URL·리다이렉트가
    안 깨진다. **이 레포 소관 아님** — GitLab 관리자에게 안내.
  - 보너스: 프론트가 https 로 서빙되면 클립보드 복사(secure-context) 정상화.

## 6. 새 내부 서비스에 HTTPS 추가 (예: PVE 관리 UI)

같은 루트 CA 로 leaf 만 더 발급하면 된다(루트 재배포 불요 — PC 는 이미 신뢰).
```bash
./reverse-proxy/scripts/gen-certs.sh pve.lge.com      # 같은 루트로 leaf 추가 발급
```
- **리버스프록시를 태우는 서비스**면 `tls-available/<host>.conf` 를 하나 더 만들어 `tls-enabled/` 로 복사.
- **PVE 관리 UI(pveproxy, 기본 :8006)** 는 리버스프록시가 아니라 Proxmox 가 직접 TLS 종단한다 →
  leaf 를 Proxmox 에 설치:
  ```
  # 노드별 인증서 (pve.lge.com leaf)
  /etc/pve/local/pveproxy-ssl.pem      ← leaf 인증서(swp-iot 방식과 동일 CA)
  /etc/pve/local/pveproxy-ssl.key      ← leaf 개인키
  systemctl restart pveproxy
  ```
  - ⚠️ **전제**: PVE 를 **호스트명(`pve.lge.com`)으로 접속**해야 이 인증서가 신뢰된다. **IP(`10.10.10.x:8006`)로
    접속하면** 우리 CA(DNS 이름 제약)로는 신뢰 인증서를 못 만든다 → PVE 에 `.lge.com` 호스트명(DNS/hosts)
    부여가 선결. (name constraint 가 DNS 기반이라 bare IP 는 제외됨.)

## 7. 인증서 갱신 (만료 대응)

- leaf 유효기간 **825일(~2.25년)**, 루트 CA **10년**. 만료 전 leaf 재발급:
  ```bash
  ./reverse-proxy/scripts/gen-certs.sh swp-iot.lge.com   # 루트 재사용, leaf 만 새로
  # → 위 ③(leaf 를 .42:/etc/nginx/ssl 로 재배치) → pnbctl proxy deploy
  ```
- **루트는 재생성하지 않는다** — 재생성하면 설치된 모든 PC 신뢰가 깨진다. 스크립트도 루트가 있으면
  재사용한다(안전장치). 루트 만료(10년)가 다가오면 그땐 새 루트 배포 캠페인이 필요(전 PC 재설치).
- 갱신 캘린더 리마인더 권장(leaf ~2년, 루트 ~10년). 자동화하려면 별도 cron + 재배포 스크립트.

## 8. 트러블슈팅

| 증상 | 원인·확인 | 조치 |
|---|---|---|
| `pnbctl proxy deploy` 가 `nginx -t` 에서 실패 | `.42:/etc/nginx/ssl/` 에 인증서 없음/경로 오타 | ③ leaf 배치 확인. reload 는 스킵됐으므로 기존 :80 은 무중단 |
| 브라우저 "안전하지 않음" 경고 | 그 PC 에 rootCA.crt 미설치 / Firefox 별도 저장소 | ② 루트 설치. Firefox 는 자체 import |
| 경고는 없는데 사이트 안 열림(:443) | NAT 443 포워딩 누락 | `pnbctl nat reload` 후 `iptables -t nat -L PVE-NET-BROKER-STATIC -n \| grep 443` |
| Protocol 이 `http/1.1` | nginx 가 http2 미적용 / 구버전 구문 | `.42` `nginx -v` 확인. 1.25.1+ 면 `listen 443 ssl;`+`http2 on;` 로 교체 |
| `/gitlab` https 에서 리다이렉트·링크 깨짐 | GitLab `external_url` 이 http (남의 소스) | Phase 2 §5 — GitLab 관리자에게 external_url https 로 |
| WebSocket(`/build` 터미널·로그) 끊김 | 업그레이드 헤더 | `_service-routes.conf` 의 Upgrade/Connection 헤더 확인(이미 설정). HTTP/2+WS 는 WS 가 자동 h1 폴백이라 정상 |

## 9. 보안 메모

- **name constraint(critical, `permitted;DNS:.lge.com`)** 로 이 CA 는 `.lge.com` 외 도메인 인증서를
  서명 못 한다 → 루트 개인키가 유출돼도 임의 사이트(google.com 등) 위장 불가. 그래서 "우리 루트를
  믿어달라"가 안전한 부탁이 된다. (구버전 클라이언트가 critical nameConstraints 를 거부하면 Phase 1
  검증에서 드러남 — 그때 non-critical 로 완화 검토.)
- **루트 개인키(`rootCA.key`) 보관**: PVE 호스트의 `reverse-proxy/ssl/`(gitignore) 에만 둔다. 유출 시
  전 PC 재배포가 필요하므로, 별도 안전 위치 백업 + 접근 제한 권장. git 에 절대 커밋 금지(.gitignore 로 방지).
- leaf 개인키는 `.42:/etc/nginx/ssl/`(root:root 600)에만.
