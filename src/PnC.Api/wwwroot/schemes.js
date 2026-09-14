// W8 (decision #158; round 5 B11). Scheme curation for one station: its schemes with their member positions, the
// positions in no scheme, and the commands — rename (scheme.Scheme_Revise), move a position's memberships to another
// scheme (scheme.SchemeMember_Revise), merge one scheme into another (every member moved, the emptied scheme retired —
// never hard-deleted), a new scheme (scheme.Scheme_Add, typed by an Effective Program.SchemeType), and "add to a scheme"
// for an unplaced position (scheme.AddSchemeMember: its installed asset and its protection-function nodes). Reads:
// location.vFloc for the station's positions, scheme.vSchemeExpanded for memberships. Permission: Scheme.Modify.
(function () {
  "use strict";
  const { $, el, table, fetchAll, me, setStatus, getJson, postJson, legacyFree } = window.PnC;
  const shown = (name) => legacyFree(name);
  const state = { stations: [], station: "", positions: [], members: [], schemes: new Map(), types: [], user: null };
  try { state.station = localStorage.getItem("pnc.settings.station") || ""; if (state.station === "*") state.station = ""; } catch (e) { /* none */ }

  // ---- the location list (shared shape with the settings book)
  async function loadStations() {
    try { state.stations = await fetchAll("/api/v1/location/vNode?NodeTypeCode=Station&orderBy=Name"); } catch (e) { state.stations = []; }
    renderStations();
  }
  function renderStations() {
    const f = $("station-filter").value.trim().toLowerCase(); const list = $("stations"); list.textContent = "";
    const rows = state.stations.filter((s) => !f || s.Name.toLowerCase().includes(f));
    for (const s of rows) { const li = el("li", "station" + (s.EntityId.toLowerCase() === state.station.toLowerCase() ? " selected" : "")); const b = el("button", "name", s.Name); b.type = "button"; b.addEventListener("click", () => { state.station = s.EntityId; renderStations(); load(); }); li.appendChild(b); list.appendChild(li); }
    $("station-summary").textContent = rows.length + " of " + state.stations.length + " location(s)";
  }
  $("station-filter").addEventListener("input", renderStations);
  const stationName = () => { const s = state.stations.find((x) => x.EntityId.toLowerCase() === state.station.toLowerCase()); return s ? s.Name : ""; };

  // ---- the read: the station's positions, every membership that resolves to one of its assets or positions
  async function load() {
    if (!state.station) { setStatus("status", "Choose a location on the left."); $("schemes").textContent = ""; return; }
    setStatus("status", "Loading " + stationName() + "…"); $("title").textContent = "Schemes — " + stationName();
    try {
      state.positions = await fetchAll("/api/v1/location/vFloc?StationNodeEntityId=" + encodeURIComponent(state.station) + "&orderBy=PanelName");
      const assets = new Set(state.positions.map((p) => String(p.InstalledAssetEntityId || "").toLowerCase()).filter(Boolean));
      const nodes = new Set(state.positions.map((p) => String(p.NodeEntityId).toLowerCase()));
      const all = await fetchAll("/api/v1/scheme/vSchemeExpanded");
      state.members = all.filter((m) => assets.has(String(m.ResolvedAssetEntityId || "").toLowerCase()) || nodes.has(String(m.DevicePositionEntityId || "").toLowerCase()));
      if (!state.types.length) {
        try {
          const defs = (await getJson("/api/v1/config/vDefinition?DefinitionKind=Program.SchemeType&take=200")).rows;
          const vs = (await getJson("/api/v1/config/vDefinitionVersion?Status=Effective&take=500")).rows;
          state.types = defs.map((d) => ({ key: d.DefinitionKey, name: d.Name, version: (vs.find((v) => v.DefinitionEntityId.toLowerCase() === d.EntityId.toLowerCase()) || {}).RowId })).filter((t) => t.version);
        } catch (e) { state.types = []; }
      }
      setStatus("status", state.positions.length + " position(s) · " + state.members.length + " membership(s)");
    } catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); return; }
    render();
  }
  function positionOf(m) {
    const byNode = m.DevicePositionEntityId && state.positions.find((p) => String(p.NodeEntityId).toLowerCase() === String(m.DevicePositionEntityId).toLowerCase());
    return byNode || state.positions.find((p) => p.InstalledAssetEntityId && String(p.InstalledAssetEntityId).toLowerCase() === String(m.ResolvedAssetEntityId || "").toLowerCase());
  }
  function render() {
    state.schemes = new Map();
    const placed = new Set();
    for (const m of state.members) {
      const p = positionOf(m); if (!p) continue;
      if (!state.schemes.has(m.SchemeEntityId)) state.schemes.set(m.SchemeEntityId, { id: m.SchemeEntityId, name: m.SchemeName, status: m.SchemeStatus, positions: new Map() });
      const s = state.schemes.get(m.SchemeEntityId);
      if (!s.positions.has(p.NodeEntityId)) s.positions.set(p.NodeEntityId, { p, members: [] });
      s.positions.get(p.NodeEntityId).members.push(m); placed.add(p.NodeEntityId);
    }
    const can = !!(state.user && state.user.can("Scheme.Modify"));
    const box = $("schemes"); box.textContent = "";
    for (const s of [...state.schemes.values()].sort((a, b) => a.name.localeCompare(b.name))) {
      const det = el("details", "scheme"); const sum = el("summary");
      sum.appendChild(el("span", "scheme-name", s.name)); sum.appendChild(el("span", "count", s.positions.size + " position(s) · " + s.status));
      det.appendChild(sum);
      const acts = el("div", "row-actions");
      for (const [label, fn] of [["Rename", () => rename(s)], ["Merge into…", () => merge(s)]]) { const b = el("button", "mini", label); b.type = "button"; b.disabled = !can; b.addEventListener("click", fn); acts.appendChild(b); }
      const g = el("a", "row-link", "Settings of this scheme"); g.href = "/settings.html?StationNodeEntityId=" + encodeURIComponent(state.station); acts.appendChild(g);
      det.appendChild(acts);
      const tbl = el("table", "grid rows"); det.appendChild(tbl);
      table(tbl, [...s.positions.values()].sort((a, b) => (a.p.PanelName || "").localeCompare(b.p.PanelName || "") || (a.p.PositionName || "").localeCompare(b.p.PositionName || "")), [
        { key: "PanelName", label: "Equipment", render: (x) => x.p.PanelName }, { key: "PositionName", label: "Position", render: (x) => x.p.PositionName }, { key: "InstalledAssetName", label: "Device", render: (x) => shown(x.p.InstalledAssetName) },
        { key: "ModelCode", label: "Model", render: (x) => x.p.ModelCode }, { key: "Functions", label: "Functions", render: (x) => x.p.Functions }, { key: "roles", label: "Member as", render: (x) => x.members.map((m) => m.MemberKind + (m.MemberRoleCode ? " (" + m.MemberRoleCode + ")" : "")).join(", ") },
        { key: "_", label: "", cls: "noprint", render: (x) => { const b = el("button", "mini", "Move to…"); b.type = "button"; b.disabled = !can; b.addEventListener("click", () => move(x, s)); return b; } },
      ]);
      box.appendChild(det);
    }
    const unplaced = state.positions.filter((p) => !placed.has(p.NodeEntityId));
    $("unplaced-summary").textContent = unplaced.length ? unplaced.length + " position(s) of this station belong to no scheme yet." : "Every position of this station is in a scheme.";
    table($("unplaced"), unplaced, [
      { key: "PanelName", label: "Equipment" }, { key: "PositionName", label: "Position" }, { key: "InstalledAssetName", label: "Device", render: (p) => shown(p.InstalledAssetName) }, { key: "ModelCode", label: "Model" }, { key: "Functions", label: "Functions" },
      { key: "_", label: "", cls: "noprint", render: (p) => { const b = el("button", "mini", "Add to a scheme…"); b.type = "button"; b.disabled = !can; b.addEventListener("click", () => addTo(p)); return b; } },
    ]);
    $("btn-new").disabled = !can;
  }

  // ---- the commands
  function panel(title, note) { const body = $("action-body"); body.textContent = ""; $("action").hidden = false; $("action-title").textContent = title; setStatus("action-status", note); $("action").scrollIntoView({ behavior: "smooth" }); return body; }
  function schemeSelect(except) { const sel = el("select"); for (const s of [...state.schemes.values()].sort((a, b) => a.name.localeCompare(b.name))) { if (except && s.id === except.id) continue; const o = el("option", null, s.name); o.value = s.id; sel.appendChild(o); } return sel; }
  async function schemeRow(id) { return (await getJson("/api/v1/scheme/vScheme?EntityId=" + encodeURIComponent(id))).rows[0]; }
  async function reviseScheme(id, patch) {
    const s = await schemeRow(id); if (!s) throw new Error("the scheme is no longer current");
    await postJson("/api/v1/scheme/Scheme_Revise", Object.assign({ EntityId: id, SchemeTypeDefinitionVersionRowId: s.SchemeTypeDefinitionVersionRowId, Name: s.Name, SystemDesignation: s.SystemDesignation, Status: s.Status, Notes: s.Notes }, patch));
  }
  async function moveMembers(members, toScheme) {
    for (const m of members) {
      const row = (await getJson("/api/v1/scheme/vSchemeMember?EntityId=" + encodeURIComponent(m.MemberEntityId))).rows[0]; if (!row) continue;
      await postJson("/api/v1/scheme/SchemeMember_Revise", { EntityId: row.EntityId, SchemeEntityId: toScheme, MemberKind: row.MemberKind, MemberEntityId: row.MemberEntityId, MemberRoleCode: row.MemberRoleCode, IsInService: row.IsInService, Notes: row.Notes });
    }
  }
  function rename(s) {
    const body = panel("Rename " + s.name, "The scheme keeps its members and history; the new name is a new version of the scheme.");
    const name = el("input"); name.type = "text"; name.value = s.name; name.size = 40;
    const ok = el("button", null, "Rename"); ok.type = "button";
    ok.addEventListener("click", async () => { ok.disabled = true; try { await reviseScheme(s.id, { Name: name.value.trim() }); setStatus("action-status", "Renamed."); await load(); } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); ok.disabled = false; } });
    const row = el("div", "action-row"); row.appendChild(name); row.appendChild(ok); body.appendChild(row);
  }
  function move(x, from) {
    const body = panel("Move " + (x.p.PositionName || shown(x.p.InstalledAssetName)) + " from " + from.name, "Its memberships (" + x.members.length + ") are revised to the chosen scheme; nothing is deleted.");
    const sel = schemeSelect(from); const ok = el("button", null, "Move"); ok.type = "button";
    ok.addEventListener("click", async () => { if (!sel.value) return; ok.disabled = true; try { await moveMembers(x.members, sel.value); setStatus("action-status", "Moved."); await load(); } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); ok.disabled = false; } });
    const row = el("div", "action-row"); row.appendChild(el("label", "inline", "To ")); row.lastChild.appendChild(sel); row.appendChild(ok); body.appendChild(row);
  }
  function merge(s) {
    const body = panel("Merge " + s.name + " into another scheme", "Every member of " + s.name + " moves to the chosen scheme; " + s.name + " is then retired (kept, not deleted).");
    const sel = schemeSelect(s); const ok = el("button", null, "Merge"); ok.type = "button";
    ok.addEventListener("click", async () => {
      if (!sel.value) return; ok.disabled = true;
      try { const members = [...s.positions.values()].flatMap((x) => x.members); await moveMembers(members, sel.value); await reviseScheme(s.id, { Status: "Retired" }); setStatus("action-status", "Merged; " + s.name + " retired."); await load(); }
      catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); ok.disabled = false; }
    });
    const row = el("div", "action-row"); row.appendChild(el("label", "inline", "Into ")); row.lastChild.appendChild(sel); row.appendChild(ok); body.appendChild(row);
  }
  function typeSelect() { const sel = el("select"); for (const t of state.types) { const o = el("option", null, t.name + " (" + t.key + ")"); o.value = t.version; sel.appendChild(o); } return sel; }
  function newScheme() {
    const body = panel("New scheme at " + stationName(), "A scheme is typed by a scheme-type definition; its station follows from its members, so add a position to it next.");
    const name = el("input"); name.type = "text"; name.placeholder = "name (e.g. Line 1103, Transformer T2, RAS)"; name.size = 40; const type = typeSelect();
    const ok = el("button", null, "Create"); ok.type = "button";
    ok.addEventListener("click", async () => {
      if (!name.value.trim() || !type.value) return; ok.disabled = true;
      try { await postJson("/api/v1/scheme/Scheme_Add", { SchemeTypeDefinitionVersionRowId: type.value, Name: name.value.trim(), Status: "Designed" }); setStatus("action-status", "Created; it appears once a position of this station is added to it."); await load(); }
      catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); ok.disabled = false; }
    });
    const row = el("div", "action-row"); row.appendChild(name); row.appendChild(el("label", "inline", "Type ")); row.lastChild.appendChild(type); row.appendChild(ok); body.appendChild(row);
  }
  async function addTo(p) {
    const body = panel("Add " + (p.PositionName || shown(p.InstalledAssetName)) + " to a scheme", "Its installed device and its protection functions become members (role Member).");
    const sel = el("select");
    try { for (const s of (await fetchAll("/api/v1/scheme/vScheme?orderBy=Name")).filter((s) => s.Status !== "Retired")) { const o = el("option", null, s.Name + (state.schemes.has(s.EntityId) ? "" : " (elsewhere or empty)")); o.value = s.EntityId; sel.appendChild(o); } } catch (e) { /* empty */ }
    const ok = el("button", null, "Add"); ok.type = "button";
    ok.addEventListener("click", async () => {
      if (!sel.value) return; ok.disabled = true;
      try {
        if (p.InstalledAssetEntityId) await postJson("/api/v1/scheme/AddSchemeMember", { SchemeEntityId: sel.value, MemberKind: "Asset", MemberEntityId: p.InstalledAssetEntityId, MemberRoleCode: "Member" });
        const fns = await fetchAll("/api/v1/location/vNodeTree?ParentEntityId=" + encodeURIComponent(p.NodeEntityId));
        for (const f of fns.filter((n) => n.NodeTypeCode === "ProtectionFunction")) await postJson("/api/v1/scheme/AddSchemeMember", { SchemeEntityId: sel.value, MemberKind: "ProtectionFunction", MemberEntityId: f.EntityId, MemberRoleCode: "Member" });
        setStatus("action-status", "Added."); await load();
      } catch (e) { setStatus("action-status", "Refused: " + (e.status || "") + " " + e.message, true); ok.disabled = false; }
    });
    const row = el("div", "action-row"); row.appendChild(el("label", "inline", "Scheme ")); row.lastChild.appendChild(sel); row.appendChild(ok); body.appendChild(row);
  }
  $("btn-new").addEventListener("click", newScheme);
  $("btn-refresh").addEventListener("click", load);
  window.PnC.registerWorker();
  me().then((m) => { state.user = m; return loadStations(); }).then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
