// docs/design/API.md §9. What every page of the shell shares: the DEV act-as identity (decision #85; DEV only — the
// host refuses the header outside Development), the JSON calls, and the small DOM helpers. No framework (decision #119).
// W6 adds the page helpers the parity screens share: a paged read of a view, dates, a table renderer, the query string,
// and the signed-in person with their permission codes.
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
  const el = (tag, cls, txt) => { const e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; };

  // every row of a view: the dispatcher answers at most 500 per call (Api:MaxTake), so the page loops on skip
  async function fetchAll(url, max) {
    const rows = []; const take = 500; let skip = 0;
    for (;;) {
      const page = await call("GET", url + (url.includes("?") ? "&" : "?") + "take=" + take + "&skip=" + skip);
      for (const r of page.rows) rows.push(r);
      if (page.rows.length < take || (max && rows.length >= max)) break;
      skip += take;
    }
    return rows;
  }
  const fmtDate = (v) => (v ? new Date(v).toLocaleDateString() : "");
  const fmtWhen = (v) => (v ? new Date(v).toLocaleString() : "");
  function qs() { const o = {}; for (const [k, v] of new URLSearchParams(location.search)) o[k] = v; return o; }

  // a table from rows and column specs [{key, label, render?}]; render(row) may return text or an element
  function table(tbl, rows, columns, onRow) {
    const thead = tbl.querySelector("thead") || tbl.appendChild(el("thead"));
    const tbody = tbl.querySelector("tbody") || tbl.appendChild(el("tbody"));
    thead.textContent = ""; tbody.textContent = "";
    const hr = el("tr"); for (const c of columns) hr.appendChild(el("th", null, c.label || c.key)); thead.appendChild(hr);
    for (const row of rows) {
      const tr = el("tr");
      for (const c of columns) {
        const td = el("td", c.cls || null);
        const v = c.render ? c.render(row) : row[c.key];
        if (v instanceof Node) td.appendChild(v); else td.textContent = v == null ? "" : String(v);
        tr.appendChild(td);
      }
      if (onRow) onRow(tr, row);
      tbody.appendChild(tr);
    }
  }
  let mePromise = null;
  function me() {
    if (!mePromise) mePromise = call("GET", "/api/v1/me").then((m) => {
      m.can = (code) => (m.permissions || []).includes(code);
      if ($("who")) $("who").textContent = (m.person.displayName || m.user.userPrincipalName) + (devUser ? " (DEV act-as)" : "");
      return m;
    }).catch((e) => { if ($("who")) $("who").textContent = e.status === 401 ? "not signed in — sign in on the home page" : "error: " + e.message; throw e; });
    return mePromise;
  }
  function setStatus(id, msg, bad) { const s = $(id); if (!s) return; s.textContent = msg; s.className = "status " + (bad ? "bad" : "muted"); }

  window.PnC = {
    $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus,
    text: (id, v) => { $(id).textContent = v == null ? "—" : String(v); },
    getJson: (url) => call("GET", url),
    postJson: (url, body) => call("POST", url, body === undefined ? {} : body),
    devUser: () => devUser,
    setDevUser: (v) => {
      devUser = v || null;
      try { if (v) localStorage.setItem("pnc.devUser", v); else localStorage.removeItem("pnc.devUser"); } catch (e) { /* no storage: the choice lasts the page */ }
    },
    registerWorker: () => { if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {}); },
  };
})();
