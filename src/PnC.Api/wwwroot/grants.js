// W8 (decision #136; IDENTITY.md §3–§5). The grants screen over security.vUser / personnel.vPerson / security.vGrant, writing
// through security.Grant_Add and security.Grant_Revise. A grant names who granted it: the session's own actor from /me
// (actorId, resolved by the database), never an id the page invents.
(function () {
  "use strict";
  const { $, el, table, fetchAll, fmtWhen, me, setStatus, getJson, postJson } = window.PnC;
  const state = { people: [], person: null, grants: [], nodes: new Map(), roles: [], canModify: false, actorId: null };

  async function load() {
    const m = await me();
    state.canModify = m.can("Grant.Modify"); state.actorId = m.actorId;
    if (!m.can("Grant.Read")) { setStatus("status", "Grant.Read is needed to see grants (the Administrator's).", true); return; }
    const [users, persons, roles, grants] = await Promise.all([
      fetchAll("/api/v1/security/vUser"), fetchAll("/api/v1/personnel/vPerson"), fetchAll("/api/v1/security/vRole"), fetchAll("/api/v1/security/vGrant"),
    ]);
    const personById = new Map(persons.map((p) => [p.EntityId.toLowerCase(), p]));
    state.people = users.map((u) => ({ user: u, person: personById.get(String(u.PersonEntityId).toLowerCase()) })).filter((x) => x.person)
      .sort((a, b) => String(a.person.DisplayName || "").localeCompare(String(b.person.DisplayName || "")));
    state.roles = roles.filter((r) => r.IsActive !== false && r.IsActive !== 0);
    state.grants = grants;
    await nodesForScopes();
    renderPeople(); $("people-summary").textContent = state.people.length + " people with an account";
    if (state.canModify) $("btn-add").hidden = true;   // shown once a person is picked
    setStatus("status", "Pick a person on the left.");
  }
  // the scope nodes: every division and station (the two kinds a grant is usually scoped to), named for the table and the picker
  async function nodesForScopes() {
    const divs = await fetchAll("/api/v1/location/vNode?NodeTypeCode=Division");
    const stations = await fetchAll("/api/v1/location/vNode?NodeTypeCode=Station");
    for (const n of divs.concat(stations)) state.nodes.set(n.EntityId.toLowerCase(), n);
    const sel = $("add-node"); sel.textContent = ""; sel.appendChild(el("option", null, "(pick a division or a station)")).value = "";
    for (const n of divs.sort((a, b) => String(a.Name).localeCompare(String(b.Name)))) { const o = el("option", null, "Division · " + n.Name); o.value = n.EntityId; sel.appendChild(o); }
    for (const n of stations.sort((a, b) => String(a.Name).localeCompare(String(b.Name)))) { const o = el("option", null, "Station · " + n.Name); o.value = n.EntityId; sel.appendChild(o); }
  }
  function renderPeople() {
    const f = ($("find").value || "").toLowerCase();
    const ul = $("people"); ul.textContent = "";
    for (const p of state.people) {
      const label = (p.person.DisplayName || "") + " — " + p.user.UserPrincipalName;
      if (f && !label.toLowerCase().includes(f)) continue;
      const li = el("li"); const b = el("button", "name", label); b.type = "button";
      const live = state.grants.filter((g) => String(g.GranteeEntityId).toLowerCase() === p.user.EntityId.toLowerCase() && !g.RevokedByActorId);
      li.appendChild(b); li.appendChild(el("span", "type small muted", live.length ? live.map((g) => g.RoleCode).join(", ") : "no grant"));
      if (p.user.IsEnabled === false || p.user.IsEnabled === 0) li.appendChild(el("span", "type small muted", " disabled"));
      b.addEventListener("click", () => pick(p));
      ul.appendChild(li);
    }
  }
  function scopeText(g) {
    if (g.ScopeKind === "Global") return "Global";
    if (g.ScopeKind === "NodeSubtree") { const n = state.nodes.get(String(g.ScopeNodeEntityId).toLowerCase()); return "NodeSubtree · " + (n ? n.NodeTypeCode + " " + n.Name : g.ScopeNodeEntityId); }
    if (g.ScopeKind === "WorkRequest") return "WorkRequest · " + g.ScopeWorkRequestEntityId;
    if (g.ScopeKind === "OwnershipRelation") return "OwnershipRelation · " + g.ScopeOwnershipRole;
    return g.ScopeKind;
  }
  function pick(p) {
    state.person = p;
    $("person-title").textContent = (p.person.DisplayName || "") + " (" + p.user.UserPrincipalName + ")";
    $("btn-add").hidden = !state.canModify; $("add").hidden = true; $("revoke").hidden = true;
    renderGrants();
  }
  function renderGrants() {
    const p = state.person; if (!p) return;
    const rows = state.grants.filter((g) => String(g.GranteeEntityId).toLowerCase() === p.user.EntityId.toLowerCase())
      .sort((a, b) => (a.RevokedByActorId ? 1 : 0) - (b.RevokedByActorId ? 1 : 0) || String(a.RoleCode).localeCompare(String(b.RoleCode)));
    const cols = [
      { key: "RoleCode", label: "Role" },
      { key: "ScopeKind", label: "Scope", render: scopeText },
      { key: "ScopeAssetClassCode", label: "Asset class" },
      { key: "ScopeDeviceCategory", label: "Device category" },
      { key: "ValidFrom", label: "Since", render: (g) => fmtWhen(g.ValidFrom) },
      { key: "RevokedByActorId", label: "State", render: (g) => (g.RevokedByActorId ? "revoked — " + (g.RevocationReason || "") : "in force") },
      { key: "_", label: "", render: (g) => { if (!state.canModify || g.RevokedByActorId) return ""; const b = el("button", null, "Revoke"); b.type = "button"; b.addEventListener("click", () => askRevoke(g)); return b; } },
    ];
    table($("grants"), rows, cols);
    setStatus("status", rows.filter((g) => !g.RevokedByActorId).length + " grant(s) in force · " + rows.filter((g) => g.RevokedByActorId).length + " revoked");
  }
  // ---- add
  function openAdd() {
    const sel = $("add-role"); sel.textContent = "";
    for (const r of state.roles) { const o = el("option", null, r.RoleCode + " — " + (r.Name || "")); o.value = r.RoleCode; sel.appendChild(o); }
    $("add-scope").value = "Global"; $("add-node").value = ""; $("add-class").value = ""; $("add-category").value = "";
    $("add-node-row").hidden = true; $("add").hidden = false; $("revoke").hidden = true; setStatus("add-status", "");
  }
  async function saveAdd() {
    const p = state.person; if (!p) return;
    const scope = $("add-scope").value; const node = $("add-node").value;
    if (scope === "NodeSubtree" && !node) { setStatus("add-status", "A NodeSubtree scope needs a node.", true); return; }
    if (!state.actorId) { setStatus("add-status", "The session's actor is unknown; sign in again.", true); return; }
    setStatus("add-status", "Saving…");
    try {
      const body = { GranteeKind: "User", GranteeEntityId: p.user.EntityId, RoleCode: $("add-role").value, ScopeKind: scope,
        ScopeNodeEntityId: scope === "NodeSubtree" ? node : null, ScopeAssetClassCode: $("add-class").value || null, ScopeDeviceCategory: $("add-category").value || null,
        GrantedByActorId: state.actorId };
      await postJson("/api/v1/security/Grant_Add", body);
      state.grants = await fetchAll("/api/v1/security/vGrant");
      $("add").hidden = true; renderPeople(); renderGrants(); setStatus("status", "Grant added.");
    } catch (e) { setStatus("add-status", "Not saved: " + (e.status || "") + " " + e.message, true); }
  }
  // ---- revoke: Grant_Revise with the row's own values, RevokedByActorId = the session's actor, and the reason
  let revoking = null;
  function askRevoke(g) {
    revoking = g; $("revoke-what").textContent = g.RoleCode + " · " + scopeText(g); $("revoke-reason").value = "";
    $("revoke").hidden = false; $("add").hidden = true; setStatus("revoke-status", "");
  }
  async function doRevoke() {
    const g = revoking; if (!g) return;
    const reason = $("revoke-reason").value.trim();
    if (!reason) { setStatus("revoke-status", "A reason is required.", true); return; }
    setStatus("revoke-status", "Revoking…");
    try {
      await postJson("/api/v1/security/Grant_Revise", {
        EntityId: g.EntityId, GranteeKind: g.GranteeKind, GranteeEntityId: g.GranteeEntityId, RoleCode: g.RoleCode, ScopeKind: g.ScopeKind,
        ScopeNodeEntityId: g.ScopeNodeEntityId, ScopeAssetClassCode: g.ScopeAssetClassCode, ScopeDeviceCategory: g.ScopeDeviceCategory,
        ScopeWorkRequestEntityId: g.ScopeWorkRequestEntityId, ScopeEntityEntityId: g.ScopeEntityEntityId, ScopeOwnershipRole: g.ScopeOwnershipRole,
        GrantedByActorId: g.GrantedByActorId, RevokedByActorId: state.actorId, RevocationReason: reason,
      });
      state.grants = await fetchAll("/api/v1/security/vGrant");
      $("revoke").hidden = true; renderPeople(); renderGrants(); setStatus("status", "Grant revoked.");
    } catch (e) { setStatus("revoke-status", "Not revoked: " + (e.status || "") + " " + e.message, true); }
  }

  $("find").addEventListener("input", renderPeople);
  $("btn-add").addEventListener("click", openAdd);
  $("btn-cancel").addEventListener("click", () => { $("add").hidden = true; });
  $("btn-save").addEventListener("click", saveAdd);
  $("add-scope").addEventListener("change", () => { $("add-node-row").hidden = $("add-scope").value !== "NodeSubtree"; });
  $("btn-revoke").addEventListener("click", doRevoke);
  $("btn-revoke-cancel").addEventListener("click", () => { $("revoke").hidden = true; });
  window.PnC.registerWorker();
  load().catch((e) => setStatus("status", "Could not load: " + (e.status || "") + " " + e.message, true));
})();
