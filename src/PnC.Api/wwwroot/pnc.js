// docs/design/API.md §9. What every page of the shell shares: the DEV act-as identity (decision #85; DEV only — the
// host refuses the header outside Development), the JSON calls, and the small DOM helpers. No framework (decision #119).
(function () {
  "use strict";
  let devUser = null;
  try { devUser = localStorage.getItem("pnc.devUser"); } catch (e) { devUser = null; }

  function headers(json) {
    const h = { Accept: "application/json" };
    if (json) h["Content-Type"] = "application/json";
    if (devUser) h["X-PnC-Dev-User"] = devUser;
    return h;
  }
  async function call(method, url, body) {
    const r = await fetch(url, { method, headers: headers(body !== undefined), body: body === undefined ? undefined : JSON.stringify(body) });
    const data = await r.json().catch(() => null);
    if (!r.ok) throw Object.assign(new Error((data && data.detail) || r.statusText), { status: r.status, code: data && data.code, body: data });
    return data;
  }
  const $ = (id) => document.getElementById(id);
  window.PnC = {
    $,
    text: (id, v) => { $(id).textContent = v == null ? "—" : String(v); },
    getJson: (url) => call("GET", url),
    postJson: (url, body) => call("POST", url, body === undefined ? {} : body),
    devUser: () => devUser,
    setDevUser: (v) => {
      devUser = v || null;
      try { if (v) localStorage.setItem("pnc.devUser", v); else localStorage.removeItem("pnc.devUser"); } catch (e) { /* no storage: the choice lasts the page */ }
    },
    el: (tag, cls, txt) => { const e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; },
    registerWorker: () => { if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {}); },
  };
})();
