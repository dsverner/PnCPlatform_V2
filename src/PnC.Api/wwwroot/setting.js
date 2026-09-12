// W6 (decision #127). The legacy setting display: the flat record in its five groups, composed from the settings-record
// row, the parsed settings with their definitions, the revision's files and the run's evidence records. What the
// platform does not model (CT/PT ratios, the free-text overflow columns) is said so, never invented.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson } = window.PnC;
  const revision = qs().revision;
  const NOT_MODELLED = el("span", "muted", "not modelled");

  function dl(node, pairs) {
    node.textContent = "";
    for (const [k, v] of pairs) { node.appendChild(el("dt", null, k)); const dd = el("dd"); if (v instanceof Node) dd.appendChild(v.cloneNode(true)); else dd.textContent = v == null || v === "" ? "—" : String(v); node.appendChild(dd); }
  }

  async function load() {
    if (!revision) { setStatus("status", "No revision in the address (setting.html?revision=…).", true); return; }
    let r;
    try { r = (await getJson("/api/v1/document/vSettingsRecord?RevisionRowId=" + encodeURIComponent(revision))).rows[0]; }
    catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); return; }
    if (!r) { setStatus("status", "No settings record with that revision is readable by you.", true); return; }
    $("title").textContent = r.DeviceName + " — rev " + (r.RevisionLabel || "?");
    const pill = $("state-pill"); pill.hidden = false; pill.textContent = r.GridState; pill.className = "pill " + (r.GridState === "Active" ? "effective" : r.GridState === "Outstanding" ? "draft" : "");
    if (r.WorkRequestEntityId) { const a = $("req-link"); a.hidden = false; a.href = "/request.html?id=" + r.WorkRequestEntityId; }
    setStatus("status", "Revision " + (r.RevisionStatus || "") + " · lifecycle " + (r.LifecycleState || "—") + " · " + (r.FileKind || "") + " " + (r.ParseStatus || ""));
    dl($("g-general"), [["Record (OLD_NO)", r.DeviceName], ["Change request", r.WorkRequestTitle], ["Location", (r.StationName || "") + (r.StationNumber ? " (" + r.StationNumber + ")" : "")],
      ["Asset (panel)", r.PanelName], ["Equipment", r.PositionName], ["Device", (r.ModelCode || "") + (r.ModelName ? " — " + r.ModelName : "")], ["Functions", r.Functions]]);
    dl($("g-system"), [["Serial number", r.SerialNumber], ["Software version", r.FirmwareVersion], ["Manufacturer", r.ManufacturerName], ["Voltage", r.VoltageClassCode], ["Number of relays", NOT_MODELLED]]);
    dl($("g-mp"), [["CT main 1–4", NOT_MODELLED], ["PT main", NOT_MODELLED], ["Class · use · responsibility", NOT_MODELLED], ["Bulk power element · protection group · element · line type", NOT_MODELLED]]);
    dl($("g-aux"), [["CT aux 1–4", NOT_MODELLED], ["PT aux", NOT_MODELLED]]);
    dl($("g-doc"), [["Calculated (CDATE)", fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? " by " + r.CalculatedByDisplayName : "")], ["Verified (VDATE)", fmtWhen(r.VerifiedAt)],
      ["In service", r.InServiceFrom ? fmtWhen(r.InServiceFrom) + (r.InServiceTo ? " – " + fmtWhen(r.InServiceTo) : " – now") : "not in service"], ["Action type", r.WorkTypeKey],
      ["SETTINGS2 · DESC1–4 · REMARKS1–5", el("span", "muted", "land as the revision's change note and the document's notes at migration (W7)")], ["IDATE", el("span", "muted", "dropped (#72)")]]);
    await settings(r); await files(r);
  }

  async function settings(r) {
    try {
      const rows = await fetchAll("/api/v1/document/vParsedSettingNamed?ConfigurationFileRevisionRowId=" + encodeURIComponent(revision) + "&orderBy=SettingCode");
      table($("settings"), rows, [{ key: "SettingCode", label: "Setting" }, { key: "SettingName", label: "Name" }, { key: "GroupNumber", label: "Group" }, { key: "DisplayValue", label: "Value" }, { key: "UnitCode", label: "Unit" },
        { key: "MinValue", label: "Min" }, { key: "MaxValue", label: "Max" }, { key: "RangeCheck", label: "Range" }, { key: "RangeCheckNote", label: "Note" }]);
      $("settings-summary").textContent = rows.length ? rows.length + " parsed setting(s) from the " + r.FileKind + " file" : (r.FileKind === "NativeSettings" ? "The native (vendor) file is stored as is; no reader exists for it yet (#113)." : "No parsed settings.");
    } catch (e) { $("settings-summary").textContent = "Settings: " + e.message; }
  }

  async function files(r) {
    const rows = [];
    try {
      for (const f of (await getJson("/api/v1/document/vFile?RevisionRowId=" + encodeURIComponent(revision) + "&take=100")).rows)
        rows.push({ what: "this revision's file", kind: f.FileRole, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: f.CreatedAt });
      if (r.WorkRequestEntityId) {
        const recs = (await getJson("/api/v1/record/vRecord?WorkRequestEntityId=" + encodeURIComponent(r.WorkRequestEntityId) + "&take=200")).rows;
        for (const rec of recs) {
          let links = [];
          try { links = (await getJson("/api/v1/document/vRevisionLink?SubjectKind=Record&SubjectEntityId=" + encodeURIComponent(rec.EntityId) + "&take=50")).rows; } catch (e) { links = []; }
          if (!links.length) { rows.push({ what: rec.RecordKindCode, kind: rec.OverallResult || "", name: rec.Summary || "", when: rec.OccurredAt }); continue; }
          for (const l of links) {
            let fs = [];
            try { fs = (await getJson("/api/v1/document/vFile?RevisionRowId=" + encodeURIComponent(l.RevisionRowId) + "&take=50")).rows; } catch (e) { fs = []; }
            if (!fs.length) rows.push({ what: rec.RecordKindCode, kind: l.LinkKind, name: "(revision " + String(l.RevisionRowId).slice(0, 8) + ")", when: rec.OccurredAt });
            for (const f of fs) rows.push({ what: rec.RecordKindCode, kind: f.FileRole || l.LinkKind, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: rec.OccurredAt });
          }
        }
      }
      table($("files"), rows, [{ key: "what", label: "Record" }, { key: "kind", label: "Kind" }, { key: "name", label: "File / summary" }, { key: "mime", label: "Type" }, { key: "size", label: "Bytes" },
        { key: "sha", label: "SHA-256", render: (x) => (x.sha ? String(x.sha).slice(0, 12) + "…" : "") }, { key: "when", label: "When", render: (x) => fmtWhen(x.when) }]);
      $("files-summary").textContent = rows.length + " file(s) and record(s) — the platform holds the bytes; a download endpoint is a later item (W6 card).";
    } catch (e) { $("files-summary").textContent = "Files: " + e.message; }
  }

  window.PnC.registerWorker();
  me().then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
