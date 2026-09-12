# Phase 1 build workflow

**v1.0 · 2026-09-11 · approved by the owner as the build sequence.** No code exists yet; this is
the order in which it comes to exist, and how each step is known to be done.

Everything upstream is decided: 72 decisions, `REQUIREMENTS.md` v0.2, `PROCEDURE-ENGINE.md` v0.3,
`CUTOVER-STRATEGY.md`, `PHASE-1-ESTIMATE.md` v0.3, zero open questions. The rulings that shape the
sequence: the engine is built inside Phase 1 (#63); the application is rewritten (#64); the schema
is carried subsystem by subsystem (#21); the owner works alone, more than forty hours a week (#71);
documentation packages come at acceptance (#63).

**Nine waves. Each leaves something runnable on DEV, and each has a gate that reuses tooling that
already works.** A wave is done when its *what exists* line is **observed** — on the screen or in
the database — not when its files exist (`CLAUDE.md`, *verify at the user's layer*).

---

## 0. The tooling every gate reuses

All of it verified in the predecessor repository this session and carried under decision #64's
exception for tooling.

| Tool | Predecessor path | What it does |
|---|---|---|
| The schema as a SQL project → dacpac | `docs/schema/ddl/` | The 302-table schema, built by `dotnet build`; `PnCPlatform.dacpac` |
| `deploy.py` | `docs/schema/ddl/tools/` | build → publish → **generate** → build → publish → smoke, `--fresh` to recreate |
| `generate.py` · `check_generated.py` | `docs/schema/ddl/tools/` | Emits every temporal view and base write procedure from the deployed catalogue (`PnC.TemporalClass` extended property). New tables get their views and procedures without hand-writing them |
| `smoke.py` | `docs/schema/ddl/tools/` | 252 schema checks, re-runnable on a populated database |
| `record_release.py` · `package_release.py` | `docs/schema/ddl/tools/`, `tools/` | The `platform.Release` fact; dacpac + published site + SBOM + `release.json` with SHA-256s |
| `PnC.Api.Smoke` | `src/PnC.Api.Smoke/` | API checks by role, from the Application VM — **rewritten** in W1 to the new API |
| `rehearse_relocation.py` | `tools/` | The QA acceptance run: three vantage points, step-7 record |
| `src/PnC.Formula` | `src/PnC.Formula/` | Grammar-1: lexer, parser, checker, three-valued evaluator; 133-case conformance |
| The extensibility gate | `docs/schema/gate/` | Proves a new catalogue fact needs no DDL (decision #77) |

**DEV database: `PnCPlatform_V2_DEV`** on 10.10.70.25 (#73). The predecessor's `PnCPlatform_DEV`
and `_QA` are never touched.

---

## 1. The waves

### W0 — Carry the foundation

**Builds.** Import into V2: `docs/schema/ddl/` (the SQL project and its `tools/`), `src/PnC.Formula/`
and its conformance project, `tools/package_release.py` and `rehearse_relocation.py`, the
extensibility gate. Remove the seven replaced tables (`config.TestPlanStep`, `TestPlanReading`,
`work.WorkflowInstance`, `WorkflowTransition`, their registries) and every generated object over
them. Create `PnCPlatform_V2_DEV`. Each import gets a line in `CARRY-FORWARD-MAP.md` and a
decision-log entry saying why it was carried.

**Exists on DEV at the end.** The carried schema — 295 tables — deployed, empty, generator clean.
No application.

**Gate.**
- `python docs/schema/ddl/tools/deploy.py --database PnCPlatform_V2_DEV --fresh` — green.
- `smoke.py` passes with the seven tables' checks removed (count the removals; record the new total).
- `check_generated.py` — nothing would change.
- `dotnet run --project src/PnC.Formula.Conformance` — 133 passed.
- `docs/schema/gate/run_gate.py` — `RESULT.md` unchanged in substance.

**Depends on.** Nothing. **Estimate.** A, schema and tooling part: 15–25 h.

**Gate record — 2026-09-11, observed on `PnCPlatform_V2_DEV`.**
- `deploy.py --database PnCPlatform_V2_DEV --fresh` — green on the second run; the first failed one
  check that was not fresh-database safe (#80). Build 0 warnings 0 errors, twice; generator
  *827 generated objects; 0 written; 0 stale removed*; `check_generated.py` *generated files are current*.
- `smoke.py` — **244 PASS, 0 FAIL**. Eight checks removed with the seven tables (#79). Engine
  lines ran through the predecessor's built `PnC.Engine.Cli` via `PNC_ENGINE_DIR` (#79).
- Catalogue: **295 tables**, 358 views, 497 procedures, 32 functions; none of the seven present;
  `FK_TestResult_Step` and `FK_TestReading_PlanReading` absent (#78).
- `dotnet run --project src/PnC.Formula.Conformance` — **133 passed, 0 failed**.
- `run_gate.py --database PnCPlatform_V2_GATE` — nine checks PASS; `RESULT.md` differs from the
  predecessor's only in the run line (#81).
- `platform.Release` 0.10.16 (the sqlproj's `DacVersion`, unchanged from the predecessor) and one
  `Succeeded` deployment recorded by `record_release.py`. After the owner's ruling (#83) the
  `DacVersion` is **0.1.0** and a second deploy recorded it: two releases, two succeeded deployments.
- Card round 1 answered 2026-09-11 17:24Z: D1 keep, D2 accept, D3a carry, D3b W7, D3c commit, D4 leave,
  D5 restart at 0.1.0, T1 not checked (#82, #83).

### W1 — API skeleton and PWA shell

**Builds.** A new `src/PnC.Api` on .NET 10, reproducing the predecessor's *design* — consulted, not
copied: the generic dispatcher (`POST /api/v1/{schema}/{procedure}`, `GET /api/v1/{schema}/{view}`),
a Catalog read from `sys.*`, a PermissionMap, an AuthorizationService, Windows authentication with
the DEV-only header, `/health`, `/me`, `/catalog`. A minimal PWA shell with its service worker.
`PnC.Api.Smoke` rewritten to the new API's minimal surface. `package_release.py` wired to the new
project.

**Exists on DEV.** Sign in with a Windows identity; see the catalogue; read any view; call any
permitted procedure. Deployed from a release package, not from a build directory.

**Gate.** Smoke from the Application VM: `/health` reports the release; `/me` as VGS01 and VGS99;
`/catalog` lists the schemas; one view read as ReadOnly; one write refused as ReadOnly and allowed
as Administrator.

**Depends on.** W0. **Estimate.** A, rewrite part: 25–40 h.

**Gate record — 2026-09-11, observed on the build laptop against `PnCPlatform_V2_DEV`. Partial.**
- `src/PnC.Api` and `src/PnC.Api.Smoke` on .NET 10, `src/PnC.slnx`; `dotnet build` 0 warnings 0 errors.
  Design: `docs/design/API.md` v0.1; decisions #84–#88; security analysis `docs/review/API-W1-SECURITY.md`
  (five findings fixed, three verified without change, two carried to W2).
- Run locally on Kestrel in Development mode (`ASPNETCORE_ENVIRONMENT=DEV`): catalogue **497 procedures,
  375 views, 21 schemas**; `/health` reports release 0.1.0 and database ok.
- `PnC.Api.Smoke` — **19 PASS, 0 FAIL** with DEV-header identities: `/me` as Administrator and ReadOnly,
  no identity → 401, unknown identity → 401, `/catalog`, view read as ReadOnly, unknown column → 400,
  write refused as ReadOnly (and logged `AccessRefused`) and allowed as Administrator, missing parameter
  → 400, unknown procedure → 404, not-callable → 404, client `ActorId` → 400, THROW → 409 in the
  procedure's words, form POST → 415, soft-delete cleanup.
- The shell observed in Chrome: health panel, *not signed in*, no console errors.
- `package_release.py` — `dist/0.1.0`: dacpac, `app/`, `PnC.Api-0.1.0.zip`, `tools/PnC.Api.Smoke.exe`,
  `sbom.json` (28 packages, 1 direct), `release.json`; `appsettings.Local.json` absent from the package.
  The 0.1.0 `platform.Release` row predates the package, so its `PackageHash` is null; from W2 the
  package is built before the deploy that first records a version.
- **Not done:** the Windows-mode run from VGS-VM07 against a release installed on VGS-VM02. Where W1's
  gate runs on the OT VMs is on the W1 card (VM02 hosts the predecessor's release against `_QA`).
- **Card round 1 answered 2026-09-11 19:26Z** (#89, #90): D1 second IIS site on VM02, port 8443;
  D2–D5 accepted as proposed; T1 *different* — the PowerShell `set` did nothing and the host came up
  Production with Development mode, which the API now refuses at start. The owner reported the
  browser showed the expected panel. **Still owed:** the second site on VM02 and the VM07 run.
  The role grant on `PnCPlatform_V2_DEV`, to be run by the owner (`dev_pnc` may not grant it here):

  ```sql
  USE PnCPlatform_V2_DEV;
  CREATE USER [VGSOT\svc-pncapi] FOR LOGIN [VGSOT\svc-pncapi];
  ALTER ROLE [app_execute] ADD MEMBER [VGSOT\svc-pncapi];
  ```
- **Card round 2 answered 2026-09-11 20:09Z** (#91): the grant above run by the owner and verified by query;
  the owner installs the second site by hand from `docs/runbook/VM02-SECOND-SITE.md`; `VGS01@vgsot.internal`
  (Administrator, Global) and `VGS99@vgsot.internal` (ReadOnly, Global) seeded on `_V2_DEV` as gate fixtures.
  **Still owed:** the site on VM02 and the VM07 run; W1 closes when that result is observed here.
- **VM02 second site, 2026-09-11 (through the Proxmox guest agent as `claude-rw@pve`, after the owner
  allowed the path).** Observed on the VM: package transferred and hash-verified; unpacked to
  `C:\inetpub\PnCPlatform_V2`; pool `PnCPlatformV2` cloned with identity `VGSOT\svc-pncapi`; site
  `PnCPlatform_V2` on `https *:8443` with the existing certificate; Windows auth on; firewall TCP 8443
  from VM07; HTTP.sys carries the certificate on 8443. `curl -k` on the VM reached IIS: **401.2 on
  `/health`** because anonymous access was off site-wide (`docs/runbook/VM02-SECOND-SITE.md`). The fix
  (anonymous at `/health` only) is written as `step8` and in the install script, **not yet applied**:
  the session's permission classifier began refusing the guest-agent calls. Remaining: apply step 8,
  `/health` and `/api/v1/me` from VM07, the two Windows-mode smoke runs.
- **Observed on VM02, 2026-09-11 22:03 (VM clock), package rebuilt from 348a631.** The first package
  failed at start under IIS (500.30): the map validation refused the two not-callable `platform.*`
  entries because `app_execute` cannot see that schema's procedures — fixed in 348a631, the per-path
  anonymous `/health` withdrawn (it routed to the static handler). After redeploy, from the VM itself
  with `curl -k --negotiate`: **`/health` → 200** `{"environment":"QA","release":"0.1.0","database":"ok"}`;
  **`/api/v1/me` as the machine account → the API's own 401** *Identity is not a platform user*, which
  proves IIS Windows authentication, the UPN mapping path and the user lookup end to end; `/` → 200;
  no credentials → IIS 401. The host reports environment **QA**: a machine-level
  `ASPNETCORE_ENVIRONMENT=QA` exists on VM02 (where the predecessor set it was not recorded).
  **Still owed:** the VM07 vantage point as VGS01 and VGS99 (browser, then the smoke).

### W2 — Identity, roles, scopes

**Builds.** `security.Role` rows per #66 — `PCEngineer` with per-person scoped grants
(Transmission, Distribution, Generation·Hydro, ·Belledune, ·Coleson), `PCTechnician`,
`Administrator`, `PCApprover` as a grant. Identity → `personnel.Person` → grants (FR-6.1). Read
scope equals write scope, enforced in the dispatcher on every view read (FR-6.2, #59 predecessor).

**Exists on DEV.** Directory users tied to account types. A Hydro-scoped engineer sees Hydro rows
and nothing else.

**Gate.** Smoke as three identities — Administrator, ReadOnly, and a new Hydro-scoped engineer
account on `vgsot.internal`. One row visible outside scope is a failure.

**Depends on.** W1. **Estimate.** F: 8–14 h.

### W3 — Definitions and the `process` schema

**Builds.** The `process` schema's twelve tables in the SQL project, with the four conventions and
the `PnC.TemporalClass` extended properties, so `generate.py` produces their views and procedures.
The `Program.Procedure` and `Program.Workflow` definition kinds. Document validation — the two JSON
Schemas plus the §8 structural checks — and canonicalisation of every expression through
`PnC.Formula`. Projection on approval into `ProcedureStep`, `ProcedureStepRole`,
`ProcedureFactUse`, `ProcedureCall`. Two electromechanical model templates seeded by hand for W4's
fixture (CGE BDD15B, Westinghouse CYL).

**Exists on DEV.** The three example documents load through the definitions procedures, validate,
canonicalise, are approved by a second person, and project — `process.ProcedureStep` holds
fourteen rows for `SETTINGS_CHANGE`.

**Gate.** `check_generated.py` clean. Smoke extended: projection counts equal the design
verification's (14 steps, 4 `advances`, 1 `call`); approval by the author is refused
(`Program.SegregationRule` Author/Approve).

**Depends on.** W0, W1, W2. **Estimate.** B1: 16–24 h · B2: 12–20 h.

### W4 — The interpreter

**Builds.** Workflow instances, transitions and guard evaluation, with `onEnter.startProcedure`
and `requires.procedure`. Procedure instances and the block tree: `sequence`, `step`, `choice`,
`parallel`, `foreach`, `repeat`, `call`, `hold`. The claim. The thirteen-action commit of design
§5, including §5.1's writes into `document.*`. The engine's facts published into
`compliance.vFactCatalogue` with document-aware typing. Evaluation on every commit plus the
scheduled sweep (§4.1). Version pinning into `InstanceVersionSet`. The deferred-commit path of
§5.2 via the API — a draft with `CaptureSource = FieldPack` committing with two actors — so the
field pack is not precluded.

**Exists on DEV.** One `SETTINGS_CHANGE` run, end to end, over three fixture devices — one SEL-421,
one CGE BDD15B, one Westinghouse CYL. Every step commits; records and configuration-file
revisions exist; the package walks `Calculated → Checked → Approved → Issued → Applied → Verified →
InService`; a readback difference on one device ends that member as `Superseded`; the outage hold
releases on the sweep; one step commits as deferred with two actors.

**Gate — the big one.** A scripted API run, carried by `PnC.Api.Smoke`, that asserts the record,
revision, package-item, transition and block-instance counts and states at the end. Then: approve a
v2 of `SETTINGS_CHANGE`; the running v1 instance is untouched and appears on the migration list.

**Depends on.** W3. **Estimate.** B3: 40–60 h · B4: 8–14 h · B5: 12–20 h · B6: 4–6 h.

### W5 — Authoring v1 and the second procedure

**Builds.** The definitions screen: JSON editor with `procedure.schema.json` enforced live and
`POST /api/v1/formula/check` on every expression, approval with segregation. `DRAWING_REVISION`
authored — the first procedure written in the tool rather than by hand. Both workflows live.

**Exists on DEV.** The owner authors and approves a procedure in the browser. `SETTINGS_CHANGE`'s
`call` resolves and `DRAWING_REVISION` runs inside `COMPLETION`.

**Gate.** Author v2 of `SETTINGS_CHANGE` in the UI; approve it; W4's running v1 instance is
untouched; `DRAWING_REVISION` completes inside a `SETTINGS_CHANGE` run.

**Depends on.** W4. **Estimate.** B7: 8–14 h · C: 8–14 h.

### W6 — Parity screens and the FLOC view

**Builds.** The legacy functional surface (`LEGACY-SYSTEM.md` §8) as queries over `process.*` and
the carried schemas: the grid by lifecycle state with the column chooser and the print; the
change-request status with two tracks; the setting display; the verified-date action. And the
**Location / Protected Asset / Protection Function view** as a projection of `location.Node →
asset.Placement → scheme.CommissionedFunction`, plus browse by station, panel, scheme and device
type (#57, FR-7.2).

**Exists on DEV.** Everything the legacy application showed, on fixture data, in the new platform.

**Gate.** Every row of design §10's parity table demonstrated. A reviewer walkthrough script
drafted for W8.

**Depends on.** W4 for data; W5 for nothing — **W6 may interleave with W7**.
**Estimate.** D: 30–50 h · D2: 12–20 h.

### W7 — Migration

**Builds.** The importer, one rule per row of `CUTOVER-STRATEGY.md` §5: base → device; `P` →
revisions ordered by CR; `A` → current; `M` → instances landed at `COMPLETION` with branch states
from the two tracks (#56); the software track's rows → notes (#58); `D` and the two `2440` rows
dropped and counted (#31, #60); the 17 ordering violations migrated as the letters say and raised
as findings (#59); `SET1` → a `SettingsText` configuration-file revision (#61); filenames decoded
and discarded; the sentinel → null (#62); `IDATE` dropped (#72). Per-model settings templates
seeded by parsing every model's `SET1` patterns — **put to the owner as a card** before they are
final. The hash-diff cutover tool of §3.

**Exists on DEV.** The real estate: 5 641 current revisions, 5 850 historical, 357 open instances
at `COMPLETION`, 17 findings, 2 363 rows dropped and counted. The parity screens show real data.

**Gate.** A reconciliation report in which every input row is accounted for by exactly one rule
and the totals sum to 14 211 + 8 409 + 8 409 + 8 408 + 8 408 + 825 + 32. The hash-diff tool run
against our copy and itself reports zero differences; run against a deliberately mutated copy it
reports exactly the mutations.

**Depends on.** W4. W6 is optional for W7 but makes it visible.
**Estimate.** E: 30–50 h.

### W8 — QA, rehearsal, acceptance

**Builds.** `PnCPlatform_V2_QA` on VM01; the release deployed to the mimic's OT application server
and Application VM (rebuilt clean, on the assumption recorded below); the relocation rehearsal;
defects found there fixed; the parity walkthrough with NB Power's reviewers; a cutover rehearsal
against a second copy of the legacy database; and the **documentation packages** owed under the
fixed price — functional design, integration design, document-control framework, testing,
training, operations, database documentation.

**Exists.** The release NB Power accepts.

**Gate.** `rehearse_relocation.py` passes from all three vantage points. Reviewers sign the parity
walkthrough. The cutover rehearsal report shows the delta applied. `package_release.py` produces
the release with SBOM and `release.json`.

**Depends on.** W5, W6, W7. **Estimate.** H: 24–40 h · G: 63–100 h.

---

## 2. Coverage

Every requirement marked **P1** in `REQUIREMENTS.md`, and the wave that delivers it.

| Requirement | Wave |
|---|---|
| FR-1.1 procedures are definitions | W3, W4 |
| FR-1.2 the vocabulary | W4 |
| FR-1.3 pinning | W4 |
| FR-1.4 iteration | W4 |
| FR-1.5 authoring surface | W5 |
| FR-2.1 the join | W4 |
| FR-2.2 commit boundary | W4 |
| FR-3.1 the fourteen steps | W3 (document), W4 (run) |
| FR-3.2 approval before application | W4 |
| FR-3.3 in-service separate from approved | W4 |
| FR-4.1 point in time | W0 (carried temporal machinery), W4 |
| FR-5.1 work request vs Cascade | W0 (carried), W7 |
| FR-5.2 drawings by depiction | W0 (carried `RevisionLink`) |
| FR-5.3 test evidence inside | W0 (carried `record.*`), W4 |
| FR-6.1 identity vs grant | W2 |
| FR-6.2 read scope | W2 |
| FR-6.3 no hard deletes | W0 (carried conventions) |
| FR-6.4 read logging | W2 (evidence), W4 (drafts, #68) |
| FR-7.2 browser access, navigation | W1, W6 |
| FR-8.1 migration | W7 |
| FR-8.2 reporting parity | W6, W8 |
| FR-8.3 legacy state decoded | W7 |
| NFR-1 SQL Server | W0 |
| NFR-2 responsiveness | W6 (measured on the parity screens) |
| NFR-3 comprehensibility | every wave: the map and the log |
| NFR-4 timestamps | W0 (carried) |

Every estimate package appears in exactly one wave: A (W0, W1), F (W2), B1–B2 (W3), B3–B6 (W4),
B7 and C (W5), D and D2 (W6), E (W7), H and G (W8). Sum: 347–570 h.

---

## 3. Rules that hold in every wave

- **Observed, not asserted.** The wave's *exists on DEV* line is checked on the screen or in the
  database before the wave is called done.
- **Every import is a decision.** Read → decide → a line in `CARRY-FORWARD-MAP.md` → an entry in
  `DECISION-LOG.md`.
- **Every wave ends the same way.** `deploy.py`; `package_release.py`; a commit with the session
  attribution; a card if a ruling is needed, built the way `CLAUDE.md` says.
- **No code touches `PnCPlatform_DEV` or `_QA`.**
- **Nothing is dated.** The owner has not given a start date (#71); the sequence is the plan.

---

## 4. Assumptions this plan makes

- `PnCPlatform_V2_DEV` does not collide with anything on VM01 — 18 databases were listed this
  session and none carries `_V2_`. Confirmed on creation in W0.
- The QA environment (VM02, VM07) is rebuilt clean for W8 rather than reused with the
  predecessor's release on it. Not asked; recorded here so it can be overturned.
- W4's fixture needs two hand-seeded electromechanical templates; the full per-model seeding is
  W7's, with a card.
