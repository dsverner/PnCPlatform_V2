// W6 (decisions #127, #130). The legacy change-request / status window over work.vChangeRequestStatus: one row is the whole
// header and both tracks; the devices are the settings grid filtered to this request; the actions are the request
// workflow's transitions (Start; Close, guarded by the procedure's completion; Cancel with a reason). The API refuses in
// the rule's words and the screen shows them.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, postJson } = window.PnC;
  const id = qs().id;
  const state = { row: null, user: null };

  function dl(node, pairs) {
    node.textContent = "";
    for (const [k, v] of pairs) { node.appendChild(el("dt", null, k)); const dd = el("dd"); if (v instanceof Node) dd.appendChild(v); else dd.textContent = v == null || v === "" ? "—" : String(v); node.appendChild(dd); }
  }
  function link(href, text, external) { const a = el("a", "row-link", text); a.href = href; if (external) { a.target = "_blank"; a.rel = "noopener"; } return a; }

  async function load() {
    if (!id) { setStatus("status", "No request id in the address (request.html?id=…).", true); return; }
    try {
      const r = (await getJson("/api/v1/work/vChangeRequestStatus?WorkRequestEntityId=" + encodeURIComponent(id))).rows[0];
      if (!r) { setStatus("status", "No change request with that id is readable by you.", true); return; }
      state.row = r;
      $("title").textContent = r.Title || "Change request";
      setStatus("status", "Request " + (r.RequestState || "not started") + (r.ProcedureState ? " · procedure " + r.ProcedureState + (r.ProcedureOutcome ? " / " + r.ProcedureOutcome : "") : "") + (r.LifecycleState ? " · package " + r.LifecycleState : ""));
      dl($("header"), [
        ["Relay ID / title", r.Title], ["Action type", (r.WorkTypeKey || "") + (r.WorkTypeName ? " — " + r.WorkTypeName : "")], ["Requested by", r.RequestedByDisplayName],
        ["Requested", fmtWhen(r.RequestedAt)], ["Location", r.StationName], ["Equipment", r.EquipmentName || r.ScopeName],
        ["Scope", (r.ScopeKind || "") + " " + (r.ScopeName || "")], ["Devices", r.DeviceCount], ["Priority", r.PriorityCode],
        ["Outage", r.OutageRequired ? "required " + fmtWhen(r.OutageWindowStartAt) + " – " + fmtWhen(r.OutageWindowEndAt) : "not required"],
        ["Return to service", r.ReturnToServiceAt ? fmtWhen(r.ReturnToServiceAt) : (r.RtsStepState ? "step " + r.RtsStepState : "—")],
        ["Notes", r.Notes], ["Description", r.Description],
      ]);
      dl($("track-doc").querySelector("dl"), [
        ["Status", pill(r.DocumentationStatus)], ["Date", fmtWhen(r.DocumentationAt)],
        ["Drawings", r.DrawingsOutcome === "NoneAffected" ? "none affected" : r.DrawingsOutcome || "—"],
        ["Go to document", r.DocumentationLink ? link(r.DocumentationLink, r.DocumentationLink, true) : "—"],
        ["Revision", (r.DocumentationRevisionLabel || "") + (r.DocumentationRevisedOn ? " revised " + fmtDate(r.DocumentationRevisedOn) : "")], ["Note", r.DocumentationNote],
      ]);
      dl($("track-db").querySelector("dl"), [
        ["Status", pill(r.DatabaseStatus)], ["Date", fmtWhen(r.DatabaseAt)],
        ["Baseline record", r.BaselineRecordEntityId ? String(r.BaselineRecordEntityId).slice(0, 8) : "—"],
        ["Go to settings page", link("/settings.html?WorkRequestEntityId=" + encodeURIComponent(id) + "&GridState=" + (r.LifecycleState === "InService" ? "Active" : "Outstanding"), "the devices below, in the grid")],
      ]);
      $("btn-start").disabled = !(r.RequestState === "Raised" && state.user && state.user.can("WorkRequest.Modify"));
      $("btn-close").disabled = !(r.RequestState === "InProgress" && state.user && state.user.can("WorkRequest.Modify"));
      $("btn-cancel").disabled = !((r.RequestState === "Raised" || r.RequestState === "InProgress") && state.user && state.user.can("WorkRequest.Modify"));
      await devices();
    } catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); }
  }
  function pill(s) { const p = el("span", "pill " + (s === "Complete" ? "effective" : s === "In Progress" ? "draft" : ""), s || "—"); return p; }

  async function devices() {
    const rows = await fetchAll("/api/v1/document/vSettingsRecord?WorkRequestEntityId=" + encodeURIComponent(id) + "&orderBy=DeviceName");
    table($("devices"), rows, [
      { key: "DeviceName", label: "Device" }, { key: "GridState", label: "State" }, { key: "PositionName", label: "Equipment" }, { key: "ModelCode", label: "Model" },
      { key: "Functions", label: "Functions" }, { key: "FileKind", label: "File" }, { key: "ParseStatus", label: "Parsed" },
      { key: "CalculatedAt", label: "Calculated", render: (r) => fmtDate(r.CalculatedAt) }, { key: "VerifiedAt", label: "Verified", render: (r) => fmtDate(r.VerifiedAt) },
      { key: "_", label: "", cls: "noprint", render: (r) => link("/setting.html?revision=" + r.RevisionRowId, "Display") },
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
