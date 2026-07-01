import { useEffect, useState } from 'react'
import { SERVICES } from './services.js'

const RECHECK_MS = 30000 // 30초마다 재확인

// 같은 도메인의 서비스 경로로 HEAD 요청 → 응답이 오면(상태 코드 무관) online.
// 302/401/405 같은 응답도 "서버가 살아있음"이므로 up 으로 본다. 네트워크 실패/타임아웃만 down.
async function probe(path) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 5000)
  try {
    await fetch(path, {
      method: 'HEAD',
      redirect: 'manual',
      cache: 'no-store',
      signal: controller.signal,
    })
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
