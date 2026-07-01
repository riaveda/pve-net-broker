import { SERVICES } from './services.js'

function ServiceCard({ name, desc, href, url }) {
  return (
    <a className="service" href={href}>
      <span className="service-info">
        <span className="service-name">{name}</span>
        <span className="service-desc">{desc}</span>
      </span>
      <span className="service-url">{url}</span>
    </a>
  )
}

export default function App() {
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
            <ServiceCard key={s.href} {...s} />
          ))}
        </div>
      </main>

      <footer>HomeHub Task</footer>
    </div>
  )
}
