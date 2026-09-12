// docs/design/API.md §9. The shell shows /health, /me and the catalogue. Every later screen is a
// view over the catalogued procedures and views; nothing here knows a domain rule. Shared helpers: pnc.js.
(function () {
  "use strict";
  const { $, text, getJson } = window.PnC;

  async function health() {
    try {
      const h = await getJson("/health");
      text("env", h.environment); text("release", h.release); text("db", h.database);
      // DEV only (API.md §2, decision #85): the host in Development mode accepts X-PnC-Dev-User; the shell offers it
      // when /health says the environment is DEV. In Windows mode the field never appears.
      if (h.environment === "DEV") { $("dev-signin").hidden = false; if (window.PnC.devUser()) $("dev-upn").value = window.PnC.devUser(); }
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
    window.PnC.setDevUser($("dev-upn").value.trim());
    me().then((signedIn) => { if (signedIn) catalog(); else text("catalog-summary", "Sign in to see the catalogue."); });
  });

  window.PnC.registerWorker();
  health().then(me).then((signedIn) => { if (signedIn) catalog(); else text("catalog-summary", "Sign in to see the catalogue."); });
})();
