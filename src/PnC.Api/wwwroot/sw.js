// docs/design/API.md §9. Caches the shell only. Never touches non-GET, cross-origin, /api/* or
// /health, so nothing the database says is ever served stale from here.
const CACHE = "shell-11";   // #190 (2026-09-18): the React app at /app/ is the PWA's start; its hashed assets are cached as they are fetched
const SHELL = ["/", "/index.html", "/styles.css", "/pnc.js", "/app.js", "/definitions.html", "/definitions.js", "/grants.html", "/grants.js", "/floc.html", "/floc.js",
  "/report.html", "/report.js", "/schemes.html", "/schemes.js", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png", "/app/"];
self.addEventListener("install", (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== self.location.origin || u.pathname.startsWith("/api") || u.pathname === "/health") return;
  e.respondWith(fetch(e.request).then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; })
    .catch(() => caches.match(e.request).then((m) => m || caches.match(u.pathname.startsWith("/app/") ? "/app/" : "/index.html"))));
});
