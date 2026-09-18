import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

// #190: the app is the PWA — the worker at the site root (scope /) makes it installable; standalone mode gives the screen
// back to the work (the owner: "it does impact screen real estate usage"). The worker never touches /api or /health.
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => { /* not installable here; the app still runs */ })

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
