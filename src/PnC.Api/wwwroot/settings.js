// W8 (decisions #157–#158). The legacy main window rebuilt to the owner's round-4 and round-5 rulings: progressive
// disclosure (a location, then its schemes as collapsed groups, rows only under an opened group, a row that unfolds to its
// card and settings text); the state toggle; the column chooser; filters by field; the right-click commands (Set Verified
// Date, Request Change, New Setting); Export CSV; the location report. The group is the functional scheme (round 5 B10:
// "really the Equipment field, more appropriately named"), the panel as the alternative. No legacy field name or record
// number is shown: the asset's bracketed legacy number is hidden on screen and still matched by the text filter (owner,
// 2026-09-14). The actions are the engine's own calls; the API refuses in its own words and the screen shows them.
(function () {
  "use strict";
  const { $, el, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, postJson, settingsText, attachMenu, menu, downloadCsv, raiseRequest, legacyFree } = window.PnC;
  const VIEW = "/api/v1/document/vSettingsRecord";
  // the row's columns in the legacy order (functions, device, revision) then the chosen ones; the group carries the context
  const LEAD = ["Functions", "DeviceName", "RevisionLabel"];
  const DEFAULT_COLUMNS = ["ModelCode", "ManufacturerName", "FirmwareVersion", "SerialNumber", "VoltageClassCode", "WorkRequestTitle", "WorkTypeKey", "CalculatedAt", "VerifiedAt", "LifecycleState", "FileKind"];
  const LABELS = { Functions: "Functions", DeviceName: "Device", RevisionLabel: "Rev", StationName: "Location", SchemeName: "Scheme", PanelName: "Equipment", PositionName: "Position", ModelCode: "Model",
    ModelName: "Model name", ManufacturerName: "Manufacturer", FirmwareVersion: "Software version", SerialNumber: "Serial number", VoltageClassCode: "Voltage", WorkRequestTitle: "Change request",
    WorkTypeKey: "Action type", CalculatedAt: "Calculated", VerifiedAt: "Verified", LifecycleState: "Lifecycle", FileKind: "File kind", GridState: "State", StationNumber: "Station no.",
    ParseStatus: "Parsed", InServiceFrom: "In service from", InServiceTo: "In service to", ReturnToServiceAt: "Returned to service", CalculatedByDisplayName: "Calculated by", Technology: "Technology", AssetStatus: "Device status" };
  const HIDDEN = new Set(["RowSeq", "RevisionRowId", "DeviceEntityId", "LifecycleWorkflowInstanceEntityId", "DocumentEntityId", "PackageRevisionRowId", "PackageSequence", "WorkRequestEntityId", "ProcedureInstanceEntityId",
    "RtsStepInstanceEntityId", "ModelId", "PositionNodeEntityId", "PanelNodeEntityId", "StationNodeEntityId", "SchemeEntityId", "InServiceFromQuality"]);
  const DATES = new Set(["CalculatedAt", "VerifiedAt", "InServiceFrom", "InServiceTo", "ReturnToServiceAt"]);
  const shown = (r) => legacyFree(r.DeviceName);               // the migrated asset name ends "[0225]": not shown (owner, 2026-09-14), still searchable
  // the legacy grid's Functions column was the FUNCTIONS text; where it carried no ANSI code the migration kept the text as the position's name
  const functions = (r) => r.Functions || r.PositionName || "";
  const state = { gridState: "Active", rows: [], outstanding: new Set(), columns: [], chosen: [], filter: "", filters: [], grouping: "scheme", open: new Set(), expanded: null, station: "", stations: [], user: null };
  try { const c = JSON.parse(localStorage.getItem("pnc.settings.columns2") || "null"); if (Array.isArray(c) && c.length) state.chosen = c; } catch (e) { /* default below */ }
  if (!state.chosen.length) state.chosen = DEFAULT_COLUMNS.slice();
  try { state.grouping = localStorage.getItem("pnc.settings.grouping") || "scheme"; } catch (e) { /* scheme */ }
  const q = qs();
  if (q.GridState) state.gridState = q.GridState;
  state.station = q.StationNodeEntityId || "";
  try { if (!state.station && !q.DeviceEntityId && !q.WorkRequestEntityId) state.station = localStorage.getItem("pnc.settings.station") || ""; } catch (e) { /* none */ }

  // ---- the location list (legacy: the active location; round 4: a list first, the estate only by an explicit choice)
  async function loadStations() {
    try { state.stations = await fetchAll("/api/v1/location/vNode?NodeTypeCode=Station&orderBy=Name"); } catch (e) { state.stations = []; }
    renderStations();
  }
  function renderStations() {
    const f = $("station-filter").value.trim().toLowerCase();
    const list = $("stations"); list.textContent = "";
    const rows = state.stations.filter((s) => !f || s.Name.toLowerCase().includes(f));
    for (const s of rows) {
      const li = el("li", "station" + (s.EntityId.toLowerCase() === state.station.toLowerCase() ? " selected" : ""));
      const b = el("button", "name", s.Name); b.type = "button";
      b.addEventListener("click", () => choose(s.EntityId));
      li.appendChild(b); list.appendChild(li);
    }
    const all = el("li", "station estate" + (state.station === "*" ? " selected" : ""));
    const b = el("button", "name", "Whole estate (every location)"); b.type = "button"; b.addEventListener("click", () => choose("*")); all.appendChild(b); list.appendChild(all);
    $("station-summary").textContent = rows.length + " of " + state.stations.length + " location(s)";
  }
  function choose(id) {
    state.station = id; state.open = new Set(); state.expanded = null;
    try { localStorage.setItem("pnc.settings.station", id); } catch (e) { /* */ }
    renderStations(); load();
  }
  $("station-filter").addEventListener("input", renderStations);

  async function loadColumns() {
    try {
      const c = await getJson("/api/v1/catalog");
      const v = c.views.find((x) => x.schema === "document" && x.name === "vSettingsRecord");
      state.columns = (v ? v.columns.map((x) => x.name || x.Name || x) : LEAD.concat(DEFAULT_COLUMNS)).filter((k) => !HIDDEN.has(k));
    } catch (e) { state.columns = LEAD.concat(DEFAULT_COLUMNS); }
  }

  // ---- the read: one state, one location (the pushed-down fast path); Active also reads Outstanding for the badges (round 5 B5)
  async function load() {
    const scoped = q.DeviceEntityId || q.WorkRequestEntityId;
    if (!scoped && !state.station) { state.rows = []; setStatus("status", "Choose a location on the left — or the whole estate at the foot of the list."); render(); return; }
    setStatus("status", "Loading " + state.gridState + " settings…");
    const scope = q.DeviceEntityId ? "&DeviceEntityId=" + encodeURIComponent(q.DeviceEntityId) : q.WorkRequestEntityId ? "&WorkRequestEntityId=" + encodeURIComponent(q.WorkRequestEntityId)
      : state.station && state.station !== "*" ? "&StationNodeEntityId=" + encodeURIComponent(state.station) : "";
    const t0 = performance.now();
    try {
      state.rows = await fetchAll(VIEW + "?GridState=" + encodeURIComponent(state.gridState) + scope + "&orderBy=-CalculatedAt");
      state.outstanding = new Set();
      if (state.gridState === "Active") {
        try { for (const r of await fetchAll(VIEW + "?GridState=Outstanding" + scope)) state.outstanding.add(String(r.DeviceEntityId).toLowerCase()); } catch (e) { /* no badges */ }
      }
      const ms = Math.round(performance.now() - t0);
      setStatus("status", state.rows.length + " " + state.gridState.toLowerCase() + " settings record(s) · " + ms + " ms" + (q.DeviceEntityId ? " · one device" : q.WorkRequestEntityId ? " · one change request" : state.station === "*" ? " · every location" : " · " + stationName()));
    } catch (e) { state.rows = []; setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
    render();
  }
  function stationName() { const s = state.stations.find((x) => x.EntityId.toLowerCase() === state.station.toLowerCase()); return s ? s.Name : "one location"; }

  // ---- filters: the text box over every shown column, and filters by field (round 5 B2)
  function visible() {
    const f = state.filter.trim().toLowerCase();
    const keys = LEAD.concat(state.chosen, ["SchemeName", "PanelName", "StationName", "PositionName"]);
    return state.rows.filter((r) => (!f || keys.some((k) => r[k] != null && String(r[k]).toLowerCase().includes(f)))
      && state.filters.every((x) => r[x.key] != null && String(DATES.has(x.key) ? fmtDate(r[x.key]) : r[x.key]).toLowerCase().includes(x.value.toLowerCase())));
  }
  function renderFilters() {
    const box = $("filters"); box.textContent = ""; box.hidden = !state.filters.length;
    state.filters.forEach((x, i) => {
      const chip = el("span", "chip", (LABELS[x.key] || x.key) + " contains “" + x.value + "”");
      const rm = el("button", "chip-x", "×"); rm.type = "button"; rm.title = "remove"; rm.addEventListener("click", () => { state.filters.splice(i, 1); renderFilters(); render(); });
      chip.appendChild(rm); box.appendChild(chip);
    });
  }
  function addFilter() {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "Add a filter"; setStatus("action-status", "Rows are kept when the field contains the text; several filters all apply.");
    const sel = el("select"); for (const k of LEAD.concat(["SchemeName", "PanelName", "StationName", "PositionName"], state.chosen)) { const o = el("option", null, LABELS[k] || k); o.value = k; sel.appendChild(o); }
    const val = el("input"); val.type = "text"; val.placeholder = "contains…";
    const ok = el("button", null, "Apply"); ok.type = "button";
    ok.addEventListener("click", () => { if (!val.value.trim()) return; state.filters.push({ key: sel.value, value: val.value.trim() }); renderFilters(); render(); $("action").hidden = true; });
    const row = el("div", "action-row"); row.appendChild(el("label", "inline", "Field ")); row.lastChild.appendChild(sel); row.appendChild(val); row.appendChild(ok); body.appendChild(row); val.focus();
  }

  // ---- the grouped grid: collapsed groups with counts; rows under an opened group; a row unfolds on a second click
  function groupKey(r) { return state.grouping === "scheme" ? (r.SchemeName || "(no scheme yet)") : state.grouping === "panel" ? (r.PanelName || "(no equipment)") : "all"; }
  function columns() {
    const ctx = state.grouping === "scheme" ? ["PanelName"] : state.grouping === "panel" ? ["SchemeName"] : ["SchemeName", "PanelName"];
    return LEAD.concat(state.station === "*" && !q.DeviceEntityId ? ["StationName"] : [], ctx, state.chosen.filter((k) => !LEAD.includes(k) && !ctx.includes(k)))
      .map((k) => ({ key: k, label: LABELS[k] || k,
        render: k === "DeviceName" ? (r) => deviceCell(r) : k === "Functions" ? functions : k === "WorkRequestTitle" ? (r) => legacyFree(r[k]) : DATES.has(k) ? (r) => fmtDate(r[k]) : (r) => r[k],
        csv: k === "DeviceName" ? shown : k === "Functions" ? functions : k === "WorkRequestTitle" ? (r) => legacyFree(r[k]) : DATES.has(k) ? (r) => fmtDate(r[k]) : undefined }));
  }
  function deviceCell(r) {
    const s = el("span"); s.appendChild(document.createTextNode(shown(r)));
    if (state.gridState === "Active" && state.outstanding.has(String(r.DeviceEntityId).toLowerCase())) { const b = el("span", "badge", "outstanding request"); b.title = "An outstanding change on this device — see the Outstanding tab"; s.appendChild(b); }
    return s;
  }
  function render() {
    for (const b of document.querySelectorAll(".state")) b.classList.toggle("selected", b.dataset.state === state.gridState);
    $("grouping").value = state.grouping;
    const rows = visible(); const cols = columns();
    const tbl = $("grid"); const thead = tbl.querySelector("thead"); const tbody = tbl.querySelector("tbody"); thead.textContent = ""; tbody.textContent = "";
    const hr = el("tr"); hr.appendChild(el("th", null, "")); for (const c of cols) hr.appendChild(el("th", null, c.label)); hr.appendChild(el("th", "noprint", "")); thead.appendChild(hr);
    const groups = new Map();
    for (const r of rows) { const k = groupKey(r); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
    const names = [...groups.keys()].sort((a, b) => a.localeCompare(b));
    if (state.grouping === "none") state.open.add("all");
    for (const name of names) {
      const list = groups.get(name); const isOpen = state.open.has(name);
      if (state.grouping !== "none") {
        const tr = el("tr", "group" + (isOpen ? " open" : "")); const td = el("td"); td.colSpan = cols.length + 2;
        const b = el("button", "group-toggle", (isOpen ? "▾ " : "▸ ") + name); b.type = "button"; b.setAttribute("aria-expanded", isOpen ? "true" : "false");
        b.appendChild(el("span", "count", list.length + (list.length === 1 ? " record" : " records")));
        b.addEventListener("click", () => { if (state.open.has(name)) state.open.delete(name); else state.open.add(name); render(); });
        td.appendChild(b); tr.appendChild(td); tbody.appendChild(tr);
      }
      if (!isOpen) continue;
      for (const r of list) {
        const tr = el("tr", "row" + (state.expanded === r.RevisionRowId ? " expanded" : "")); tr.tabIndex = 0;
        const arrow = el("td", "arrow", state.expanded === r.RevisionRowId ? "▾" : "▸"); tr.appendChild(arrow);
        for (const c of cols) { const td = el("td"); const v = c.render(r); if (v instanceof Node) td.appendChild(v); else td.textContent = v == null ? "" : String(v); tr.appendChild(td); }
        const act = el("td", "noprint"); const dots = el("button", "mini dots", "⋯"); dots.type = "button"; dots.title = "Commands (right-click or Shift+F10 also)";
        dots.addEventListener("click", (e) => { e.stopPropagation(); const rc = dots.getBoundingClientRect(); menu(commands(r), rc.left, rc.bottom); }); act.appendChild(dots); tr.appendChild(act);
        tr.addEventListener("click", () => { state.expanded = state.expanded === r.RevisionRowId ? null : r.RevisionRowId; render(); });
        tr.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); tr.click(); } });
        attachMenu(tr, () => commands(r));
        tbody.appendChild(tr);
        if (state.expanded === r.RevisionRowId) { const ctr = el("tr", "card-row"); const ctd = el("td"); ctd.colSpan = cols.length + 2; ctd.appendChild(card(r)); ctr.appendChild(ctd); tbody.appendChild(ctr); }
      }
    }
    $("summary").textContent = rows.length + " row(s) in " + names.length + " group(s) of " + state.rows.length + " · open a group to see its records; click a record to unfold it";
  }

  // ---- the card under a row (round 5 B1 C): the record's facts and the settings text as filed
  function card(r) {
    const box = el("div", "card");
    const facts = el("dl", "facts three");
    const pairs = [["Device", shown(r)], ["Model", (r.ModelCode || "") + (r.ModelName ? " — " + r.ModelName : "")], ["Manufacturer", r.ManufacturerName], ["Software version", r.FirmwareVersion], ["Serial number", r.SerialNumber],
      ["Functions", functions(r)], ["Location", (r.StationName || "") + (r.StationNumber ? " · " + r.StationNumber : "")], ["Scheme", r.SchemeName], ["Equipment", r.PanelName], ["Position", r.PositionName],
      ["Calculated", fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? " by " + r.CalculatedByDisplayName : "")], ["Verified", fmtWhen(r.VerifiedAt)],
      ["In service", r.InServiceFrom ? fmtDate(r.InServiceFrom) + (r.InServiceTo ? " – " + fmtDate(r.InServiceTo) : " – now") : "not in service"], ["Change request", legacyFree(r.WorkRequestTitle)], ["Action type", r.WorkTypeKey], ["Lifecycle", r.LifecycleState]];
    for (const [k, v] of pairs) { facts.appendChild(el("dt", null, k)); facts.appendChild(el("dd", null, v == null || v === "" ? "—" : String(v))); }
    box.appendChild(facts);
    const links = el("div", "row-actions");
    const a = el("a", "row-link", "Open the record"); a.href = "/setting.html?revision=" + r.RevisionRowId; links.appendChild(a);
    if (r.WorkRequestEntityId) { const b = el("a", "row-link", "Change request"); b.href = "/request.html?id=" + r.WorkRequestEntityId; links.appendChild(b); }
    box.appendChild(links);
    const pre = el("pre", "settings-text", "loading the settings text…"); box.appendChild(pre);
    settingsText(r.RevisionRowId).then((t) => { pre.textContent = t ? t.text : "No settings file is filed for this revision."; }).catch((e) => { pre.textContent = "The settings text could not be read: " + (e.status || "") + " " + e.message; });
    return box;
  }

  // ---- the commands (round 4 §3: the legacy right-click menu)
  function commands(r) {
    const can = (c) => !!(state.user && state.user.can(c));
    const items = [{ label: "Open the record", run: () => { location.href = "/setting.html?revision=" + r.RevisionRowId; } }];
    if (r.WorkRequestEntityId) items.push({ label: "Change request", run: () => { location.href = "/request.html?id=" + r.WorkRequestEntityId; } });
    items.push({ label: "Set verified date", disabled: !(r.RtsStepInstanceEntityId && (r.RtsStepState === "Ready" || r.RtsStepState === "Active") && can("Record.Modify")), run: () => verifiedDate(r) });
    items.push({ label: "Request change", disabled: !(r.GridState === "Active" && can("WorkRequest.Modify")), run: () => requestChange(r) });
    items.push({ label: "New setting here", disabled: !(r.PositionNodeEntityId && can("WorkRequest.Modify")), run: () => newSetting(r) });
    items.push({ label: "Compare revisions", run: () => { location.href = "/setting.html?revision=" + r.RevisionRowId + "#compare"; } });
    return items;
  }

  // Set Verified Date: the witnessed RETURN_TO_SERVICE commit (#114) or the check-in of a field capture (#115), with a date first (round 4)
  function verifiedDate(r) {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "Set verified date — " + shown(r) + (r.WorkRequestTitle ? " (" + r.WorkRequestTitle + ")" : "");
    setStatus("action-status", "The return-to-service step is " + r.RtsStepState + ". Pick the date the settings were verified in the field, then claim, have a second person witness from their own session, and check in — or commit now for today.");
    const step = r.RtsStepInstanceEntityId;
    const row = el("div", "action-row");
    const capAt = el("input"); capAt.type = "date"; capAt.id = "cap-at"; capAt.valueAsDate = new Date();
    const capBy = el("input"); capBy.type = "text"; capBy.placeholder = "verified by (account)"; capBy.id = "cap-by"; capBy.value = state.user && state.user.user ? state.user.user.userPrincipalName || "" : "";
    const claim = el("button", null, "1. Claim"); claim.type = "button";
    const witness = el("button", null, "2. Witness (as the second person)"); witness.type = "button";
    const checkin = el("button", null, "3. Check in that date"); checkin.type = "button";
    const commit = el("button", null, "Commit now (today)"); commit.type = "button";
    const cancel = el("button", null, "Cancel"); cancel.type = "button"; cancel.addEventListener("click", () => { $("action").hidden = true; });
    const call = async (what, fn) => { try { const x = await fn(); setStatus("action-status", what + " → done" + (x && x.advanced ? " · " + x.advanced : "") + "."); await load(); } catch (e) { setStatus("action-status", what + " → " + (e.status || "") + " " + e.message, true); } };
    claim.addEventListener("click", () => call("Claim", () => postJson("/api/v1/process/step-instances/" + step + "/claim", {})));
    witness.addEventListener("click", () => call("Witness", () => postJson("/api/v1/process/step-instances/" + step + "/witness", {})));
    checkin.addEventListener("click", () => call("Check-in", () => postJson("/api/v1/process/step-instances/" + step + "/checkin", { outcome: "Done", capturedBy: capBy.value.trim(), capturedAt: new Date(capAt.value + "T12:00:00").toISOString() })));
    commit.addEventListener("click", () => call("Commit", () => postJson("/api/v1/process/step-instances/" + step + "/commit", { outcome: "Done" })));
    row.appendChild(el("label", "inline", "Verified on ")); row.lastChild.appendChild(capAt); row.appendChild(capBy);
    for (const x of [claim, witness, checkin, commit, cancel]) row.appendChild(x);
    body.appendChild(row); $("action").scrollIntoView({ behavior: "smooth" });
  }
  function requestChange(r) {
    raiseRequest({ heading: "Request change — " + shown(r), title: "Settings change — " + shown(r), scopeKind: "Asset", scopeEntityId: r.DeviceEntityId, defaultType: "SETTINGS_CHANGE" });
  }
  // New Setting: a new record like this one — location and scheme prefilled, the work request on the position (round 4 §3)
  function newSetting(r) {
    const loc = el("input"); loc.type = "text"; loc.readOnly = true; loc.value = r.StationName || ""; loc.size = 24;
    const sch = el("input"); sch.type = "text"; sch.readOnly = true; sch.value = (r.SchemeName || "") + (r.PanelName ? " · " + r.PanelName : ""); sch.size = 30;
    raiseRequest({ heading: "New setting — " + (r.PositionName || shown(r)), title: "New setting — " + (r.PositionName || shown(r)), scopeKind: "Node", scopeEntityId: r.PositionNodeEntityId, defaultType: "SETTINGS_ADD",
      before: [["Location", loc], ["Scheme", sch]], note: "A work request on this position, in the same location and scheme; starting it runs the settings-change procedure." });
  }

  // ---- the column chooser
  function chooser() {
    const box = $("columns");
    if (!box.hidden) { box.hidden = true; return; }
    box.textContent = ""; box.hidden = false;
    for (const c of state.columns) {
      if (LEAD.includes(c)) continue;
      const lab = el("label", "col"); const cb = el("input"); cb.type = "checkbox"; cb.checked = state.chosen.includes(c); cb.value = c;
      cb.addEventListener("change", () => {
        state.chosen = state.columns.filter((k) => (k === c ? cb.checked : state.chosen.includes(k)));
        try { localStorage.setItem("pnc.settings.columns2", JSON.stringify(state.chosen)); } catch (e) { /* the choice lasts the page */ }
        render();
      });
      lab.appendChild(cb); lab.appendChild(document.createTextNode(" " + (LABELS[c] || c))); box.appendChild(lab);
    }
    const reset = el("button", "mini", "Default columns"); reset.type = "button";
    reset.addEventListener("click", () => { state.chosen = DEFAULT_COLUMNS.slice(); try { localStorage.setItem("pnc.settings.columns2", JSON.stringify(state.chosen)); } catch (e) { /* */ } render(); chooser(); chooser(); });
    box.appendChild(reset);
  }

  for (const b of document.querySelectorAll(".state")) b.addEventListener("click", () => { state.gridState = b.dataset.state; state.expanded = null; load(); });
  $("grouping").addEventListener("change", (ev) => { state.grouping = ev.target.value; state.open = new Set(); try { localStorage.setItem("pnc.settings.grouping", state.grouping); } catch (e) { /* */ } render(); });
  $("btn-columns").addEventListener("click", chooser);
  $("btn-filter").addEventListener("click", addFilter);
  $("btn-csv").addEventListener("click", () => downloadCsv("settings-" + state.gridState.toLowerCase() + "-" + new Date().toISOString().slice(0, 10) + ".csv", visible(), [{ key: "StationName", label: "Location" }, { key: "SchemeName", label: "Scheme" }, { key: "PanelName", label: "Equipment" }].concat(columns())));
  $("btn-print").addEventListener("click", () => { if (!state.station || state.station === "*") { setStatus("status", "Choose one location first: the report is per location.", true); return; } window.open("/report.html?StationNodeEntityId=" + encodeURIComponent(state.station) + "&GridState=" + encodeURIComponent(state.gridState), "_blank", "noopener"); });
  $("btn-refresh").addEventListener("click", load);
  $("filter").addEventListener("input", (ev) => { state.filter = ev.target.value; render(); });

  window.PnC.registerWorker();
  me().then((m) => { state.user = m; return Promise.all([loadColumns(), loadStations()]); }).then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
