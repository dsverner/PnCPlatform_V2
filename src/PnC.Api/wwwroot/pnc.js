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

  // every row of a view: the dispatcher answers at most Api:MaxTake per call (10 000 since W7), so the page loops on skip
  async function fetchAll(url, max) {
    const rows = []; const take = 5000; let skip = 0;
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

  // W8 (#157–#158): what the legacy-shaped screens share.
  // No legacy record number on screen (owner, 2026-09-14): the migrated asset name ends "[0225]" and the migrated request title
  // ends "— A0225"; both are stripped for display only — the stored values are untouched and the text filters still match them
  const LEGACY_NO = /\s*(\[[A-Za-z]?\d{3,5}\]|—\s*[AMPD]\d{4})\s*$/;
  const legacyFree = (text) => (text == null ? "" : String(text).replace(LEGACY_NO, ""));
  // The migrated record's detail: the legacy overflow columns landed as the revision record's summary (W7, #140) — its
  // classification (class, use, responsibility, bulk power element, protection group, element, line type, number of
  // relays), its instrument-transformer ratios and its descriptions and remarks. Read back under the platform's own
  // labels; the legacy field names and record numbers stay in the data, not on screen (owner, 2026-09-14).
  const DETAIL = { SETTINGS2: ["notes", "Settings (continued)"], DESC1: ["notes", "Description 1"], DESC2: ["notes", "Description 2"], DESC3: ["notes", "Description 3"], DESC4: ["notes", "Description 4"],
    REMARKS1: ["notes", "Remarks 1"], REMARKS2: ["notes", "Remarks 2"], REMARKS3: ["notes", "Remarks 3"], REMARKS4: ["notes", "Remarks 4"], REMARKS5: ["notes", "Remarks 5"],
    CT_MAIN1: ["it", "CT main 1"], CT_MAIN2: ["it", "CT main 2"], CT_MAIN3: ["it", "CT main 3"], CT_MAIN4: ["it", "CT main 4"], PT_MAIN: ["it", "PT main"],
    CT_AUX1: ["it", "CT aux 1"], CT_AUX2: ["it", "CT aux 2"], CT_AUX3: ["it", "CT aux 3"], CT_AUX4: ["it", "CT aux 4"], PT_AUX: ["it", "PT aux"],
    CLASS: ["mp", "Class"], USE: ["mp", "Use"], RESPONSIBILITY: ["mp", "Responsibility"], Bulk_Power_Element: ["mp", "Bulk power element"], Protection_Group: ["mp", "Protection group"],
    ELEMENT: ["mp", "Element"], LINE_TYPE: ["mp", "Line type"], "NUMBER OF RELAYS": ["mp", "Number of relays"] };
  function legacyDetail(summary) {
    const out = { notes: [], mp: [], it: [] };
    for (const seg of String(summary || "").split(";")) {
      const i = seg.indexOf("="); if (i < 0) continue;                       // "Legacy A0087, CR 9607019" — the identifiers, not shown
      const key = seg.slice(0, i).trim(), value = seg.slice(i + 1).trim(); const d = DETAIL[key];
      if (d && value) out[d[0]].push([d[1], value]);
    }
    return out;
  }
  // a file's bytes as text (the settings file of a revision): the files endpoint, same identity header, no JSON parse
  async function getText(url) {
    const r = await fetch(url, { headers: headers(false) });
    if (!r.ok) { const data = await r.json().catch(() => null); throw Object.assign(new Error((data && data.detail) || r.statusText), { status: r.status, code: data && data.code }); }
    return r.text();
  }
  // the settings text of a designed revision: its first text file, else its first file, read as text; null when none
  async function settingsText(revisionRowId) {
    const files = (await call("GET", "/api/v1/document/vFile?RevisionRowId=" + encodeURIComponent(revisionRowId) + "&take=50")).rows;
    if (!files.length) return null;
    const f = files.find((x) => /^text\//i.test(x.MimeType || "")) || files.find((x) => x.FileRole === "Source") || files[0];
    return { name: f.FileName, mime: f.MimeType, text: await getText("/api/v1/files/" + f.RowId) };
  }
  // a context menu on an element: items [{label, run, disabled?}]; opened by right-click, Shift+F10 or the ⋯ button
  let openMenu = null;
  function closeMenu() { if (openMenu) { openMenu.remove(); openMenu = null; } }
  document.addEventListener("click", closeMenu); document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenu(); });
  function menu(items, x, y) {
    closeMenu();
    const m = el("div", "menu"); m.setAttribute("role", "menu");
    for (const it of items) {
      const b = el("button", "menu-item", it.label); b.type = "button"; b.setAttribute("role", "menuitem"); b.disabled = !!it.disabled;
      b.addEventListener("click", (e) => { e.stopPropagation(); closeMenu(); it.run(); });
      m.appendChild(b);
    }
    document.body.appendChild(m);
    const w = m.offsetWidth, h = m.offsetHeight;
    m.style.left = Math.max(4, Math.min(x, window.innerWidth - w - 8)) + "px"; m.style.top = Math.max(4, Math.min(y, window.innerHeight - h - 8)) + "px";
    openMenu = m; const first = m.querySelector("button:not(:disabled)"); if (first) first.focus();
    return m;
  }
  function attachMenu(node, items) {
    node.addEventListener("contextmenu", (e) => { e.preventDefault(); menu(items(), e.clientX, e.clientY); });
    node.addEventListener("keydown", (e) => { if (e.shiftKey && e.key === "F10") { e.preventDefault(); const r = node.getBoundingClientRect(); menu(items(), r.left + 24, r.bottom); } });
  }
  // rows as a CSV file the browser saves (Export CSV, round 5 B9)
  function downloadCsv(name, rows, columns) {
    const q = (v) => { const s = v == null ? "" : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
    const lines = [columns.map((c) => q(c.label || c.key)).join(",")];
    for (const r of rows) lines.push(columns.map((c) => q(c.csv ? c.csv(r) : r[c.key])).join(","));
    const blob = new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const a = el("a"); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }
  // Request Change / New Setting: a work request of the chosen type on the subject, its workflow started (PROCEDURE-ENGINE §10 rows 8–9).
  // Renders into the page's #action panel; opts {title, scopeKind, scopeEntityId, defaultType, heading, note}
  async function raiseRequest(opts) {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = opts.heading;
    setStatus("action-status", opts.note || "A new work request; starting it runs the settings-change procedure.");
    let types = [], versions = [];
    try { types = (await call("GET", "/api/v1/config/vDefinition?DefinitionKind=Program.WorkType&take=500")).rows; versions = (await call("GET", "/api/v1/config/vDefinitionVersion?Status=Effective&take=500")).rows; } catch (e) { /* the list stays empty; the API refuses the raise in its words */ }
    const sel = el("select"); sel.id = "wt";
    for (const t of types) {
      const v = versions.find((x) => x.DefinitionEntityId.toLowerCase() === t.EntityId.toLowerCase()); if (!v) continue;
      const o = el("option", null, t.DefinitionKey + " — " + (t.Name || "")); o.value = v.RowId; if (t.DefinitionKey === opts.defaultType) o.selected = true; sel.appendChild(o);
    }
    const title = el("input"); title.type = "text"; title.id = "wr-title"; title.value = opts.title; title.size = 50;
    const go = el("button", null, "Raise and start"); go.type = "button";
    go.addEventListener("click", async () => {
      go.disabled = true;
      try {
        const wr = await call("POST", "/api/v1/work/WorkRequest_Add", { WorkTypeDefinitionVersionRowId: sel.value, Title: title.value.trim(), ScopeKind: opts.scopeKind, ScopeEntityId: opts.scopeEntityId });
        const wf = await call("POST", "/api/v1/process/workflows/start", { workflowKey: "SETTINGS_CHANGE_REQUEST", subjectKind: "WorkRequest", subjectEntityId: wr.EntityId });
        await call("POST", "/api/v1/process/workflow-instances/" + wf.workflowInstanceEntityId + "/transitions", { name: "Start" });
        location.href = "/request.html?id=" + wr.EntityId;
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); go.disabled = false; }
    });
    const row = el("div", "action-row");
    for (const [lab, ctl] of opts.before || []) { row.appendChild(el("label", "inline", lab + " ")); row.lastChild.appendChild(ctl); }
    row.appendChild(el("label", "inline", "Action type ")); row.lastChild.appendChild(sel);
    row.appendChild(el("label", "inline", "Title ")); row.lastChild.appendChild(title);
    row.appendChild(go); body.appendChild(row);
    $("action").scrollIntoView({ behavior: "smooth" });
  }

  window.PnC = {
    $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getText, settingsText, menu, attachMenu, closeMenu, downloadCsv, raiseRequest, legacyFree, legacyDetail,
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
