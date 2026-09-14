// W8 (decision #158; round 5 B5). The request queue: every change request the person may read, from
// work.vChangeRequestStatus (the whole list read once — the view is materialised before paging, appsettings
// Api:MaterialiseBeforePaging), counted in the browser: raised, in progress, closed this month, cancelled. Filters by
// state and location; a row opens request.html. Nothing here knows a rule.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, me, setStatus, downloadCsv, legacyFree } = window.PnC;
  const shown = (name) => legacyFree(name);
  const state = { rows: [], filter: "", which: "open", station: "" };

  async function load() {
    setStatus("status", "Loading requests…");
    const t0 = performance.now();
    try {
      state.rows = await fetchAll("/api/v1/work/vChangeRequestStatus?orderBy=-RequestedAt");
      setStatus("status", state.rows.length + " request(s) · " + Math.round(performance.now() - t0) + " ms");
      const stations = [...new Set(state.rows.map((r) => r.StationName).filter(Boolean))].sort();
      const sel = $("station"); while (sel.options.length > 1) sel.remove(1);
      for (const s of stations) { const o = el("option", null, s); o.value = s; sel.appendChild(o); }
    } catch (e) { state.rows = []; setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
    render();
  }
  const isOpen = (r) => r.RequestState === "Raised" || r.RequestState === "InProgress";
  function counters() {
    const now = new Date(); const month = (d) => d && new Date(d).getFullYear() === now.getFullYear() && new Date(d).getMonth() === now.getMonth();
    const c = [["Raised", state.rows.filter((r) => r.RequestState === "Raised").length, "Raised"], ["In progress", state.rows.filter((r) => r.RequestState === "InProgress").length, "InProgress"],
      ["Closed this month", state.rows.filter((r) => r.RequestState === "Closed" && month(r.RequestCompletedAt)).length, "Closed"], ["Cancelled", state.rows.filter((r) => r.RequestState === "Cancelled").length, "Cancelled"],
      ["Not started", state.rows.filter((r) => !r.RequestState).length, ""]];
    const box = $("counters"); box.textContent = "";
    for (const [label, n, which] of c) {
      const b = el("button", "counter" + (state.which === which ? " selected" : "")); b.type = "button";
      b.appendChild(el("span", "n", String(n))); b.appendChild(el("span", "l", label));
      b.addEventListener("click", () => { state.which = which; $("state").value = which; render(); });
      box.appendChild(b);
    }
  }
  function visible() {
    const f = state.filter.trim().toLowerCase();
    return state.rows.filter((r) => (state.which === "open" ? isOpen(r) : state.which === "" ? true : (r.RequestState || "") === state.which)
      && (!state.station || r.StationName === state.station)
      && (!f || ["Title", "ScopeName", "EquipmentName", "StationName", "RequestedByDisplayName", "WorkTypeKey", "Description"].some((k) => r[k] && String(r[k]).toLowerCase().includes(f))));
  }
  const COLS = [
    { key: "Title", label: "Request", render: (r) => { const a = el("a", "row-link", legacyFree(r.Title) || "(untitled)"); a.href = "/request.html?id=" + r.WorkRequestEntityId; return a; }, csv: (r) => legacyFree(r.Title) },
    { key: "RequestState", label: "State", render: (r) => { const p = el("span", "pill " + (r.RequestState === "Closed" ? "effective" : r.RequestState === "InProgress" ? "draft" : ""), r.RequestState || "not started"); return p; }, csv: (r) => r.RequestState },
    { key: "WorkTypeKey", label: "Action type" }, { key: "StationName", label: "Location" }, { key: "EquipmentName", label: "Relay / equipment", render: (r) => shown(r.EquipmentName || r.ScopeName), csv: (r) => shown(r.EquipmentName || r.ScopeName) },
    { key: "DeviceCount", label: "Devices" }, { key: "RequestedByDisplayName", label: "Requested by" }, { key: "RequestedAt", label: "Requested", render: (r) => fmtDate(r.RequestedAt), csv: (r) => fmtDate(r.RequestedAt) },
    { key: "DocumentationStatus", label: "Documentation" }, { key: "DatabaseStatus", label: "Database" }, { key: "LifecycleState", label: "Package" },
    { key: "RequestCompletedAt", label: "Completed", render: (r) => fmtDate(r.RequestCompletedAt), csv: (r) => fmtDate(r.RequestCompletedAt) },
  ];
  function render() {
    counters();
    const rows = visible();
    table($("grid"), rows, COLS);
    $("summary").textContent = rows.length + " shown of " + state.rows.length;
  }
  $("state").addEventListener("change", (ev) => { state.which = ev.target.value; render(); });
  $("station").addEventListener("change", (ev) => { state.station = ev.target.value; render(); });
  $("filter").addEventListener("input", (ev) => { state.filter = ev.target.value; render(); });
  $("btn-csv").addEventListener("click", () => downloadCsv("requests-" + new Date().toISOString().slice(0, 10) + ".csv", visible(), COLS));
  $("btn-refresh").addEventListener("click", load);
  window.PnC.registerWorker();
  me().then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
