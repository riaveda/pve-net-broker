# HTTPS 전환 — 설계·사유 (why)

이 문서는 `swp-iot.lge.com` 서비스에 HTTPS(HTTP/2)를 도입하기로 한 **결정과 그 사유**를 담는다.
*무엇을 어떻게 켜나*(운영 절차)는 자매 문서 **[`tls-setup.md`](tls-setup.md)** 가 담고, 여기는 *왜 이렇게
정했나*(설계 근거)를 담아 처음 인수받는 사람이 판단 맥락까지 이해하도록 한다.

> **현재 상태**: 인프라(사내 CA·leaf 템플릿·생성 스크립트·문서)는 **준비만 돼 있고 비활성**이다.
> 아래는 "켤 때 이렇게 한다"의 확정 설계.

---

## 0. 한눈에 (확정안 요약)

- **인증서**: 사내 CA 가 서명한 `swp-iot.lge.com` **leaf 한 장** → `.42` nginx(:443 웹) + PVE pveproxy(:8006)
  둘 다 커버. (전 서비스가 이 호스트 하나라 와일드카드 불필요.)
- **루트**: 팀 PC 에 **1회 설치**(포털·agent·build 어디서든 가이드).
- **서빙**: `:80` **유지** + `:443`(HTTP/2) 추가. **리다이렉트·가이드는 "브라우저 페이지 로드"에만.**
- **대상**: 포털·agent-platform·build-center = "루트 없으면 가이드 / 있으면 443 리다이렉트" 통일.
  **gitlab·collab_search 는 제외**(http 유지).

## 1. 왜 HTTPS(HTTP/2)를 하나 (목표)

- **직접 동기**: 브라우저 **HTTP/1.1 origin 연결상한**(= scheme+host+port 당 동시 연결 ~6개, *브라우저* 강제)
  때문에 agent-platform 디버깅 UI 의 상시 SSE 스트림이 6슬롯을 채우면 중단·요청이 클라 큐에서 굶는다.
  이 상한은 서버 설정으로 못 없앤다. **HTTP/2**(연결 1개에 스트림 다중화)면 상한 자체가 사라진다.
- **단, 브라우저는 HTTP/2 를 HTTPS(TLS) 위에서만 쓴다**(cleartext h2c 미지원) → HTTPS 종단이 전제.
- **범위 인지(중요)**: 이 이득은 *브라우저* 전용이다. git·MCP·API·BYOH 같은 비-브라우저 클라이언트엔
  6-연결 상한이 없어 HTTP/2 가 이득 0 → 이들은 https 로 강제할 이유가 없다(그리고 강제하면 깨진다, §5).
- **비고**: 실제 "중단 먹통" 사고의 진짜 원인은 백엔드 이벤트루프 블로킹(tiktoken 런타임 다운로드)이었고
  그건 이미 별도 근본 수정됨. 연결상한은 *잠복* 이슈라 이 트랙은 급성 대응이 아니라 "브라우저 UX 개선".

## 2. 신뢰 모델 — root CA / leaf (키가 둘)

인증서 신뢰는 "믿는 발급기관(CA)이 서명했는가"로 성립한다. 공개 CA(Let's Encrypt)·사내 정식 CA 경로가
조직 사정으로 막혀, **자체 사내 CA(내부 PKI)** 를 쓴다(fleet 통제 하 내부 서비스 HTTPS 의 업계 정석 —
step-ca·Vault PKI 계열).

**키가 두 종류다(혼동 주의):**

| 키 | 역할 | 어디에 | 서빙에 쓰나 |
|---|---|---|---|
| **root CA 개인키** | leaf 를 *서명* | **PVE 에만**(안전보관) | ❌ 서명만 |
| **leaf 개인키** | 서버가 *TLS 핸드셰이크*에 사용 | **nginx 있는 곳 = .42** (+ pveproxy) | ✅ 매 접속 |

- **왜 leaf 를 `.42`에 둬야 하나**: TLS 종단(핸드셰이크)이 nginx(.42)에서 일어나고, 그때마다 leaf 개인키가
  필요하다. PVE 에만 있으면 .42 가 https 를 못 건다. → leaf 는 반드시 서빙 장비에.
- **왜 root 키는 PVE 에만**: 서빙 장비(.42)가 뚫려도 *발급기관 자체*는 안 털리게. **업계 토폴로지 그대로**
  (CA 키는 서빙 엣지와 격리, 엣지는 자기 leaf 만 보유).
- **root 공개 인증서**: 팀 PC 에 1회 설치 → 이 CA 발급분 자동 신뢰.

근거: [tls-setup.md §2·§10](tls-setup.md).

## 3. 왜 인증서 한 장(단일 호스트)으로 충분한가

- 전 서비스가 **`swp-iot.lge.com/<path>`** (호스트 하나, 경로만 다름) + PVE 관리 UI 는 **`swp-iot.lge.com:8006`**
  (같은 호스트, 포트만 다름).
- **TLS 인증서는 경로·포트 무관, 호스트명(SNI)만 매칭** → `swp-iot.lge.com` **leaf 한 장이 전 경로 + :8006
  까지 전부 커버.** 와일드카드 불필요.
- **CA name-constraint 도 `swp-iot.lge.com` 으로 좁힘**(`.lge.com` 전체 아님): 루트 키 유출 시 위장 범위가
  그 호스트 하나로 축소(blast radius↓). 필요한 건 다 커버하면서 더 안전.
- (레거시 `swp-iot.duckdns.org` 는 더 이상 정식 경로 아님 — 무시. 정식은 `swp-iot.lge.com:8006`.)

## 4. 서빙 전략 (핵심 규칙)

- **`:80` 절대 유지** — git·MCP·BYOH 가 http 로 계속 동작(안 깨짐).
- **`:443`(HTTP/2) 추가**.
- **리다이렉트·가이드는 "브라우저 페이지 로드"(`Accept: text/html`)에만** 건다. 이게 **load-bearing 규칙**:
  - 브라우저는 페이지 요청에 `Accept: text/html` 을 실어 보냄 → 이때만 가이드/리다이렉트.
  - 프로그램(git·MCP·BYOH)은 그 헤더를 안 실음 → **손 안 대고 http 로 통과.**
  - 비유: 문지기가 *사람만* 붙잡아 확인하고 *택배 트럭(프로그램)은 통과*. 트럭까지 막으면 배송(git·빌드)이 깨진다.

## 5. 서비스별 결정 + 사유

| 서비스 | 결정 | 사유 |
|---|---|---|
| **포털 `/`** | :80 유지 + (루트 없으면 가이드 / 있으면 443) | 가이드는 경고 없는 http 에서 보여야 함 |
| **agent-platform** | 브라우저만 (가이드 / 443 리다이렉트) | 프론트가 상대경로라 https OK, HTTP/2 로 연결상한 소멸(§1). https 첫 접속 시 재로그인 1회 |
| **build-center** | 브라우저만 (가이드 / 443 리다이렉트) | ⚠️ 실시간 터미널·로그가 WebSocket → https 에선 wss 여야(§8) |
| **gitlab** | **제외 — http 유지** | https 강제 시 git 이 깨짐(§6) |
| **collab_search** | 담당자에게 동일 방식 안내(소관 밖) | 리다이렉트 배관은 리버스프록시 한 곳 → 담당자는 "자기 앱이 https 렌더되나"만 확인 |
| **PVE `:8006`** | 같은 leaf 를 pveproxy 에 설치 | 같은 호스트라 별도 CA·트랙 불요. 루트만 깔리면 :8006 경고 소멸(포털 가이드로 덤 해결) |

**포털·agent·build 3개는 동일 기능(가이드+리다이렉트)으로 통일.** 이유:
- **통일 메커니즘(DRY)**: nginx 스니펫 하나를 세 경로에 동일 적용 — 특례 없음, 드리프트 0.
- **어느 입구로 와도 가이드**: 포털 안 거치고 서비스 직접 접속해도 루트 없으면 거기서 바로 안내(온보딩 갭 해소).
- **루트 있는 사람은 어디서든 자동 https.**

## 6. 비-브라우저 클라이언트는 왜 http 유지 (git·MCP·BYOH)

https 강제가 이들을 깨뜨리는 이유:

- **git (clone/pull/push)** — git 은 OS/브라우저 인증서 저장소가 아니라 **자기만의 CA 번들**을 쓴다(Git for
  Windows 는 자체 `ca-bundle.crt`). → **PC 에 루트를 깔아도 git 은 여전히 안 믿어 실패.**
  - **80 을 없애면**: 기존 http remote 가 `Connection refused` → pull/push 죽음. 복구엔 사용자마다
    `git remote set-url … https` + git 이 root 를 믿게(ca-bundle 추가/`http.sslBackend schannel`) 수동 2단계.
  - 신규 clone 도 https 면 git-CA 신뢰 설정 전엔 실패. → **그래서 gitlab 은 http 유지가 정답.**
  - **SSH clone(`ssh://…:2236`) 은 인증서·포트 무관 → 영향 0.**
- **MCP (agent→build)** — 서버끼리의 도구 호출(JSON). https 로 강제되면 호출 런타임(Python certifi·Node)이
  root 안 믿어 빌드 실패. **http 로 남으면 인증서가 안 끼어들고 JWT 로 인증** → 안전(내부 LAN).
  - 주의: JWT ≠ TLS 신뢰(다른 층). MCP 가 인증서 불필요한 건 "http 로 남아서"지 "JWT 라서"가 아니다.
- **BYOH** — 외부 개발 머신이 agent-platform 에 붙음. https 강제 시 그 머신이 root 안 믿어 끊김.

→ 이들은 `Accept: text/html` 을 안 보내므로 §4 분기에서 **자동 http 통과** = 지켜진다.

## 7. 온보딩 (probe + 가이드, 공유 1벌)

- **probe** = 브라우저가 몰래 우리 https 를 시험 접속해 "이 PC 가 우리 인증서를 믿나" 감지.
  - 믿음 → 443 리다이렉트. 못 믿음 → 가이드.
- **가이드** = 루트 인증서 다운로드 + **원클릭 설치 스크립트**(예: `certutil -user -addstore Root …`).
  - **자동 "설치"는 불가**(브라우저가 웹페이지의 루트 설치를 원천 차단 — 보안). "원클릭"이 최선.
- **공유 자원 1벌(DRY)**: 가이드 페이지·probe 엔드포인트는 **한 개**를 세 경로가 공유. 고칠 때 한 곳만.
- **Firefox** 는 OS 저장소가 아니라 자체 신뢰저장소라 별도 import 한 단계 더(가이드에 명시).

## 8. 앱별 https 준비 (리버스프록시와 별개, 각 앱 소관)

리버스프록시가 https 로 보내주는 것과, 각 앱이 https 에서 온전한지는 별개다.

- **build-center — WebSocket**: ✅ **확인됨(2026-07-22)**. build-center 프론트의 전 WebSocket(대시보드·
  LogViewer·마이그레이션·SSH 터미널·워킹셋)이 `const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'`
  패턴으로 페이지 프로토콜 기준 → https 에서 자동 wss. 코드 수정 불요. (유일한 `ws://` 하드코딩은
  `vite.config.ts` 개발 프록시 target 이라 운영·mixed-content 무관.)
- **agent-platform — 재로그인 1회**: 로그인 토큰이 `localStorage`(scheme 별 분리)라, http↔https 전환 시
  토큰이 새 저장소에 없어 **1회 재로그인**(깨짐 아님). 프론트는 상대경로라 mixed-content 없음(확인됨).
- **mixed-content 일반**: https 페이지가 `http://` 절대경로 서브리소스를 부르면 차단(상대경로면 안전).

## 9. 안 하는 것 (검토 후 기각) — 왜

| 기각안 | 왜 안 하나 |
|---|---|
| **`:80` 전면 제거** | 기계 클라이언트(git·MCP·BYOH)가 `Connection refused` 로 죽음. "경고+계속"도 아니고 접속 자체 불가 |
| **와일드카드 인증서(`*.lge.com`)** | 전 서비스가 `swp-iot.lge.com` 하나라 불필요. 좁은 단일 호스트가 더 안전 |
| **전 서비스 https 강제 / 전부 리다이렉트** | git·MCP·BYOH 깨짐. (표준 정본이려면 이들도 root 신뢰해야 하나, 그 비용을 회피) |
| **서비스마다 가이드 페이지** | 비효율·드리프트. 포털·agent·build 가 **공유 가이드 1벌** 사용 |
| **PVE 를 별도 CA/Let's Encrypt** | 정식 경로가 `swp-iot.lge.com:8006`(같은 호스트)라 우리 leaf 로 커버. 별도 트랙 불요 |

## 10. 남은 갭·확인 (활성화 전)

- **.42 인증서 배치가 pnbctl 자동화 밖**: `pnbctl proxy deploy` 는 riaveda 홈 rsync + `nginx -t`·`reload`
  두 개만 NOPASSWD sudo → `/etc/nginx/ssl` 에 root 로 못 씀. **1회 수동 sudo** 또는 **pnbctl 확장**(sudoers +
  `pnbctl proxy cert`) 필요.
- **build-center wss** — ✅ 확인 완료(§8, 코드가 이미 protocol 기준).
- **agent→build 경로** — ✅ 확인 완료(2026-07-22):
  - agent→build MCP = `host.docker.internal:8001/sse`(agent 호스트 .6 의 PM2 직통, 리버스프록시 밖) → 무관.
  - MCP→build-center = `BUILD_CENTER_BASE_URL`(설정 URL). :80 유지 + 브라우저-only 리다이렉트라 **http 값이면
    그대로 통과**(MCP 는 비-html). **조건: 이 env 를 http 로 유지**(내부 `http://10.10.10.41:4050/build` 이상적,
    또는 공개 http). **https 로 바꾸면** MCP 런타임(certifi)이 root 를 믿어야 함 → 바꾸지 않는 게 안전.
  - artifact 링크 = **JFrog URL**(별도 호스트, `image_url` 을 resource_link 로 통과) → swp-iot https 와 무관.
- **활성화 절차**는 [tls-setup.md §5](tls-setup.md) 참조.

## 11. 표준 대조 (납득 근거)

- **자체 사내 CA + 루트 배포** = fleet 통제 하 내부 서비스 HTTPS 의 정석(step-ca·Vault PKI·AD CS). CA 키 격리
  + 엣지는 leaf 만 = 표준 토폴로지.
- **http→https 301 리다이렉트** = 표준. 단 **"기계 클라는 http 통과"** 는 *사설 CA 를 기계 신뢰저장소까지
  안 심으려는* 실용적 변형(순수 표준은 전 클라이언트가 CA 신뢰 + 전부 https). 우리 맥락(기계 트러스트
  안 건드림)에 맞춘 선택 — 재평가 트리거: 공개 CA/GPO 자동배포가 열리면 전부 https 로 승격 검토.
