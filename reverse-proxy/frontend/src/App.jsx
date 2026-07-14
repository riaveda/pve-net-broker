import { useEffect, useMemo, useState } from 'react'
import { SERVICES } from './services.js'

const RECHECK_MS = 30000 // 30초마다 재확인
const VIEW_KEY = 'portal.view' // localStorage: 'grid' | 'list'

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

// 아이콘 아바타. svg(인라인 SVG 문자열)가 있으면 그걸 렌더(자체 배경 타일이라
// 박스 배경/테두리 제거), 없으면 이모지. svg 는 레포 내 신뢰된 정적 데이터.
function ServiceIcon({ icon, svg }) {
  if (svg) {
    return (
      <span
        className="service-icon service-icon-svg"
        aria-hidden="true"
        dangerouslySetInnerHTML={{ __html: svg }}
      />
    )
  }
  return (
    <span className="service-icon" aria-hidden="true">
      {icon || '🔗'}
    </span>
  )
}

// 그리드(카드) 뷰 — 4:3 비율, 아이콘/상태 상단 · 이름/설명 중단 · URL 하단
function GridCard({ name, desc, href, url, icon, svg, state }) {
  return (
    <a className="service service-card" href={href}>
      <div className="service-top">
        <ServiceIcon icon={icon} svg={svg} />
        <span className={`service-badge ${state}`}>
          <StatusDot state={state} />
          {LABEL[state]}
        </span>
      </div>
      <div className="service-body">
        <span className="service-name">{name}</span>
        <span className="service-desc">{desc}</span>
      </div>
      <span className="service-url">{url}</span>
    </a>
  )
}

// 리스트(행) 뷰 — 한 줄에 아이콘 · 이름/설명 · URL/상태
function ListRow({ name, desc, href, url, icon, svg, state }) {
  return (
    <a className="service service-row" href={href}>
      <ServiceIcon icon={icon} svg={svg} />
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
  const [view, setView] = useState(() => {
    try {
      return localStorage.getItem(VIEW_KEY) === 'list' ? 'list' : 'grid'
    } catch {
      return 'grid'
    }
  })

  useEffect(() => {
    try {
      localStorage.setItem(VIEW_KEY, view)
    } catch {
      /* localStorage 불가 환경 무시 */
    }
  }, [view])

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

  const Card = view === 'grid' ? GridCard : ListRow

  return (
    <div className="container">
      <header>
        <h1>안녕하세요, HomeHub Task 입니다.</h1>
        <p>주요 서비스 안내 페이지입니다.</p>
      </header>

      <main>
        <div className="section-head">
          <h2>주요 서비스</h2>
          <div className="controls">
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
            <div className="view-toggle" role="group" aria-label="보기 방식">
              <button
                type="button"
                className={view === 'grid' ? 'active' : ''}
                aria-pressed={view === 'grid'}
                title="카드 보기"
                onClick={() => setView('grid')}
              >
                ▦
              </button>
              <button
                type="button"
                className={view === 'list' ? 'active' : ''}
                aria-pressed={view === 'list'}
                title="목록 보기"
                onClick={() => setView('list')}
              >
                ☰
              </button>
            </div>
          </div>
        </div>

        <div className={`service-list ${view}`}>
          {visible.map((s) => (
            <Card key={s.href} {...s} state={status[s.href]} />
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
