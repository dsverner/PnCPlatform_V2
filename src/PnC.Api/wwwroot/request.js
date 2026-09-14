// W8 (decisions #157–#158). The change request in the legacy shape with what Dev_Final showed: a stage bar over the
// request workflow's states (read from the Effective SETTINGS_CHANGE_REQUEST definition, current = RequestState), the
// header in the legacy order (relay, action type, requested by, equipment), the notes block, the three completion tracks
// side by side as read-only radio rows (Change in progress · Complete · NA) with date and notes — the software track
// noted, not modelled (#58) — Post Request / Close, Go to Settings, Go to Document, and the devices grid. The actions
// are the workflow's transitions; the API refuses in the rule's words and the screen shows them.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, postJson, legacyFree } = window.PnC;
  const id = qs().id;
  const shown = (name) => legacyFree(name);
  const state = { row: null, user: null, states: null };

  function dl(node, pairs) {
    node.textContent = "";
    for (const [k, v] of pairs) { node.appendChild(el("dt", null, k)); const dd = el("dd"); if (v instanceof Node) dd.appendChild(v); else dd.textContent = v == null || v === "" ? "—" : String(v); node.appendChild(dd); }
  }
  function link(href, text, external) { const a = el("a", "row-link", text); a.href = href; if (external) { a.target = "_blank"; a.rel = "noopener"; } return a; }

  // the stage bar: the workflow's states in document order, the current one marked (a definition, never a list in code)
  async function stages(workflowKey, current) {
    if (!state.states) {
      try {
        const defs = (await getJson("/api/v1/config/vDefinition?DefinitionKind=Program.Workflow&DefinitionKey=" + encodeURIComponent(workflowKey || "SETTINGS_CHANGE_REQUEST") + "&take=5")).rows;
        const vs = defs.length ? (await getJson("/api/v1/config/vDefinitionVersion?DefinitionEntityId=" + encodeURIComponent(defs[0].EntityId) + "&Status=Effective&take=5")).rows : [];
        const doc = vs.length && vs[0].PayloadText ? JSON.parse(vs[0].PayloadText) : null;
        state.states = doc && Array.isArray(doc.states) ? doc.states.map((s) => ({ code: s.code, name: s.name || s.code, terminal: !!s.terminal, cancellation: !!s.cancellation })) : [];
      } catch (e) { state.states = []; }
    }
    const ol = $("stages"); ol.textContent = "";
    const list = state.states.length ? state.states : [{ code: current || "—", name: current || "not started" }];
    let passed = true;
    for (const s of list) {
      if (s.cancellation && s.code !== current) continue;
      const li = el("li", "stage" + (s.code === current ? " current" : passed ? " done" : ""), s.name);
      if (s.code === current) passed = false;
      ol.appendChild(li);
    }
  }

  async function load() {
    if (!id) { setStatus("status", "No request id in the address (request.html?id=…).", true); return; }
    try {
      const r = (await getJson("/api/v1/work/vChangeRequestStatus?WorkRequestEntityId=" + encodeURIComponent(id))).rows[0];
      if (!r) { setStatus("status", "No change request with that id is readable by you.", true); return; }
      state.row = r;
      $("title").textContent = legacyFree(r.Title) || "Change request";
      setStatus("status", "Request " + (r.RequestState || "not started") + (r.ProcedureState ? " · procedure " + r.ProcedureState + (r.ProcedureOutcome ? " / " + r.ProcedureOutcome : "") : "") + (r.LifecycleState ? " · package " + r.LifecycleState : ""));
      await stages(r.WorkflowKey, r.RequestState);
      dl($("header"), [
        ["Relay", r.EquipmentName ? shown(r.EquipmentName) : (r.ScopeKind === "Asset" ? shown(r.ScopeName) : "—")], ["Action type", (r.WorkTypeKey || "") + (r.WorkTypeName ? " — " + r.WorkTypeName : "")], ["Requested by", r.RequestedByDisplayName],
        ["Requested", fmtWhen(r.RequestedAt)], ["Location", r.StationName], ["Equipment / scope", (r.ScopeKind || "") + " " + shown(r.ScopeName)],
        ["Devices", r.DeviceCount], ["Priority", r.PriorityCode], ["Outage", r.OutageRequired ? "required " + fmtWhen(r.OutageWindowStartAt) + " – " + fmtWhen(r.OutageWindowEndAt) : "not required"],
        ["Return to service", r.ReturnToServiceAt ? fmtWhen(r.ReturnToServiceAt) : (r.RtsStepState ? "step " + r.RtsStepState : "—")], ["Started", fmtWhen(r.RequestStartedAt)], ["Completed", fmtWhen(r.RequestCompletedAt)],
      ]);
      dl($("notes"), [["Description", r.Description], ["Special instructions", r.SpecialInstructions], ["Notes", r.Notes]]);
      track($("track-doc"), r.DocumentationStatus, [["Date", fmtWhen(r.DocumentationAt)], ["Drawings", r.DrawingsOutcome === "NoneAffected" ? "none affected" : r.DrawingsOutcome || "—"],
        ["Document", r.DocumentationLink ? link(r.DocumentationLink, r.DocumentationLink, true) : "—"], ["Revision", (r.DocumentationRevisionLabel || "") + (r.DocumentationRevisedOn ? " revised " + fmtDate(r.DocumentationRevisedOn) : "")], ["Notes", r.DocumentationNote]]);
      track($("track-db"), r.DatabaseStatus, [["Date", fmtWhen(r.DatabaseAt)], ["Baseline record", r.BaselineRecordEntityId ? "recorded" : "—"], ["Notes", r.DatabaseBlockState ? "block " + r.DatabaseBlockState : "—"]]);
      track($("track-sw"), null, [["Status", el("span", "muted", "not modelled — the legacy software rows carry over as notes on the request (#58)")], ["Notes", r.Notes]]);
      $("btn-settings").href = "/settings.html?WorkRequestEntityId=" + encodeURIComponent(id) + "&GridState=" + (r.LifecycleState === "InService" ? "Active" : "Outstanding");
      if (r.DocumentationLink) { $("btn-doc").hidden = false; $("btn-doc").href = r.DocumentationLink; }
      $("btn-start").disabled = !(r.RequestState === "Raised" && state.user && state.user.can("WorkRequest.Modify"));
      $("btn-close").disabled = !(r.RequestState === "InProgress" && state.user && state.user.can("WorkRequest.Modify"));
      $("btn-cancel").disabled = !((r.RequestState === "Raised" || r.RequestState === "InProgress") && state.user && state.user.can("WorkRequest.Modify"));
      await devices();
    } catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
  }
  // a track: the legacy's three radio buttons, read-only, set from the engine's block state; then its facts
  function track(node, status, pairs) {
    const radios = node.querySelector(".radios"); radios.textContent = "";
    const opts = [["In Progress", "Change in progress"], ["Complete", "Complete"], ["NA", "NA"]];
    for (const [code, label] of opts) {
      const lab = el("label", "radio"); const rb = el("input"); rb.type = "radio"; rb.disabled = true; rb.checked = status === code; rb.name = node.id;
      lab.appendChild(rb); lab.appendChild(document.createTextNode(" " + label)); radios.appendChild(lab);
    }
    if (status && !opts.some(([c]) => c === status)) radios.appendChild(el("span", "pill", status));
    dl(node.querySelector("dl"), pairs);
  }

  async function devices() {
    const rows = await fetchAll("/api/v1/document/vSettingsRecord?WorkRequestEntityId=" + encodeURIComponent(id) + "&orderBy=DeviceName");
    table($("devices"), rows, [
      { key: "DeviceName", label: "Device", render: (r) => shown(r.DeviceName) }, { key: "GridState", label: "State" }, { key: "SchemeName", label: "Scheme" }, { key: "PanelName", label: "Equipment" }, { key: "ModelCode", label: "Model" },
      { key: "Functions", label: "Functions" }, { key: "FileKind", label: "File" }, { key: "ParseStatus", label: "Parsed" },
      { key: "CalculatedAt", label: "Calculated", render: (r) => fmtDate(r.CalculatedAt) }, { key: "VerifiedAt", label: "Verified", render: (r) => fmtDate(r.VerifiedAt) },
      { key: "_", label: "", cls: "noprint", render: (r) => link("/setting.html?revision=" + r.RevisionRowId, "Record") },
    ]);
    $("devices-summary").textContent = rows.length + " designed revision(s) in this change";
  }

  async function transition(name, reason) {
    const r = state.row; if (!r || !r.RequestWorkflowInstanceEntityId) { setStatus("status", "This request has no workflow instance to transition.", true); return; }
    try {
      const x = await postJson("/api/v1/process/workflow-instances/" + r.RequestWorkflowInstanceEntityId + "/transitions", reason ? { name, reason } : { name });
      setStatus("status", name + " → " + x.toState + ".");
      await load();
    } catch (e) { setStatus("status", name + " refused: " + (e.status || "") + " " + e.message, true); }
  }
  $("btn-start").addEventListener("click", () => transition("Start"));
  $("btn-close").addEventListener("click", () => transition("Close"));
  $("btn-cancel").addEventListener("click", () => { const reason = $("cancel-reason").value.trim(); if (!reason) { setStatus("status", "A reason is required to cancel (the workflow says so).", true); return; } transition("Cancel", reason); });

  window.PnC.registerWorker();
  me().then((m) => { state.user = m; return load(); }).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
