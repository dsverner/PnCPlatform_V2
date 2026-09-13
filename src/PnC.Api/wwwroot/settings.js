// W6 (decisions #127–#129). The legacy main window as one screen over document.vSettingsRecord: the state toggle is an
// equality filter on GridState; the column chooser reads the view's columns from /api/v1/catalog and keeps the choice in
// this browser; the print is the grid as shown (a device whose member left its change — GridState Withdrawn — is not
// offered by the toggle, as the legacy did: owner, W6 card A); the two actions are the engine's own calls (Set Verified Date = the
// RETURN_TO_SERVICE step: claim, witness by a second person, commit or check-in; Request Change = a work request on the
// device, its workflow started). Nothing here knows a rule: the API refuses in its own words and the screen shows them.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, postJson } = window.PnC;
  const VIEW = "/api/v1/document/vSettingsRecord";
  // the legacy grid's columns (LEGACY-SYSTEM §2), in the platform's names, as the default choice
  const DEFAULT_COLUMNS = ["StationName", "PanelName", "PositionName", "DeviceName", "Functions", "ModelCode", "ManufacturerName", "FirmwareVersion",
    "SerialNumber", "VoltageClassCode", "WorkRequestTitle", "WorkTypeKey", "CalculatedAt", "VerifiedAt", "LifecycleState", "RevisionLabel", "FileKind"];
  const LABELS = { StationName: "Location", PanelName: "Asset (panel)", PositionName: "Equipment", DeviceName: "Device", Functions: "Functions", ModelCode: "Model",
    ManufacturerName: "Manufacturer", FirmwareVersion: "Software version", SerialNumber: "Serial number", VoltageClassCode: "Voltage", WorkRequestTitle: "Change request",
    WorkTypeKey: "Action type", CalculatedAt: "Calculated (CDATE)", VerifiedAt: "Verified (VDATE)", LifecycleState: "Lifecycle", RevisionLabel: "Rev", FileKind: "File kind",
    GridState: "State", StationNumber: "Station no.", ParseStatus: "Parsed", InServiceFrom: "In service from", InServiceTo: "In service to", ReturnToServiceAt: "Returned to service" };
  const DATES = new Set(["CalculatedAt", "VerifiedAt", "InServiceFrom", "InServiceTo", "ReturnToServiceAt"]);
  const state = { gridState: "Active", rows: [], columns: [], chosen: [], filter: "", user: null };
  try { const c = JSON.parse(localStorage.getItem("pnc.settings.columns") || "null"); if (Array.isArray(c) && c.length) state.chosen = c; } catch (e) { /* default below */ }
  if (!state.chosen.length) state.chosen = DEFAULT_COLUMNS.slice();
  const q = qs();
  if (q.GridState) state.gridState = q.GridState;

  async function loadColumns() {
    const c = await getJson("/api/v1/catalog");
    const v = c.views.find((x) => x.schema === "document" && x.name === "vSettingsRecord");
    state.columns = v ? v.columns.map((x) => x.name || x.Name || x) : DEFAULT_COLUMNS.slice();
  }

  async function load() {
    setStatus("status", "Loading " + state.gridState + " settings…");
    const filters = "GridState=" + encodeURIComponent(state.gridState) + (q.DeviceEntityId ? "&DeviceEntityId=" + encodeURIComponent(q.DeviceEntityId) : "")
      + (q.WorkRequestEntityId ? "&WorkRequestEntityId=" + encodeURIComponent(q.WorkRequestEntityId) : "");
    const t0 = performance.now();
    try {
      state.rows = await fetchAll(VIEW + "?" + filters + "&orderBy=-CalculatedAt");
      const ms = Math.round(performance.now() - t0);
      setStatus("status", state.rows.length + " " + state.gridState.toLowerCase() + " settings record(s) · " + ms + " ms" + (q.DeviceEntityId ? " · one device" : "") + (q.WorkRequestEntityId ? " · one change request" : ""));
    } catch (e) { state.rows = []; setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
    render();
  }

  function visible() {
    const f = state.filter.trim().toLowerCase();
    if (!f) return state.rows;
    return state.rows.filter((r) => state.chosen.some((k) => r[k] != null && String(r[k]).toLowerCase().includes(f)));
  }

  function render() {
    for (const b of document.querySelectorAll(".state")) b.classList.toggle("selected", b.dataset.state === state.gridState);
    const rows = visible();
    const cols = state.chosen.map((k) => ({ key: k, label: LABELS[k] || k, render: DATES.has(k) ? (r) => fmtDate(r[k]) : undefined }));
    cols.push({ key: "_actions", label: "", cls: "noprint", render: (r) => actions(r) });
    table($("grid"), rows, cols);
    $("summary").textContent = rows.length + " row(s) shown of " + state.rows.length + " · columns: " + state.chosen.length;
    $("print-head").textContent = "Settings — " + state.gridState + " — " + rows.length + " row(s) — printed " + new Date().toLocaleString() + (state.user ? " by " + (state.user.person.displayName || state.user.user.userPrincipalName) : "");
  }

  function link(href, text) { const a = el("a", "row-link", text); a.href = href; return a; }
  function actions(r) {
    const box = el("span", "row-actions");
    box.appendChild(link("/setting.html?revision=" + r.RevisionRowId, "Display"));
    if (r.WorkRequestEntityId) box.appendChild(link("/request.html?id=" + r.WorkRequestEntityId, "Request"));
    // Set Verified Date: only while the run's RETURN_TO_SERVICE step is ready — the legacy "Active only" rule is now the engine's state
    if (r.RtsStepInstanceEntityId && (r.RtsStepState === "Ready" || r.RtsStepState === "Active")) {
      const b = el("button", "mini", "Set verified date"); b.type = "button"; b.disabled = !(state.user && state.user.can("Record.Modify"));
      b.addEventListener("click", () => verifiedDate(r)); box.appendChild(b);
    }
    if (r.GridState === "Active") {
      const b = el("button", "mini", "Request change"); b.type = "button"; b.disabled = !(state.user && state.user.can("WorkRequest.Modify"));
      b.addEventListener("click", () => requestChange(r)); box.appendChild(b);
    }
    return box;
  }

  // ---- Set Verified Date: the witnessed RETURN_TO_SERVICE commit (#114) or the check-in of a field capture (#115)
  function verifiedDate(r) {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "Set verified date — " + r.DeviceName + " (" + (r.WorkRequestTitle || "") + ")";
    setStatus("action-status", "The return-to-service step is " + r.RtsStepState + ". Claim it, have a second person witness from their own session, then commit now or check in a date captured in the field.");
    const step = r.RtsStepInstanceEntityId;
    const row = el("div", "action-row");
    const claim = el("button", null, "1. Claim"); claim.type = "button";
    const witness = el("button", null, "2. Witness (as the second person)"); witness.type = "button";
    const commit = el("button", null, "3a. Commit now"); commit.type = "button";
    const capBy = el("input"); capBy.type = "text"; capBy.placeholder = "captured by (UPN)"; capBy.id = "cap-by";
    const capAt = el("input"); capAt.type = "datetime-local"; capAt.id = "cap-at";
    const checkin = el("button", null, "3b. Check in the captured date"); checkin.type = "button";
    const call = async (what, fn) => { try { const x = await fn(); setStatus("action-status", what + " → done" + (x && x.advanced ? " · " + x.advanced : "") + "."); await load(); } catch (e) { setStatus("action-status", what + " → " + (e.status || "") + " " + e.message, true); } };
    claim.addEventListener("click", () => call("Claim", () => postJson("/api/v1/process/step-instances/" + step + "/claim", {})));
    witness.addEventListener("click", () => call("Witness", () => postJson("/api/v1/process/step-instances/" + step + "/witness", {})));
    commit.addEventListener("click", () => call("Commit", () => postJson("/api/v1/process/step-instances/" + step + "/commit", { outcome: "Done" })));
    checkin.addEventListener("click", () => call("Check-in", () => postJson("/api/v1/process/step-instances/" + step + "/checkin", { outcome: "Done", capturedBy: capBy.value.trim(), capturedAt: new Date(capAt.value).toISOString() })));
    for (const x of [claim, witness, commit, capBy, capAt, checkin]) row.appendChild(x);
    body.appendChild(row);
    $("action").scrollIntoView({ behavior: "smooth" });
  }

  // ---- Request Change: a work request scoped to the device, its request workflow started and moved to InProgress
  async function requestChange(r) {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "Request change — " + r.DeviceName;
    setStatus("action-status", "A new work request on this device; starting it runs the settings-change procedure.");
    let types = [];
    try { types = (await getJson("/api/v1/config/vDefinition?DefinitionKind=Program.WorkType&take=500")).rows; } catch (e) { types = []; }
    let versions = [];
    try { versions = (await getJson("/api/v1/config/vDefinitionVersion?Status=Effective&take=500")).rows; } catch (e) { versions = []; }
    const sel = el("select"); sel.id = "wt";
    for (const t of types) {
      const v = versions.find((x) => x.DefinitionEntityId.toLowerCase() === t.EntityId.toLowerCase());
      if (!v) continue;
      const o = el("option", null, t.DefinitionKey + " — " + (t.Name || "")); o.value = v.RowId; if (t.DefinitionKey === "SETTINGS_CHANGE") o.selected = true; sel.appendChild(o);
    }
    const title = el("input"); title.type = "text"; title.id = "wr-title"; title.value = "Settings change — " + r.DeviceName; title.size = 50;
    const go = el("button", null, "Raise and start"); go.type = "button";
    go.addEventListener("click", async () => {
      try {
        const wr = await postJson("/api/v1/work/WorkRequest_Add", { WorkTypeDefinitionVersionRowId: sel.value, Title: title.value.trim(), ScopeKind: "Asset", ScopeEntityId: r.DeviceEntityId });
        const wf = await postJson("/api/v1/process/workflows/start", { workflowKey: "SETTINGS_CHANGE_REQUEST", subjectKind: "WorkRequest", subjectEntityId: wr.EntityId });
        await postJson("/api/v1/process/workflow-instances/" + wf.workflowInstanceEntityId + "/transitions", { name: "Start" });
        location.href = "/request.html?id=" + wr.EntityId;
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); }
    });
    const row = el("div", "action-row");
    row.appendChild(el("label", "inline", "Action type ")); row.lastChild.appendChild(sel);
    row.appendChild(el("label", "inline", "Title ")); row.lastChild.appendChild(title);
    row.appendChild(go);
    body.appendChild(row);
    $("action").scrollIntoView({ behavior: "smooth" });
  }

  // ---- the column chooser
  function chooser() {
    const box = $("columns");
    if (!box.hidden) { box.hidden = true; return; }
    box.textContent = ""; box.hidden = false;
    for (const c of state.columns) {
      if (c === "RowSeq") continue;
      const lab = el("label", "col"); const cb = el("input"); cb.type = "checkbox"; cb.checked = state.chosen.includes(c); cb.value = c;
      cb.addEventListener("change", () => {
        state.chosen = state.columns.filter((k) => (k === c ? cb.checked : state.chosen.includes(k)));
        try { localStorage.setItem("pnc.settings.columns", JSON.stringify(state.chosen)); } catch (e) { /* the choice lasts the page */ }
        render();
      });
      lab.appendChild(cb); lab.appendChild(document.createTextNode(" " + (LABELS[c] || c))); box.appendChild(lab);
    }
    const reset = el("button", "mini", "Legacy columns"); reset.type = "button";
    reset.addEventListener("click", () => { state.chosen = DEFAULT_COLUMNS.slice(); try { localStorage.setItem("pnc.settings.columns", JSON.stringify(state.chosen)); } catch (e) { /* */ } render(); chooser(); chooser(); });
    box.appendChild(reset);
  }

  for (const b of document.querySelectorAll(".state")) b.addEventListener("click", () => { state.gridState = b.dataset.state; load(); });
  $("btn-columns").addEventListener("click", chooser);
  $("btn-print").addEventListener("click", () => window.print());
  $("btn-refresh").addEventListener("click", load);
  $("filter").addEventListener("input", (ev) => { state.filter = ev.target.value; render(); });

  window.PnC.registerWorker();
  me().then((m) => { state.user = m; return loadColumns(); }).then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
