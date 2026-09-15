// The platform's React front end (decision #163, 2026-09-15: supersedes #119 "no UI framework"). Built into the API's
// wwwroot/app and served under /app/ beside the plain pages until each of those is replaced. In development Vite proxies
// the API and /health to the DEV API on 5210. No inline script or style is emitted: the API's content-security policy
// (script-src 'self'; style-src 'self') stays as strict as before.
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

export default defineConfig({
  base: '/app/',
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  build: {
    outDir: path.resolve(__dirname, '../PnC.Api/wwwroot/app'),
    emptyOutDir: true,
    assetsInlineLimit: 0,           // never a data: URI for an asset — everything is a file under /app/assets
    modulePreload: { polyfill: false },
    sourcemap: false,
  },
  server: {
    port: 5220,
    proxy: {
      '/api': { target: 'http://127.0.0.1:5210', changeOrigin: false },
      '/health': { target: 'http://127.0.0.1:5210', changeOrigin: false },
    },
  },
})
