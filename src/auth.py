"""요청 문지기 — 상태를 바꾸는 공개 호출은 API 키, /internal 은 호스트 자신만.

왜 필요한가: 이 서비스는 예약 한 번에 PVE 호스트의 nat 테이블에 DNAT 를 넣는다. 아무나 부를 수 있으면
  사내망 어디서든 이 호스트의 포워딩을 주입할 수 있다(감사 B-01).
  · 바인드는 vmbr1 게이트웨이 주소뿐(systemd 유닛·config.API_HOST) — 사내 인터페이스엔 소켓 자체가 없다.
  · 그래도 vmbr1 안의 VM 은 전부 닿는다 → 상태를 바꾸는 호출(reserve/renew/release)은 키를 요구한다.
  · /internal/* 은 udev 훅(호스트 자신)만 부른다 → 출발지가 호스트 자신이 아니면 거절한다.
"""

import secrets

from fastapi import Header, HTTPException, Request

from src.config import API_KEY, VMBR1_GATEWAY

# 호스트 자신이 자기를 부를 때의 출발지 — 루프백, 또는 바인드 주소(vmbr1 게이트웨이)로 붙은 경우.
HOST_LOCAL_SOURCES = frozenset({"127.0.0.1", "::1", VMBR1_GATEWAY})


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """예약·갱신·해제에 붙는 문지기. 키가 설정돼 있지 않으면 **전부 거절**한다(fail-closed)."""
    if not API_KEY:
        raise HTTPException(
            status_code=503,
            detail="API_KEY is not configured on the broker — reserve/renew/release are closed (run scripts/ensure-env.sh)",
        )
    if not x_api_key or not secrets.compare_digest(x_api_key, API_KEY):
        raise HTTPException(status_code=401, detail="invalid or missing X-Api-Key")


async def require_host_local(request: Request) -> None:
    """/internal 문지기 — udev 훅이 호스트 안에서 부르는 경로. 바깥 출발지는 거절한다."""
    host = request.client.host if request.client else None
    if host not in HOST_LOCAL_SOURCES:
        raise HTTPException(status_code=403, detail="internal endpoint — host-local callers only")
