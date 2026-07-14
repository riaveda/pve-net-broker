// 안내 페이지에 노출할 서비스 목록.
// 서비스 추가/변경은 여기만 수정하면 됩니다 (App 은 이 배열을 렌더).
//   icon: 카드 아바타 이모지 (외부 요청 없이 자체 완결)
//   svg : 이모지 대신 인라인 SVG 아이콘을 쓸 때. 있으면 icon 보다 우선.
//         (SVG 자체가 둥근 배경 타일이면 아이콘 박스 배경/테두리는 자동 제거)
export const SERVICES = [
  {
    name: 'GitLab',
    desc: '소스 코드 저장소',
    href: '/gitlab',
    url: 'swp-iot.lge.com/gitlab',
    icon: '🦊',
  },
  {
    name: 'Build-Center',
    desc: '빌드 플랫폼',
    href: '/build',
    url: 'swp-iot.lge.com/build',
    icon: '🏗️',
  },
  {
    name: 'Agent-Platform',
    desc: '에이전트 플랫폼',
    href: '/agent',
    url: 'swp-iot.lge.com/agent',
    icon: '🤖',
  },
  {
    name: 'Collab-Search',
    desc: '협업 검색',
    href: '/collab_search',
    url: 'swp-iot.lge.com/collab_search',
    svg: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs>
    <linearGradient id="cfGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0052CC"/>
      <stop offset="100%" style="stop-color:#2684FF"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="10" fill="url(#cfGrad)"/>
  <path d="M10 42 C16 30 22 24 32 24 C22 24 16 18 10 6"
        fill="none" stroke="white" stroke-width="5" stroke-linecap="round"/>
  <path d="M54 22 C48 34 42 40 32 40 C42 40 48 46 54 58"
        fill="none" stroke="white" stroke-width="5" stroke-linecap="round"/>
  <circle cx="44" cy="44" r="13" fill="white" opacity="0.95"/>
  <circle cx="44" cy="44" r="9" fill="none" stroke="#0052CC" stroke-width="3"/>
  <line x1="51" y1="51" x2="57" y2="57" stroke="#0052CC" stroke-width="3.5" stroke-linecap="round"/>
</svg>`,
  },
]
