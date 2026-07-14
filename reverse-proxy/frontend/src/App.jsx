import { useEffect, useMemo, useState } from 'react'
import { SERVICES } from './services.js'

const RECHECK_MS = 30000 // 30초마다 재확인

// 같은 도메인의 서비스 경로로 HEAD 요청을 보내 백엔드 생존을 판정한다.
//  - 2xx/3xx/401/403/405 등: 서비스가 살아있음 → up
//  - 5xx(502/503/504 = 업스트림 다운): nginx는 떠 있으나 백엔드가 죽음 → down
//  - 네트워크 실패/타임아웃: down
async function probe(path) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 5000)
  try {
    const res = await fetch(path, {
      method: 'HEAD',
      redirect: 'manual',
      cache: 'no-store',
      signal: controller.signal,
    })
    // redirect:'manual' → 3xx는 opaqueredirect(status 0)로 옴 = 도달 가능 = up
    if (res.type === 'opaqueredirect') return 'up'
    // 5xx는 게이트웨이/서버 오류 = 백엔드 다운
    if (res.status >= 500) return 'down'
    return 'up'
  } catch {
    return 'down'
  } finally {
    clearTimeout(timer)
  }
}

const LABEL = { checking: '확인 중', up: 'online', down: 'offline' }
// 정렬 우선순위: online 먼저 → 확인 중 → offline
const RANK = { up: 0, checking: 1, down: 2 }

function StatusDot({ state }) {
  return (
    <span
      className={`status-dot ${state}`}
      role="img"
      aria-label={LABEL[state]}
      title={LABEL[state]}
    />
  )
}

function ServiceCard({ name, desc, href, url, icon, state }) {
  return (
    <a className="service" href={href}>
      <span className="service-icon" aria-hidden="true">
        {icon || '🔗'}
      </span>
      <span className="service-info">
        <span className="service-name-row">
          <StatusDot state={state} />
          <span className="service-name">{name}</span>
        </span>
        <span className="service-desc">{desc}</span>
      </span>
      <span className="service-right">
        <span className="service-url">{url}</span>
        <span className={`service-status ${state}`}>{LABEL[state]}</span>
      </span>
    </a>
  )
}

export default function App() {
  const [status, setStatus] = useState(() =>
    Object.fromEntries(SERVICES.map((s) => [s.href, 'checking'])),
  )
  const [query, setQuery] = useState('')

  useEffect(() => {
    let alive = true
    const checkAll = async () => {
      const results = await Promise.all(
        SERVICES.map(async (s) => [s.href, await probe(s.href)]),
      )
      if (alive) setStatus(Object.fromEntries(results))
    }
    checkAll()
    const id = setInterval(checkAll, RECHECK_MS)
    return () => {
      alive = false
      clearInterval(id)
    }
  }, [])

  // 검색 필터(이름/설명/URL) + online 우선 정렬.
  // Array.sort 는 안정 정렬이라 같은 상태끼리는 원래 순서를 유지한다.
  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    const matched = q
      ? SERVICES.filter(
          (s) =>
            s.name.toLowerCase().includes(q) ||
            s.desc.toLowerCase().includes(q) ||
            s.url.toLowerCase().includes(q),
        )
      : SERVICES
    return [...matched].sort(
      (a, b) => RANK[status[a.href]] - RANK[status[b.href]],
    )
  }, [query, status])

  return (
    <div className="container">
      <header>
        <h1>안녕하세요, HomeHub Task 입니다.</h1>
        <p>주요 서비스 안내 페이지입니다.</p>
      </header>

      <main>
        <div className="section-head">
          <h2>주요 서비스</h2>
          <div className="search">
            <span className="search-icon" aria-hidden="true">🔍</span>
            <input
              type="search"
              className="search-input"
              placeholder="서비스 검색…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="서비스 검색"
            />
          </div>
        </div>

        <div className="service-list">
          {visible.map((s) => (
            <ServiceCard key={s.href} {...s} state={status[s.href]} />
          ))}
          {visible.length === 0 && (
            <p className="empty">‘{query}’ 에 맞는 서비스가 없습니다.</p>
          )}
        </div>
      </main>

      <footer>HomeHub Task</footer>
    </div>
  )
}
