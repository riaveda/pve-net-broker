import { useEffect, useState } from 'react'
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

function ServiceCard({ name, desc, href, url, state }) {
  return (
    <a className="service" href={href}>
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

  return (
    <div className="container">
      <header>
        <h1>안녕하세요, HomeHub Task 입니다.</h1>
        <p>주요 서비스 안내 페이지입니다.</p>
      </header>

      <main>
        <h2>주요 서비스</h2>
        <div className="service-list">
          {SERVICES.map((s) => (
            <ServiceCard key={s.href} {...s} state={status[s.href]} />
          ))}
        </div>
      </main>

      <footer>HomeHub Task</footer>
    </div>
  )
}
