// W6 (decisions #57, #127). The FLOC view: a lazy tree over location.vNodeTree (an arrow only where HasChildren says so),
// the positions grid over location.vFloc, and browse by station or panel (a click in the tree), by scheme
// (location.vFlocScheme) or by model — each an equality filter the dispatcher already supports. "New setting" raises a
// work request on the position and starts its workflow (PROCEDURE-ENGINE §10 row 8).
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, qs, me, setStatus, getJson, postJson } = window.PnC;
  const state = { filter: { key: null, value: null, label: "Every position" }, scheme: "", model: "", rows: [], text: "", user: null };
  const POSITION_TYPES = new Set(["DevicePosition", "MeteringPosition", "NetworkSwitchPosition"]);

  // ---- the tree
  async function children(parent) {
    const rows = await fetchAll("/api/v1/location/vNodeTree?ParentEntityId=" + (parent || "null") + "&orderBy=Name");
    return rows.filter((n) => n.NodeTypeCode !== "ProtectionFunction");
  }
  function node(n) {
    const li = el("li", "node " + n.NodeTypeCode);
    const row = el("div", "node-row");
    const arrow = el("button", "arrow", n.HasChildren ? "▸" : "·"); arrow.type = "button"; arrow.disabled = !n.HasChildren;
    const name = el("button", "name", n.Name); name.type = "button"; name.title = n.NodeTypeCode;
    row.appendChild(arrow); row.appendChild(name); row.appendChild(el("span", "type small muted", n.NodeTypeCode));
    li.appendChild(row);
    let kids = null;
    arrow.addEventListener("click", async () => {
      if (kids) { kids.hidden = !kids.hidden; arrow.textContent = kids.hidden ? "▸" : "▾"; return; }
      arrow.textContent = "…";
      try { kids = el("ul", "children"); for (const c of await children(n.EntityId)) kids.appendChild(node(c)); li.appendChild(kids); arrow.textContent = "▾"; }
      catch (e) { arrow.textContent = "!"; arrow.title = e.message; }
    });
    name.addEventListener("click", () => {
      if (n.NodeTypeCode === "Station") { browse("StationNodeEntityId", n.EntityId, "Station " + n.Name); moveOffer(n); }
      else if (n.NodeTypeCode === "Panel") browse("PanelNodeEntityId", n.EntityId, "Panel " + n.Name);
      else if (POSITION_TYPES.has(n.NodeTypeCode)) browse("NodeEntityId", n.EntityId, "Position " + n.Name);
      else browse("Path", null, n.Name + " (" + n.NodeTypeCode + ": pick a station, panel or position beneath it)");
    });
    return li;
  }
  async function tree() {
    try {
      const roots = await children(null);
      $("tree").textContent = ""; for (const r of roots) $("tree").appendChild(node(r));
      $("tree-summary").textContent = roots.length + " root(s) · expand to browse; click a station, panel or position";
    } catch (e) { $("tree-summary").textContent = e.message; }
  }

  // ---- W8 (owner's card A, decision #153): a person with Node.Modify moves a station under another division — the owner
  // asked whether the tree can be corrected in the application; a division under NB Power or a merchant owner is the target
  async function moveOffer(n) {
    if (!state.user || !state.user.can("Node.Modify")) return;
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "Move " + n.Name + " to another owner or division";
    setStatus("action-status", "The station and everything beneath it moves; read scope follows the tree (IDENTITY §4). The move is recorded with who did it.");
    const owners = (await children(null)).filter((o) => o.NodeTypeCode === "Owner");
    const sel = el("select"); sel.id = "move-target";
    for (const o of owners) {
      for (const d of await children(o.EntityId)) {
        if (d.NodeTypeCode !== "Division" || d.EntityId.toLowerCase() === String(n.ParentEntityId).toLowerCase()) continue;
        const opt = el("option", null, o.Name + " › " + d.Name); opt.value = d.EntityId; sel.appendChild(opt);
      }
    }
    const row = el("div", "action-row");
    row.appendChild(el("label", "inline", "To ")); row.lastChild.appendChild(sel);
    const btn = el("button", null, "Move"); btn.type = "button";
    btn.addEventListener("click", async () => {
      if (!sel.value) return;
      btn.disabled = true; setStatus("action-status", "Moving…");
      try {
        await postJson("/api/v1/location/MoveNode", { EntityId: n.EntityId, NewParentEntityId: sel.value });
        setStatus("action-status", n.Name + " moved to " + sel.selectedOptions[0].textContent + ". The tree reloads.");
        await tree();
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); btn.disabled = false; }
    });
    row.appendChild(btn); body.appendChild(row);
    const add = el("div", "action-row");
    const owner = el("select"); owner.id = "new-division-owner"; for (const o of owners) { const opt = el("option", null, o.Name); opt.value = o.EntityId; owner.appendChild(opt); }
    const name = el("input"); name.type = "text"; name.placeholder = "new division name (e.g. Industrial)"; name.id = "new-division-name";
    const addBtn = el("button", null, "Add division"); addBtn.type = "button";
    addBtn.addEventListener("click", async () => {
      if (!name.value.trim()) return;
      try {
        const r = await postJson("/api/v1/location/AddNode", { NodeTypeCode: "Division", ParentEntityId: owner.value, Name: name.value.trim() });
        setStatus("action-status", "Division " + name.value.trim() + " added under " + owner.selectedOptions[0].textContent + "."); await tree(); moveOffer(n);
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); }
    });
    add.appendChild(el("label", "inline", "New division under ")); add.lastChild.appendChild(owner); add.appendChild(name); add.appendChild(addBtn); body.appendChild(add);
  }

  // ---- the grid
  function browse(key, value, label) { state.filter = { key: value ? key : null, value, label }; load(); }
  async function load() {
    $("browse-title").textContent = state.filter.label + (state.scheme ? " · scheme" : "") + (state.model ? " · model " + state.model : "");
    setStatus("status", "Loading…");
    const t0 = performance.now();
    try {
      let url;
      if (state.scheme) url = "/api/v1/location/vFlocScheme?SchemeEntityId=" + encodeURIComponent(state.scheme) + (state.filter.key ? "&" + state.filter.key + "=" + encodeURIComponent(state.filter.value) : "");
      else url = "/api/v1/location/vFloc?" + (state.filter.key ? state.filter.key + "=" + encodeURIComponent(state.filter.value) : "") + (state.model ? "&ModelCode=" + encodeURIComponent(state.model) : "");
      state.rows = await fetchAll(url + "&orderBy=StationName");
      setStatus("status", state.rows.length + " position(s) · " + Math.round(performance.now() - t0) + " ms");
    } catch (e) { state.rows = []; setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
    render();
  }
  function render() {
    const f = state.text.trim().toLowerCase();
    const rows = f ? state.rows.filter((r) => ["StationName", "PanelName", "PositionName", "InstalledAssetName", "ModelCode", "Functions", "SchemeNames"].some((k) => r[k] && String(r[k]).toLowerCase().includes(f))) : state.rows;
    table($("grid"), rows, [
      { key: "StationName", label: "Location", render: (r) => (r.StationName || "") + (r.StationNumber ? " (" + r.StationNumber + ")" : "") },
      { key: "PanelName", label: "Protected asset (panel)" }, { key: "PositionName", label: "Position" },
      { key: "InstalledAssetName", label: "Device" }, { key: "ModelCode", label: "Model" }, { key: "ManufacturerName", label: "Manufacturer" },
      { key: "Functions", label: "Protection functions" }, { key: "SchemeNames", label: "Schemes" }, { key: "FirmwareVersion", label: "Firmware" },
      { key: "PlacedFrom", label: "Installed", render: (r) => fmtDate(r.PlacedFrom) },
      { key: "_", label: "", cls: "noprint", render: (r) => actions(r) },
    ]);
    $("summary").textContent = rows.length + " shown of " + state.rows.length;
  }
  function link(href, text) { const a = el("a", "row-link", text); a.href = href; return a; }
  function actions(r) {
    const box = el("span", "row-actions");
    if (r.InstalledAssetEntityId) box.appendChild(link("/settings.html?DeviceEntityId=" + r.InstalledAssetEntityId, "Settings"));
    const b = el("button", "mini", "New setting"); b.type = "button"; b.disabled = !(state.user && state.user.can("WorkRequest.Modify"));
    b.addEventListener("click", () => newSetting(r)); box.appendChild(b);
    return box;
  }

  // ---- New Setting: a work request scoped to the position, its workflow started
  async function newSetting(r) {
    const body = $("action-body"); body.textContent = "";
    $("action").hidden = false; $("action-title").textContent = "New setting — " + (r.PositionName || "") + (r.InstalledAssetName ? " (" + r.InstalledAssetName + ")" : "");
    setStatus("action-status", "A work request on this position; starting it runs the settings-change procedure.");
    const types = (await getJson("/api/v1/config/vDefinition?DefinitionKind=Program.WorkType&take=500")).rows;
    const versions = (await getJson("/api/v1/config/vDefinitionVersion?Status=Effective&take=500")).rows;
    const sel = el("select");
    for (const t of types) { const v = versions.find((x) => x.DefinitionEntityId.toLowerCase() === t.EntityId.toLowerCase()); if (!v) continue; const o = el("option", null, t.DefinitionKey + " — " + (t.Name || "")); o.value = v.RowId; if (t.DefinitionKey === "SETTINGS_ADD") o.selected = true; sel.appendChild(o); }
    const title = el("input"); title.type = "text"; title.size = 50; title.value = "New setting — " + (r.PositionName || "");
    const go = el("button", null, "Raise and start"); go.type = "button";
    go.addEventListener("click", async () => {
      try {
        const wr = await postJson("/api/v1/work/WorkRequest_Add", { WorkTypeDefinitionVersionRowId: sel.value, Title: title.value.trim(), ScopeKind: "Node", ScopeEntityId: r.NodeEntityId });
        const wf = await postJson("/api/v1/process/workflows/start", { workflowKey: "SETTINGS_CHANGE_REQUEST", subjectKind: "WorkRequest", subjectEntityId: wr.EntityId });
        await postJson("/api/v1/process/workflow-instances/" + wf.workflowInstanceEntityId + "/transitions", { name: "Start" });
        location.href = "/request.html?id=" + wr.EntityId;
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); }
    });
    const row = el("div", "action-row");
    row.appendChild(el("label", "inline", "Action type ")); row.lastChild.appendChild(sel);
    row.appendChild(el("label", "inline", "Title ")); row.lastChild.appendChild(title);
    row.appendChild(go); body.appendChild(row);
    $("action").scrollIntoView({ behavior: "smooth" });
  }

  // ---- browse lists
  async function lists() {
    try { for (const s of (await getJson("/api/v1/scheme/vScheme?take=500&orderBy=Name")).rows) { const o = el("option", null, s.Name); o.value = s.EntityId; $("scheme").appendChild(o); } } catch (e) { /* no scheme read */ }
    try { for (const m of (await getJson("/api/v1/ref/vModel?take=500&orderBy=ModelCode")).rows) { const o = el("option", null, m.ModelCode + (m.ModelName ? " — " + m.ModelName : "")); o.value = m.ModelCode; $("model").appendChild(o); } } catch (e) { /* no model read */ }
  }
  $("scheme").addEventListener("change", (ev) => { state.scheme = ev.target.value; load(); });
  $("model").addEventListener("change", (ev) => { state.model = ev.target.value; load(); });
  $("filter").addEventListener("input", (ev) => { state.text = ev.target.value; render(); });
  $("btn-clear").addEventListener("click", () => { state.filter = { key: null, value: null, label: "Every position" }; state.scheme = ""; state.model = ""; state.text = ""; $("scheme").value = ""; $("model").value = ""; $("filter").value = ""; load(); });

  window.PnC.registerWorker();
  me().then((m) => { state.user = m; tree(); lists(); return load(); }).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
