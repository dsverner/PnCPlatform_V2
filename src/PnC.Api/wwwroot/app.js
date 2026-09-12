// docs/design/API.md §9. The shell shows /health, /me and the catalogue. Every later screen is a
// view over the catalogued procedures and views; nothing here knows a domain rule.
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const text = (id, v) => { $(id).textContent = v == null ? "—" : String(v); };

  // DEV only (API.md §2, decision #85): the host in Development mode accepts X-PnC-Dev-User; the shell offers it
  // when /health says the environment is DEV, remembers the choice in this browser, and sends it on every request.
  // In Windows mode the field never appears and the browser's own identity is what IIS negotiates.
  let devUser = null;
  try { devUser = localStorage.getItem("pnc.devUser"); } catch (e) { devUser = null; }
  async function getJson(url) {
    const headers = { Accept: "application/json" };
    if (devUser) headers["X-PnC-Dev-User"] = devUser;
    const r = await fetch(url, { headers });
    const body = await r.json().catch(() => null);
    if (!r.ok) throw Object.assign(new Error((body && body.detail) || r.statusText), { status: r.status, code: body && body.code });
    return body;
  }

  async function health() {
    try {
      const h = await getJson("/health");
      text("env", h.environment); text("release", h.release); text("db", h.database);
      if (h.environment === "DEV") { $("dev-signin").hidden = false; if (devUser) $("dev-upn").value = devUser; }
      text("loaded", h.catalogLoadedAt ? new Date(h.catalogLoadedAt).toLocaleString() : null);
    } catch (e) { text("db", "unreachable: " + e.message); }
  }

  async function me() {
    try {
      const m = await getJson("/api/v1/me");
      text("who", m.person.displayName || m.user.userPrincipalName);
      text("person", m.person.displayName); text("upn", m.user.userPrincipalName);
      text("grants", m.grants.length ? m.grants.map((g) => g.RoleCode + " (" + g.ScopeKind + ")").join(", ") : "none");
      return true;
    } catch (e) {
      text("who", e.status === 401 ? "not signed in" : "error");
      text("person", e.message); text("upn", "—"); text("grants", "—");
      return false;
    }
  }

  function fill(listId, items, render) {
    const ul = $(listId); ul.textContent = "";
    for (const it of items) { const li = document.createElement("li"); li.textContent = render(it); if (!it.permission) li.className = "muted"; ul.appendChild(li); }
  }

  async function catalog() {
    try {
      const c = await getJson("/api/v1/catalog");
      text("catalog-summary", c.schemas.length + " schemas · " + c.procedures.length + " procedures · " + c.views.length + " views");
      fill("procs", c.procedures, (p) => p.schema + "." + p.name + (p.permission ? "  →  " + p.permission : "  (not callable)"));
      fill("views", c.views, (v) => v.schema + "." + v.name + (v.permission ? "  →  " + v.permission : ""));
    } catch (e) { text("catalog-summary", e.message); }
  }

  $("dev-signin").addEventListener("submit", (ev) => {
    ev.preventDefault();
    const v = $("dev-upn").value.trim();
    try { if (v) localStorage.setItem("pnc.devUser", v); else localStorage.removeItem("pnc.devUser"); } catch (e) { /* no storage: the choice lasts the page */ }
    devUser = v || null;
    me().then((signedIn) => { if (signedIn) catalog(); else text("catalog-summary", "Sign in to see the catalogue."); });
  });

  if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
  health().then(me).then((signedIn) => { if (signedIn) catalog(); else text("catalog-summary", "Sign in to see the catalogue."); });
})();
