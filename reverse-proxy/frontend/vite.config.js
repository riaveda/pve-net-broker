import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// 빌드 산출물은 레포의 reverse-proxy/html/ 로 나간다 (배포 대상, git에 커밋됨).
// pnbctl proxy deploy 가 html/ 을 .42 의 /home/riaveda/reverse-proxy/html 로 rsync 한다.
export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    outDir: '../html',
    emptyOutDir: true,
  },
})
