// W8 (decisions #157–#158). The settings record: the flat legacy window's content in the platform's names — device, where,
// dates and state, notes — the parsed settings, the settings text as filed (read from the revision's file through the
// files endpoint, so a technician sees the settings in full as the legacy showed them), the files and evidence, and Compare
// with another revision of the same device (round 5 B4: a read of two revisions' parsed settings, or their texts line by
// line when nothing is parsed). What the platform does not model is said so, never invented.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, settingsText, legacyFree, legacyDetail } = window.PnC;
  const revision = qs().revision;
  const shown = (name) => legacyFree(name);
  const state = { row: null, parsed: [], text: null, revisions: [] };

  function dl(node, pairs) {
    node.textContent = "";
    for (const [k, v] of pairs) { node.appendChild(el("dt", null, k)); const dd = el("dd"); if (v instanceof Node) dd.appendChild(v); else dd.textContent = v == null || v === "" ? "—" : String(v); node.appendChild(dd); }
  }
  const notModelled = () => el("span", "muted", "not modelled");

  async function load() {
    if (!revision) { setStatus("status", "No revision in the address (setting.html?revision=…).", true); return; }
    let r;
    try { r = (await getJson("/api/v1/document/vSettingsRecord?RevisionRowId=" + encodeURIComponent(revision))).rows[0]; }
    catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); return; }
    if (!r) { setStatus("status", "No settings record with that revision is readable by you.", true); return; }
    state.row = r;
    $("title").textContent = shown(r.DeviceName) + " — rev " + (r.RevisionLabel || "?");
    const pill = $("state-pill"); pill.hidden = false; pill.textContent = r.GridState; pill.className = "pill " + (r.GridState === "Active" ? "effective" : r.GridState === "Outstanding" ? "draft" : "");
    if (r.WorkRequestEntityId) { const a = $("req-link"); a.hidden = false; a.href = "/request.html?id=" + r.WorkRequestEntityId; }
    setStatus("status", "Revision " + (r.RevisionStatus || "") + " · lifecycle " + (r.LifecycleState || "—") + " · " + (r.FileKind || "") + " " + (r.ParseStatus || ""));
    dl($("g-device"), [["Device", shown(r.DeviceName)], ["Model", (r.ModelCode || "") + (r.ModelName ? " — " + r.ModelName : "")], ["Manufacturer", r.ManufacturerName], ["Technology", r.Technology],
      ["Software version", r.FirmwareVersion], ["Serial number", r.SerialNumber], ["Voltage", r.VoltageClassCode], ["Functions", r.Functions || r.PositionName]]);
    dl($("g-where"), [["Location", (r.StationName || "") + (r.StationNumber ? " · " + r.StationNumber : "")], ["Scheme", r.SchemeName], ["Equipment", r.PanelName], ["Position", r.PositionName]]);
    dl($("g-dates"), [["Calculated", fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? " by " + r.CalculatedByDisplayName : "")], ["Verified", fmtWhen(r.VerifiedAt)],
      ["In service", r.InServiceFrom ? fmtWhen(r.InServiceFrom) + (r.InServiceTo ? " – " + fmtWhen(r.InServiceTo) : " – now") : "not in service"],
      ["Change request", legacyFree(r.WorkRequestTitle)], ["Action type", r.WorkTypeKey], ["Lifecycle", r.LifecycleState], ["Revision", (r.RevisionLabel || "") + " · " + (r.RevisionStatus || "")]]);
    await notes(r); await settings(r); await files(r); await revisions(r);
    if (location.hash === "#compare") compare();
  }

  state.detailRecord = null;
  async function notes(r) {
    const pairs = [];
    let detail = { notes: [], mp: [], it: [] };
    try {
      if (r.WorkRequestEntityId) {
        const recs = (await getJson("/api/v1/record/vRecord?WorkRequestEntityId=" + encodeURIComponent(r.WorkRequestEntityId) + "&RecordKindCode=ConfigurationFileRevision&take=200")).rows;
        const rec = recs.find((x) => String(x.SecondSubjectEntityId || "").toLowerCase() === String(revision).toLowerCase()) || (recs.length === 1 ? recs[0] : null);
        if (rec) { state.detailRecord = rec; detail = legacyDetail(rec.Summary); }
      }
    } catch (e) { /* no record read: the groups say so */ }
    try { const rv = (await getJson("/api/v1/document/vRevision?RowId=" + encodeURIComponent(revision))).rows[0]; if (rv) for (const k of ["ChangeNote", "Notes", "Description"]) if (rv[k]) pairs.push(["Revision " + k.toLowerCase(), legacyFree(rv[k])]); } catch (e) { /* no revision read */ }
    try { if (r.DocumentEntityId) { const d = (await getJson("/api/v1/document/vDocument?EntityId=" + encodeURIComponent(r.DocumentEntityId))).rows[0]; if (d) for (const k of ["Notes", "Description"]) if (d[k]) pairs.push(["Document " + k.toLowerCase(), legacyFree(d[k])]); } } catch (e) { /* no document read */ }
    const mp = detail.mp.concat(detail.it);
    dl($("g-mp"), mp.length ? mp : [["Class · use · responsibility", el("span", "muted", "not recorded")], ["CT / PT ratios", el("span", "muted", "not recorded")]]);
    const all = detail.notes.concat(pairs);
    dl($("g-notes"), all.length ? all : [["Notes", el("span", "muted", "none recorded")]]);
  }

  async function settings(r) {
    try {
      state.parsed = await fetchAll("/api/v1/document/vParsedSettingNamed?ConfigurationFileRevisionRowId=" + encodeURIComponent(revision) + "&orderBy=SettingCode");
      table($("settings"), state.parsed, [{ key: "SettingCode", label: "Setting" }, { key: "SettingName", label: "Name" }, { key: "GroupNumber", label: "Group" }, { key: "DisplayValue", label: "Value" }, { key: "UnitCode", label: "Unit" },
        { key: "MinValue", label: "Min" }, { key: "MaxValue", label: "Max" }, { key: "RangeCheck", label: "Range" }, { key: "RangeCheckNote", label: "Note" }]);
      $("settings-summary").textContent = state.parsed.length ? state.parsed.length + " parsed setting(s) from the " + r.FileKind + " file" : (r.FileKind === "NativeSettings" ? "The native (vendor) file is stored as is; no reader exists for it yet (#113)." : "No parsed settings; the text below is the record.");
    } catch (e) { $("settings-summary").textContent = "Settings: " + e.message; }
    try { state.text = await settingsText(revision); $("settings-text").textContent = state.text ? state.text.text : "No settings file is filed for this revision."; if (state.text) $("text-head").textContent = "Settings text as filed — " + state.text.name; }
    catch (e) { $("settings-text").textContent = "The settings text could not be read: " + (e.status || "") + " " + e.message; }
  }

  async function files(r) {
    const rows = [];
    try {
      for (const f of (await getJson("/api/v1/document/vFile?RevisionRowId=" + encodeURIComponent(revision) + "&take=100")).rows)
        rows.push({ what: "this revision's file", kind: f.FileRole, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: f.CreatedAt, fileRowId: f.RowId });
      if (r.WorkRequestEntityId) {
        const recs = (await getJson("/api/v1/record/vRecord?WorkRequestEntityId=" + encodeURIComponent(r.WorkRequestEntityId) + "&take=200")).rows;
        for (const rec of recs) {
          let links = [];
          try { links = (await getJson("/api/v1/document/vRevisionLink?SubjectKind=Record&SubjectEntityId=" + encodeURIComponent(rec.EntityId) + "&take=50")).rows; } catch (e) { links = []; }
          if (!links.length) { rows.push({ what: rec.RecordKindCode, kind: rec.OverallResult || "", name: rec.RecordKindCode === "ConfigurationFileRevision" ? "the migrated record's detail — shown in the groups above" : legacyFree(rec.Summary), when: rec.OccurredAt }); continue; }
          for (const l of links) {
            let fs = [];
            try { fs = (await getJson("/api/v1/document/vFile?RevisionRowId=" + encodeURIComponent(l.RevisionRowId) + "&take=50")).rows; } catch (e) { fs = []; }
            if (!fs.length) rows.push({ what: rec.RecordKindCode, kind: l.LinkKind, name: "(revision " + String(l.RevisionRowId).slice(0, 8) + ")", when: rec.OccurredAt });
            for (const f of fs) rows.push({ what: rec.RecordKindCode, kind: f.FileRole || l.LinkKind, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: rec.OccurredAt, fileRowId: f.RowId });
          }
        }
      }
      table($("files"), rows, [{ key: "what", label: "Record" }, { key: "kind", label: "Kind" }, { key: "name", label: "File / summary", render: (x) => { if (!x.fileRowId) return x.name || ""; const a = el("a", "row-link", x.name); a.href = "/api/v1/files/" + x.fileRowId; a.target = "_blank"; a.rel = "noopener"; return a; } }, { key: "mime", label: "Type" }, { key: "size", label: "Bytes" },
        { key: "sha", label: "SHA-256", render: (x) => (x.sha ? String(x.sha).slice(0, 12) + "…" : "") }, { key: "when", label: "When", render: (x) => fmtWhen(x.when) }]);
      $("files-summary").textContent = rows.length + " file(s) and record(s) — a file name opens the file (every open is a logged read, #144). The rationale document moves to the file store in a later wave (#159).";
    } catch (e) { $("files-summary").textContent = "Files: " + e.message; }
  }

  // ---- Compare (round 5 B4): the device's other designed revisions, one beside this one
  async function revisions(r) {
    try { state.revisions = (await fetchAll("/api/v1/document/vSettingsRecord?DeviceEntityId=" + encodeURIComponent(r.DeviceEntityId) + "&orderBy=-CalculatedAt")).filter((x) => x.RevisionRowId !== r.RevisionRowId); } catch (e) { state.revisions = []; }
    const sel = $("compare-with"); sel.textContent = "";
    for (const x of state.revisions) { const o = el("option", null, "rev " + (x.RevisionLabel || "?") + " · " + x.GridState + " · calculated " + fmtDate(x.CalculatedAt) + (x.WorkRequestTitle ? " · " + legacyFree(x.WorkRequestTitle) : "")); o.value = x.RevisionRowId; sel.appendChild(o); }
    $("btn-compare").disabled = !state.revisions.length; if (!state.revisions.length) $("btn-compare").title = "This device has no other designed revision";
  }
  async function compare() {
    if (!state.revisions.length) return;
    $("compare").hidden = false; $("compare").scrollIntoView({ behavior: "smooth" });
    const other = $("compare-with").value; const o = state.revisions.find((x) => x.RevisionRowId === other); if (!o) return;
    $("compare-summary").textContent = "Comparing…";
    try {
      const mine = state.parsed; const theirs = await fetchAll("/api/v1/document/vParsedSettingNamed?ConfigurationFileRevisionRowId=" + encodeURIComponent(other) + "&orderBy=SettingCode");
      if (mine.length || theirs.length) {
        const key = (p) => p.SettingCode + "|" + (p.GroupNumber == null ? "" : p.GroupNumber);
        const m = new Map(mine.map((p) => [key(p), p])), t = new Map(theirs.map((p) => [key(p), p]));
        const keys = [...new Set([...m.keys(), ...t.keys()])].sort();
        const rows = keys.map((k) => { const a = m.get(k), b = t.get(k); const av = a ? a.DisplayValue : null, bv = b ? b.DisplayValue : null; return { code: (a || b).SettingCode, name: (a || b).SettingName, group: (a || b).GroupNumber, mine: av, theirs: bv, diff: av !== bv }; });
        const n = rows.filter((x) => x.diff).length;
        table($("compare-table"), rows, [{ key: "code", label: "Setting" }, { key: "name", label: "Name" }, { key: "group", label: "Group" }, { key: "mine", label: "This revision" }, { key: "theirs", label: "rev " + (o.RevisionLabel || "?") }], (tr, x) => { if (x.diff) tr.classList.add("diff"); });
        $("compare-summary").textContent = n + " of " + rows.length + " setting(s) differ between rev " + (state.row.RevisionLabel || "?") + " and rev " + (o.RevisionLabel || "?") + " (differences highlighted).";
      } else {
        const a = state.text ? state.text.text.split(/\r?\n/) : [], bt = await settingsText(other); const b = bt ? bt.text.split(/\r?\n/) : [];
        const sa = new Set(a), sb = new Set(b); const n = Math.max(a.length, b.length); const rows = [];
        for (let i = 0; i < n; i++) rows.push({ i: i + 1, mine: a[i], theirs: b[i], diff: (a[i] != null && !sb.has(a[i])) || (b[i] != null && !sa.has(b[i])) });
        table($("compare-table"), rows, [{ key: "i", label: "Line" }, { key: "mine", label: "This revision" }, { key: "theirs", label: "rev " + (o.RevisionLabel || "?") }], (tr, x) => { if (x.diff) tr.classList.add("diff"); });
        $("compare-summary").textContent = rows.filter((x) => x.diff).length + " line(s) present in one text and not the other (no parsed settings on either; the texts are compared line by line).";
      }
    } catch (e) { $("compare-summary").textContent = "Compare: " + (e.status || "") + " " + e.message; }
  }
  $("btn-compare").addEventListener("click", compare);
  $("compare-with").addEventListener("change", compare);
  $("btn-compare-close").addEventListener("click", () => { $("compare").hidden = true; });
  $("btn-close").addEventListener("click", () => { if (history.length > 1 && document.referrer.includes("/settings.html")) history.back(); else location.href = "/settings.html"; });
  $("btn-docs").addEventListener("click", () => $("files-panel").scrollIntoView({ behavior: "smooth" }));

  window.PnC.registerWorker();
  me().then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
