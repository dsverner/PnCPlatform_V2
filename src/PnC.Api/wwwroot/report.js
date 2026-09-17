// W8 (decision #157; round 4 A). The location report, laid out as the legacy print preview: a header with the station,
// its number, the state and the date; one section per scheme (the group the settings book uses), one block per record
// with the device, model, functions, dates and revision, and the settings text as filed beneath it. The page is the
// preview; Print is window.print(). The texts are fetched one revision at a time with a progress line — a station of a
// few hundred records takes a little while, and says so.
(function () {
  "use strict";
  const { $, el, fetchAll, fmtDate, fmtWhen, qs, me, setStatus, getJson, settingsText, legacyFree, legacyDetail } = window.PnC;
  const q = qs();
  const shown = (name) => legacyFree(name);
  const gridState = q.GridState || "Active";

  // #179: the report is per location, and after #178 a location is a BUILDING. The address may still name a station,
  // because links and bookmarks made before this change carry one and both are ordinary columns of the same view.
  const locCol = q.BuildingNodeEntityId ? "BuildingNodeEntityId" : "StationNodeEntityId";
  const locId = q.BuildingNodeEntityId || q.StationNodeEntityId;

  async function load() {
    if (!locId) { setStatus("status", "No location in the address (report.html?BuildingNodeEntityId=…&GridState=Active).", true); return; }
    setStatus("status", "Loading " + gridState + " records…");
    let rows = [];
    try { rows = await fetchAll("/api/v1/document/vSettingsRecord?GridState=" + encodeURIComponent(gridState) + "&" + locCol + "=" + encodeURIComponent(locId) + "&orderBy=DeviceName"); }
    catch (e) { setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true); return; }
    let station = rows.length ? { name: locCol === "BuildingNodeEntityId" ? rows[0].BuildingName : rows[0].StationName, no: "" } : null;
    if (!station) { try { const n = (await getJson("/api/v1/location/vNode?EntityId=" + encodeURIComponent(locId))).rows[0]; station = { name: n ? n.Name : "?", no: "" }; } catch (e) { station = { name: "?", no: "" }; } }
    $("title").textContent = "Location report — " + station.name;
    document.title = station.name + " · " + gridState + " settings · P&C Platform";
    const head = $("head"); head.textContent = "";
    head.appendChild(el("div", "report-title", station.name + (station.no ? "  ·  station " + station.no : "")));
    head.appendChild(el("div", "report-sub", gridState + " settings  ·  " + rows.length + " record(s)  ·  printed " + new Date().toLocaleString()));
    const groups = new Map();
    for (const r of rows) { const k = r.SchemeName || "(no scheme yet)"; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
    const body = $("body"); body.textContent = "";
    const pres = [];
    for (const name of [...groups.keys()].sort((a, b) => a.localeCompare(b))) {
      const sec = el("section", "report-group");
      sec.appendChild(el("h3", "report-group-title", name + "  ·  " + groups.get(name).length + " record(s)"));
      for (const r of groups.get(name)) {
        const blk = el("div", "report-record");
        const facts = el("dl", "facts three");
        for (const [k, v] of [["Device", shown(r.DeviceName)], ["Model", (r.ModelCode || "") + (r.ModelName ? " — " + r.ModelName : "")], ["Functions", r.Functions || r.PositionName], ["Equipment", r.PanelName], ["Position", r.PositionName],
          ["Software version", r.FirmwareVersion], ["Serial number", r.SerialNumber], ["Calculated", fmtDate(r.CalculatedAt)], ["Verified", fmtDate(r.VerifiedAt)], ["Revision", r.RevisionLabel], ["Change request", legacyFree(r.WorkRequestTitle)]])
          { facts.appendChild(el("dt", null, k)); facts.appendChild(el("dd", null, v == null || v === "" ? "—" : String(v))); }
        const ctpt = el("dd", "muted", "…"); facts.appendChild(el("dt", null, "CT / PT · class")); facts.appendChild(ctpt);
        blk.appendChild(facts);
        const pre = $("with-text").checked ? el("pre", "settings-text small", "…") : null; if (pre) blk.appendChild(pre);
        pres.push([r, pre, ctpt]);
        sec.appendChild(blk);
      }
      body.appendChild(sec);
    }
    let n = 0;
    for (const [r, pre, ctpt] of pres) {
      setStatus("status", "Reading record " + (++n) + " of " + pres.length + "…");
      if (pre) { try { const t = await settingsText(r.RevisionRowId); pre.textContent = t ? t.text : "(no settings file filed)"; } catch (e) { pre.textContent = "(the settings text could not be read: " + e.message + ")"; } }
      // the CT/PT ratios and the classification live on the revision's migrated record (W7, #140), read under the platform's labels
      try {
        const recs = r.WorkRequestEntityId ? (await getJson("/api/v1/record/vRecord?WorkRequestEntityId=" + encodeURIComponent(r.WorkRequestEntityId) + "&RecordKindCode=ConfigurationFileRevision&take=200")).rows : [];
        const rec = recs.find((x) => String(x.SecondSubjectEntityId || "").toLowerCase() === String(r.RevisionRowId).toLowerCase()) || (recs.length === 1 ? recs[0] : null);
        const d = rec ? legacyDetail(rec.Summary) : { mp: [], it: [] };
        const parts = d.it.concat(d.mp).map(([k, v]) => k + " " + v);
        ctpt.textContent = parts.length ? parts.join(" · ") : "not recorded"; ctpt.className = parts.length ? "" : "muted";
      } catch (e) { ctpt.textContent = "not read: " + e.message; }
    }
    setStatus("status", rows.length + " record(s) in " + groups.size + " scheme(s)" + " · " + pres.length + " record(s) read" + " · ready to print");
  }
  $("btn-print").addEventListener("click", () => window.print());
  $("with-text").addEventListener("change", load);
  window.PnC.registerWorker();
  me().then(load).catch(() => setStatus("status", "Sign in on the home page first.", true));
})();
