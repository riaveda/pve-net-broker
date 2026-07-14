// 안내 페이지에 노출할 서비스 목록.
// 서비스 추가/변경은 여기만 수정하면 됩니다 (App 은 이 배열을 렌더).
//   icon: 카드 아바타에 쓰는 이모지 (외부 요청 없이 자체 완결)
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
]
