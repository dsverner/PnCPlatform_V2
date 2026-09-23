// docs/design/API.md §9 and PROCEDURE-ENGINE §8 (W5, decisions #119–#120). The authoring screen: a JSON editor over the
// definitions endpoints. Nothing here knows a rule — every check is the API's dry run (schema, grammar, types, the
// database's structural rules), the store is process.Add*Version, approval is the database's with segregation.
(function () {
  "use strict";
  const { $, text, getJson, postJson, el } = window.PnC;
  const KINDS = { "Program.Procedure": "Procedures", "Program.Workflow": "Workflows", "Program.Screen": "Screens (#165)" };
  const SKELETON = {
    g: 1, kind: "procedure", key: "NEW_PROCEDURE", name: "New procedure", description: "", subjectKind: "WorkRequest",
    roles: { engineer: { role: "PCEngineer" } },
    outcomes: ["Completed"],
    body: { block: "sequence", id: "MAIN", items: [
      { block: "step", id: "FIRST_STEP", title: "[1] The first step", instruction: "What the person does.", role: "engineer", record: { kind: "Attestation" } },
    ] },
  };

  const state = { current: null, definitions: [], versions: [], permissions: [], checkTimer: null, lastChecked: null };
  const can = (code) => state.permissions.includes(code);

  // ---- identity and permissions (/me carries the permission codes of the roles in force — W5)
  async function me() {
    try {
      const m = await getJson("/api/v1/me");
      text("who", (m.person.displayName || m.user.userPrincipalName) + (window.PnC.devUser() ? " (DEV act-as)" : ""));
      state.permissions = m.permissions || [];
      const notes = [];
      if (!can("Definition.Modify")) notes.push("you hold no Definition.Modify grant, so Save is disabled");
      if (!can("Definition.Approve")) notes.push("you hold no Definition.Approve grant, so Approve is disabled");
      $("permission-note").hidden = notes.length === 0;
      $("permission-note").textContent = notes.length ? "Read-only: " + notes.join("; ") + ". The API decides; this only says what it will refuse." : "";
      return true;
    } catch (e) {
      text("who", e.status === 401 ? "not signed in — sign in on the home page" : "error: " + e.message);
      state.permissions = [];
      return false;
    }
  }

  function setButtons() {
    const c = state.current;
    $("btn-save").disabled = !can("Definition.Modify") || !$("doc").value.trim();
    $("btn-approve").disabled = !can("Definition.Approve") || !c || !c.versionRowId || c.status !== "Draft";
    $("btn-exception").disabled = !can("Definition.Approve") || !c || !c.versionRowId || c.status !== "Draft";
    $("btn-check").disabled = !$("doc").value.trim();
  }

  // ---- the list: definitions of the two kinds and their versions
  async function loadList() {
    try {
      const [p, w, v] = await Promise.all([
        getJson("/api/v1/config/vDefinition?DefinitionKind=Program.Procedure&take=500"),
        getJson("/api/v1/config/vDefinition?DefinitionKind=Program.Workflow&take=500"),
        getJson("/api/v1/config/vDefinitionVersion?take=500&orderBy=VersionNumber"),
      ]);
      state.definitions = p.rows.concat(w.rows);
      state.versions = v.rows;
      renderList();
    } catch (e) { text("list-summary", e.message); }
  }

  function renderList() {
    const ul = $("definitions"); ul.textContent = "";
    let versionCount = 0;
    for (const kind of Object.keys(KINDS)) {
      const defs = state.definitions.filter((d) => d.DefinitionKind === kind).sort((a, b) => a.DefinitionKey.localeCompare(b.DefinitionKey));
      if (!defs.length) continue;
      ul.appendChild(el("li", "group", KINDS[kind]));
      for (const d of defs) {
        const li = el("li", "def");
        li.appendChild(el("div", "def-key", d.DefinitionKey));
        li.appendChild(el("div", "def-name muted small", d.Name || ""));
        const vs = state.versions.filter((x) => x.DefinitionEntityId.toLowerCase() === d.EntityId.toLowerCase()).sort((a, b) => b.VersionNumber - a.VersionNumber);
        const vl = el("ul", "versions");
        for (const x of vs) {
          versionCount++;
          const b = el("button", "version " + x.Status.toLowerCase());
          b.type = "button";
          b.textContent = "v" + x.VersionNumber + " · " + x.Status + (x.ApprovedAt ? " · " + new Date(x.ApprovedAt).toLocaleDateString() : "");
          b.title = x.ChangeNote || "";
          b.dataset.row = x.RowId;
          if (state.current && state.current.versionRowId && state.current.versionRowId.toLowerCase() === x.RowId.toLowerCase()) b.classList.add("selected");
          b.addEventListener("click", () => loadVersion(x.RowId));
          const li2 = el("li"); li2.appendChild(b); vl.appendChild(li2);
        }
        li.appendChild(vl);
        ul.appendChild(li);
      }
    }
    text("list-summary", state.definitions.length + " definitions · " + versionCount + " versions");
  }

  // ---- loading one version: the API prints every expression back as grammar text
  async function loadVersion(rowId) {
    try {
      setStatus("Loading…");
      const d = await getJson("/api/v1/definitions/documents/" + rowId);
      state.current = { versionRowId: d.versionRowId, status: d.status, key: d.key, kind: d.kind, versionNumber: d.versionNumber };
      $("doc").value = JSON.stringify(d.document, null, 2);
      $("change-note").value = "";
      showTitle();
      clearErrors();
      setStatus("Loaded " + d.key + " v" + d.versionNumber + " (" + d.status + ")" + (d.changeNote ? " — " + d.changeNote : "") + ". Edit and Save to store the next version.");
      renderList();
      setButtons();
      scheduleCheck();
    } catch (e) { setStatus("Could not load: " + e.message, true); }
  }

  function showTitle() {
    const c = state.current;
    text("doc-key", c ? c.key + (c.versionNumber ? " v" + c.versionNumber : " (unsaved)") : "No document loaded");
    const pill = $("doc-status");
    pill.hidden = !c || !c.status;
    if (c && c.status) { pill.textContent = c.status; pill.className = "pill " + c.status.toLowerCase(); }
  }

  function setStatus(msg, bad) { const s = $("status"); s.textContent = msg; s.className = "status " + (bad ? "bad" : "muted"); }

  // ---- the document in the editor
  function parseDoc() {
    const t = $("doc").value;
    try { return { doc: JSON.parse(t) }; }
    catch (e) {
      const m = /position (\d+)/.exec(e.message);
      return { error: { path: "$", code: "json", message: e.message, offset: m ? Number(m[1]) : 0 } };
    }
  }

  // ---- the live check: POST …/documents?dryRun=true — the whole document, nothing stored
  function scheduleCheck() {
    clearTimeout(state.checkTimer);
    $("check-state").textContent = "checking…";
    state.checkTimer = setTimeout(check, 700);
  }
  async function check() {
    const { doc, error } = parseDoc();
    if (error) { showErrors([error]); $("check-state").textContent = "not valid JSON"; return null; }
    try {
      const r = await postJson("/api/v1/definitions/documents?dryRun=true", { document: doc });
      clearErrors();
      $("check-state").textContent = "checked · " + r.kind + " " + r.key + " · no problems · canonical " + r.canonicalLength + " chars";
      state.lastChecked = $("doc").value;
      return r;
    } catch (e) {
      if (e.code === "document_invalid" && e.body && e.body.errors) { showErrors(e.body.errors); $("check-state").textContent = e.body.errors.length + " problem(s)"; }
      else { showErrors([{ path: "$", code: e.code || String(e.status || ""), message: e.message }]); $("check-state").textContent = "refused"; }
      return null;
    }
  }

  function clearErrors() { $("errors").textContent = ""; }
  function showErrors(errors) {
    const ol = $("errors"); ol.textContent = "";
    const t = $("doc").value;
    for (const er of errors) {
      const li = el("li", "error");
      const offset = er.offset != null ? er.offset : locate(t, er.path);
      const where = offset >= 0 ? lineCol(t, offset) : null;
      const b = el("button", "path", er.path + (where ? "  (line " + where.line + ")" : ""));
      b.type = "button";
      b.addEventListener("click", () => { if (offset >= 0) goTo(offset); });
      li.appendChild(b);
      li.appendChild(el("span", "code", er.code));
      li.appendChild(el("span", "msg", er.message));
      ol.appendChild(li);
    }
  }

  function goTo(offset) {
    const ta = $("doc");
    ta.focus();
    ta.setSelectionRange(offset, offset);
    const before = ta.value.slice(0, offset);
    const line = before.split("\n").length - 1;
    const lineHeight = parseFloat(getComputedStyle(ta).lineHeight) || 18;
    ta.scrollTop = Math.max(0, line * lineHeight - ta.clientHeight / 2);
    showCaret();
  }
  function lineCol(t, offset) {
    const before = t.slice(0, offset);
    const lines = before.split("\n");
    return { line: lines.length, col: lines[lines.length - 1].length + 1 };
  }
  function showCaret() {
    const ta = $("doc");
    const lc = lineCol(ta.value, ta.selectionStart);
    text("caret", "line " + lc.line + ", col " + lc.col);
  }

  // The JSON path of an error ($.body.items[3].precondition) → the offset of that value in the editor's text. A small
  // scanner over the text keeping the path of the value it is at, so the author is taken to the line without reformatting.
  function locate(t, path) {
    if (!path || path[0] !== "$") return -1;
    const segs = [];
    const re = /\.([^.\[\]]+)|\[(\d+)\]/g;
    let m;
    while ((m = re.exec(path.slice(1))) !== null) segs.push(m[1] !== undefined ? m[1] : Number(m[2]));
    const stack = [];
    let i = 0;
    const n = t.length;
    const matches = () => {
      if (stack.length !== segs.length) return false;
      for (let k = 0; k < segs.length; k++) { const f = stack[k]; if ((f.type === "obj" ? f.key : f.index) !== segs[k]) return false; }
      return true;
    };
    const readString = () => {
      let j = i + 1, out = "";
      while (j < n) {
        const c = t[j];
        if (c === "\\") { const e = t[j + 1]; if (e === "u") { out += String.fromCharCode(parseInt(t.substr(j + 2, 4), 16)); j += 6; } else { out += ({ n: "\n", t: "\t", r: "\r", b: "\b", f: "\f" })[e] || e; j += 2; } }
        else if (c === "\"") { j++; break; }
        else { out += c; j++; }
      }
      i = j; return out;
    };
    while (i < n) {
      const c = t[i];
      if (c === " " || c === "\n" || c === "\r" || c === "\t") { i++; continue; }
      const top = stack[stack.length - 1];
      if (top && top.type === "obj" && top.expectKey) {
        if (c === "}") { stack.pop(); i++; continue; }
        if (c === "\"") { top.key = readString(); top.expectKey = false; continue; }
        i++; continue;
      }
      if (c === ":") { i++; continue; }
      if (c === ",") { if (top) { if (top.type === "obj") top.expectKey = true; else top.index++; } i++; continue; }
      if (c === "}" || c === "]") { stack.pop(); i++; continue; }
      if (top && top.type === "arr" && top.index < 0) top.index = 0;
      if (matches()) return i;
      if (c === "{") { stack.push({ type: "obj", key: null, expectKey: true }); i++; continue; }
      if (c === "[") { stack.push({ type: "arr", index: -1 }); i++; continue; }
      if (c === "\"") { readString(); continue; }
      while (i < n && ",}] \n\r\t".indexOf(t[i]) < 0) i++;
    }
    return -1;
  }

  // ---- save: the next Draft version (idempotent on content — the API answers existing=true for the same canonical text)
  async function save() {
    const { doc, error } = parseDoc();
    if (error) { showErrors([error]); return; }
    try {
      setStatus("Saving…");
      const r = await postJson("/api/v1/definitions/documents", { document: doc, changeNote: $("change-note").value.trim() || null });
      await loadList();
      state.current = { versionRowId: r.versionRowId, key: r.key, kind: r.kind, versionNumber: r.versionNumber, status: null };
      const row = state.versions.find((x) => x.RowId.toLowerCase() === String(r.versionRowId).toLowerCase());
      if (row) state.current.status = row.Status;
      showTitle(); renderList(); setButtons();
      clearErrors();
      setStatus(r.existing ? "Nothing new: this exact content is already stored as " + r.key + " v" + r.versionNumber + " (" + (state.current.status || "?") + ")."
        : "Saved " + r.key + " v" + r.versionNumber + " as a Draft. A second person approves it.");
    } catch (e) {
      if (e.code === "document_invalid" && e.body && e.body.errors) { showErrors(e.body.errors); setStatus("Not saved: " + e.body.errors.length + " problem(s).", true); }
      else setStatus("Not saved: " + (e.status ? e.status + " " : "") + e.message, true);
    }
  }

  // ---- approve: the database's, segregation included (Author/Approve on DefinitionVersion → 409 in the rule's words)
  async function approve() {
    const c = state.current;
    if (!c || !c.versionRowId) return;
    try {
      setStatus("Approving…");
      const r = await postJson("/api/v1/definitions/documents/" + c.versionRowId + "/approve", {});
      await loadList();
      const row = state.versions.find((x) => x.RowId.toLowerCase() === String(c.versionRowId).toLowerCase());
      c.status = row ? row.Status : "Effective";
      showTitle(); renderList(); setButtons();
      setStatus("Approved " + c.key + " v" + c.versionNumber + " → " + c.status + (r.kind === "Program.Procedure" ? " · " + r.projectedSteps + " steps projected" : "") + ".");
      loadMigration();
    } catch (e) { setStatus("Not approved: " + (e.status ? e.status + " " : "") + e.message, true); }
  }

  // ---- #232 (the owner, 2026-09-23): where the rule does not let the author approve their own version, another person who could
  // approve it lets the author do so, once, within 24 hours — from their own sign-in; the author never names who approved
  async function approveException() {
    const c = state.current;
    if (!c || !c.versionRowId) return;
    const row = state.versions.find((x) => x.RowId.toLowerCase() === String(c.versionRowId).toLowerCase());
    try {
      const a = row && row.CreatedBy ? await getJson("/api/v1/personnel/vActor?ActorId=" + row.CreatedBy + "&take=1") : { rows: [] };
      const person = a.rows[0] && a.rows[0].PersonEntityId;
      if (!person) { setStatus("The author of this version is not a person, so there is no one to let approve it.", true); return; }
      const reason = window.prompt("Why may the author approve " + c.key + " v" + c.versionNumber + " themselves?");
      if (!reason || !reason.trim()) return;
      setStatus("Recording the exception…");
      const r = await postJson("/api/v1/process/override-approvals", { subjectKind: "DefinitionVersion", subjectEntityId: c.versionRowId, action: "Approve", forPersonEntityId: person, reason: reason.trim() });
      setStatus("Exception recorded: the author can approve " + c.key + " v" + c.versionNumber + " once, until " + new Date(r.expiresAt).toLocaleString() + ".");
    } catch (e) { setStatus("Exception not recorded: " + String(e.message).replace(/^[a-z]+\.[A-Za-z]+: /, ""), true); }
  }

  // ---- the expression bench
  async function bench(ev) {
    ev.preventDefault();
    const body = { expression: $("bench-expr").value };
    if ($("bench-subject").value) body.subjectKind = $("bench-subject").value;
    if ($("bench-value").value) body.env = { value: { type: $("bench-value").value } };
    const out = $("bench-out");
    try {
      const r = await postJson("/api/v1/formula/check", body);
      out.className = "out " + (r.ok ? "good" : "bad");
      out.textContent = r.ok
        ? "type: " + r.type + "\nfacts: " + (r.facts.length ? r.facts.join(", ") : "none") + "\ncanonical: " + JSON.stringify(r.canonical)
        : r.code + " at " + (r.position == null ? "?" : r.position) + ": " + r.message;
    } catch (e) { out.className = "out bad"; out.textContent = (e.status || "") + " " + e.message; }
  }

  // ---- the migration list
  async function loadMigration() {
    try {
      const r = await getJson("/api/v1/process/vMigrationList?take=500");
      const tb = $("migration-table").querySelector("tbody"); tb.textContent = "";
      for (const row of r.rows) {
        const tr = el("tr");
        tr.appendChild(el("td", "mono", String(row.ProcedureInstanceEntityId).slice(0, 8) + (row.IsRootProcedure ? "" : " (callee)")));
        tr.appendChild(el("td", null, row.CalleeKey));
        tr.appendChild(el("td", null, "v" + row.PinnedVersionNumber));
        tr.appendChild(el("td", null, "v" + row.CurrentVersionNumber + " from " + new Date(row.CurrentEffectiveFrom).toLocaleString()));
        tr.appendChild(el("td", null, row.State));
        tr.appendChild(el("td", null, new Date(row.StartedAt).toLocaleString()));
        tb.appendChild(tr);
      }
      text("migration-summary", r.rows.length ? r.rows.length + " run(s) awaiting a ruling" : "No run is waiting on a version ruling.");
    } catch (e) { text("migration-summary", e.status === 403 ? "Not visible to you (Definition.Read)." : e.message); }
  }

  // ---- wiring
  $("btn-new").addEventListener("click", () => {
    state.current = { versionRowId: null, status: null, key: SKELETON.key, kind: "procedure", versionNumber: null };
    $("doc").value = JSON.stringify(SKELETON, null, 2);
    showTitle(); renderList(); clearErrors(); setButtons();
    setStatus("A skeleton. Change the key, add steps, Check, then Save.");
    scheduleCheck();
  });
  $("btn-check").addEventListener("click", () => { clearTimeout(state.checkTimer); check(); });
  $("btn-save").addEventListener("click", save);
  $("btn-approve").addEventListener("click", approve);
  $("btn-exception").addEventListener("click", approveException);
  $("doc").addEventListener("input", () => { setButtons(); scheduleCheck(); });
  $("doc").addEventListener("keyup", showCaret);
  $("doc").addEventListener("click", showCaret);
  $("doc").addEventListener("keydown", (ev) => {
    if (ev.key === "Tab") { ev.preventDefault(); const ta = ev.target; const s = ta.selectionStart; ta.setRangeText("  ", s, ta.selectionEnd, "end"); ta.dispatchEvent(new Event("input")); }
  });
  $("bench-form").addEventListener("submit", bench);

  window.PnC.registerWorker();
  me().then((ok) => { setButtons(); if (ok) { loadList(); loadMigration(); } else { text("list-summary", "Sign in on the home page first."); } });
})();
