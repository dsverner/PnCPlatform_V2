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
- **Observed from VGS-VM07 as VGS01, 2026-09-11 (owner's screenshot).** Edge first refused the correct
  password: the site lacked `useAppPoolCredentials`, which the predecessor's site has (Kerberos tickets
  for the service-account SPN); set, and the page loaded. Shown: *Environment QA · Release 0.1.0 ·
  Database ok · Catalogue loaded 2026-09-11 10:17:58 p.m. · Person VGS01 · Account VGS01@vgsot.internal
  · Grants Administrator (Global) · 21 schemas · 495 procedures · 375 views* with permission codes.
  495, not the laptop's 497: `app_execute` cannot see the two `platform` procedures — consistent with
  348a631. Gate items met from VM07: `/health` reports the release; `/me` as VGS01; `/catalog` lists the
  schemas. **Still owed:** `/me` as VGS99, one view read as ReadOnly, one write refused as ReadOnly and
  allowed as Administrator — the smoke runs.
- **`/me` as VGS99, 2026-09-12 (owner's report, from an InPrivate window in the VGS01 desktop on VM07,
  credentials given at the site's Windows Security prompt).** The page loaded as VGS99. Domain read
  beforehand: the account was active, unlocked, password set 2026-09-07, never logged on; Guacamole's
  own throttle ("too many login errors") was the earlier obstacle, not the account. **Still owed:** one
  view read as ReadOnly, one write refused as ReadOnly and allowed as Administrator — the smoke.
- **View read as VGS99, 2026-09-12 (owner's report, same window):** `GET /api/v1/asset/vAsset?take=5`
  answered `{"view":"asset.vAsset","skip":0,"take":5,"rows":[]}` — 200, the empty V2 estate. **Still
  owed:** one write refused as ReadOnly and allowed as Administrator.
- **Write refused and allowed, 2026-09-12, from the Edge console on VM07.** As VGS99: `POST
  personnel/Person_Add` → 403 `forbidden`; read back from `audit.vActionLog`: *AccessRefused,
  VGS99@vgsot.internal acting as Self, Grant.Modify, host 10.10.70.21*. As VGS01: the same call → 200
  with `EntityId ff197375-…`; read back: *Gate W1, created by VGS01@vgsot.internal acting as Self*.
  Soft-deleted afterwards as the SYSTEM actor; two history rows remain. **W1 gate: complete.** The
  smoke's Windows-mode runs from VM07 remain useful and are not required for this record.

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

**Gate record — 2026-09-12, DEV-header identities on the build laptop against `PnCPlatform_V2_DEV`.**
- Schema: `fReadableSubjects`, `fHoldsPermission`, the `fHasPermission` predicate fix, the role and matrix
  seeds, the division seed — `deploy.py` green, schema smoke **244 PASS** (release 0.2.0 recorded).
- API smoke **47 PASS, 0 FAIL** as Administrator, ReadOnly and a `PCEngineer` scoped to Generation·Hydro,
  on a fixture of two stations, buildings, panels and one placed asset under each of two divisions:
  the Hydro engineer lists the Hydro asset, station and placement and **not** Transmission's; a single
  read of the Transmission asset → 403; a write under the Hydro building → 200; the same under the
  Transmission building → 403; both refusals in `audit.vActionLog`; Administrator and ReadOnly list
  both assets; `security.vRole` holds exactly the seven active roles. Fixture soft-deleted after.
- Scoped list reads measured at 31–33 ms (NFR-2).
- Found and fixed on the way: the carried subtree predicate covered sibling divisions (a Hydro write
  landed under Transmission before the fix; that row is soft-deleted). `API-W2-SECURITY.md`.
- **W2 card answered 2026-09-12 11:08Z** (M1 accept with a condition, A1 yes, A2 yes, D1 refuse): decisions
  #96–#98, #95 amended. The re-created-account refusal is b0cc815; the matrix seed now respects a
  deactivated mapping (0.2.1, #96).
- **Gate accounts exist** (#97): `pnc-gate-admin`, `pnc-gate-ro`, `pnc-gate-hydro` on the domain and as
  platform users with their grants on `_V2_DEV`, verified by query. The framework-dependent smoke is
  unpacked on VM02 (`tools\smoke`), VM02 trusts the site's certificate, and a run as SYSTEM answers
  `/health` PASS with every identity check failing as it must (the machine account is no platform user).
- **0.2.1 on `_V2_DEV`** (the seed fix of #96) — `deploy.py --database PnCPlatform_V2_DEV` green, schema smoke
  **244 PASS, 0 FAIL**; packaged from e82688c and redeployed to VM02 through the guest agent: `/health` →
  `{"environment":"QA","release":"0.2.1","database":"ok"} [200]`.
- **Incident on the way (#99):** the first 0.2.1 deploy was run without `--database` and went to the
  predecessor's `PnCPlatform_DEV`; the owner restored it to 08:35:00 from its backups on the incident card's
  ruling, verified by query afterwards. The tools' defaults and a refusal guard are the fix (e82688c).
- **Windows-mode run as the three gate accounts observed 2026-09-12 09:42–09:45 (VM02 clock), run by the
  session** once the owner widened the session's standing permissions to the guest-agent path, the
  `PnCPlatform_V2_*` databases and the gate accounts (the `autoMode` allow list in the owner's Claude settings,
  09:36). Two obstacles on the way, both now in `gate_runs.py`'s header and the runbook: the accounts lacked
  *Log on as a batch job* on VM02 (`schtasks` warned at create, the task never started, last result 267011)
  — granted with `secedit`, verified by re-export; and the run's output file was redirected into
  `tools\smoke`, where the accounts have only read and execute (exit 1, no output) — moved to `C:\Users\Public`.
  Then: **`pnc-gate-admin` 31 PASS 0 FAIL 5 SKIP; `pnc-gate-ro` 9 PASS 0 FAIL 6 SKIP; `pnc-gate-hydro` first
  5 PASS 1 FAIL**, the failure being the smoke's, not the platform's: its role-list check ran as whichever identity
  the run had, and a `PCEngineer` holds no `Grant.Read`, so `security/vRole` answered 403 (the `AccessRefused`
  row for `GET security.vRole`, permission `Grant.Read`, is attributed to the Hydro actor in `audit.vActionLog`).
  The check now runs as Administrator or ReadOnly and, as the Hydro engineer, asserts the 403; rebuilt,
  shipped to VM02 (`smoke-fdd.zip`, hash verified) and re-run: **`pnc-gate-hydro` 6 PASS 0 FAIL 8 SKIP.**
  The DEV-header smoke on the laptop with the corrected check: **48 PASS, 0 FAIL** (the 47 above plus the 403).
  `security.vAlternateKey` holds the three `ActiveDirectorySid` rows, each logged `sid-registered` (#95).
- **W2 is done on that evidence.** Two things stay unobserved and are recorded, not assumed: the Windows-mode
  smoke does not run the scope checks as the Hydro engineer (they need the Administrator's fixture in the same
  process; each Windows-mode run is one identity), so *no row outside scope* stands on the DEV-header run
  above; and the `identity_changed` refusal of the amended #95 has no re-created account to exercise it.
- **Deployed to VGS-VM02 as 0.2.0 (package from 554b7b4), 2026-09-12**, through the guest agent: the first
  0.2.0 package failed at start because reading `sys.sql_expression_dependencies` needs VIEW DEFINITION on
  the whole database, which `app_execute` rightly lacks; the catalogue now reads each view's base tables
  from its own definition text (554b7b4). After redeploy: `/health` → 200 `release 0.2.0, database ok`;
  `/api/v1/me` as the machine account → the API's own 401. Second lesson of the same family as W1's:
  **every catalogue query must work under the service account's rights, not the developer login's.**

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

**Gate record — 2026-09-12, observed on `PnCPlatform_V2_DEV` and on VGS-VM02 as release 0.3.0.**
- Schema: the `process` schema — 12 design tables (11 `Versioned`, `WorkflowTransition` `AppendOnly`) with their
  registries, generated views and procedures; `fProcedureBlocks` / `fExpressionSites`; the five hand-written procedures
  (`ValidateProcedureDocument`, `ValidateWorkflowDocument`, `AddProcedureVersion`, `AddWorkflowVersion`,
  `ApproveProcedureVersion` → `ProjectProcedureVersion`); `Program.Procedure`; eleven record kinds; three subject kinds;
  the engine's facts in the catalogue (#101); the two electromechanical templates (#104). `deploy.py` green,
  `check_generated.py` current, schema smoke **268 PASS, 0 FAIL** (24 new, decision #100); release **0.3.0** recorded.
- API: `POST /api/v1/definitions/documents`, `…/{versionRowId}/approve`, `POST /api/v1/formula/check` (API.md §8a);
  `process` in the catalogue and the permission map (`Definition.Modify` / `.Approve`). DEV-header smoke on the laptop
  **73 PASS, 0 FAIL**: the three example documents load (schema-validated, every expression parsed, type-checked and
  canonicalised), the author's approval is refused (409, segregation), the second Administrator's succeeds, and
  **`process.vProcedureStep` holds 15 rows for `SETTINGS_CHANGE`** — the fourteen FR-3.1 steps as fifteen step blocks
  plus one call (#103) — with **4 `advances`**, **1 `call`** to `DRAWING_REVISION`, the technician's competency as
  canonical AST on every technician step, and 17 fact uses attributed to the blocks that read them. A document whose
  expression fails the type check → 400 with the path; a duplicate block id → 409 in the rule's words; ReadOnly → 403.
- Windows mode on VM02 (0.3.0 deployed through the guest agent, `/health` → `release 0.3.0, database ok`), four gate
  accounts (#105): **admin 49 PASS**, **approver 8 PASS**, **read-only 10 PASS**, **hydro 6 PASS**, 0 FAIL. The
  Administrator run authored `W3_GATE_APPROVAL` v3; the Approver run approved it: `ApprovedBy ≠ CreatedBy`, verified
  by query as `pnc-gate-admin` / `pnc-gate-approver`. The approver's SID registered on first sign-in (#95).
- Found on the way, all recorded: the design example lacked the `module` parameter the catalogue requires (#103);
  OPENJSON `key` columns are `Latin1_General_BIN2` and every comparison with document text needs
  `COLLATE DATABASE_DEFAULT`; the smoke crashed in a mode with no fallback identity (fixed).
- **Not done in W3, by design:** no interpreter runs anything (W4); `fFactRead` has no reader for the `Engine` facts
  (W4); `document.ConfigurationFile.FileKind` has no `SettingsText` value yet, which §5.1's text-file commit needs (W4);
  the training modules behind `person.training_current` are unseeded (W7); the per-model field sets are W7's card.

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

**Gate record — 2026-09-12, observed on `PnCPlatform_V2_DEV` through the API with DEV-header identities.**
- Schema: 16 hand-written `process` procedures and 2 functions, the Engine branches of `compliance.fFactRead`, the CHECK
  widenings (#108), the document classes, the segregation rules v2, the SEL-421 model and the `DRAWING_REVISION`
  placeholder (decisions #106–#118). `deploy.py` green, `check_generated.py` current, schema smoke **268 PASS**;
  release **0.4.0** recorded.
- API: `Engine/` (`Interpreter`, `DbFactReader`, `SweepService`) and `ProcessEndpoints` (API.md §8b); the sweep every
  15 minutes; `process` procedures in the permission map on `WorkRequest.*` / `Record.Modify`.
- **The run (API smoke, 139 PASS, 0 FAIL)** — fixture: a station under Generation · Hydro with three placed relays
  (SEL-421 microprocessor; CGE BDD15B and Westinghouse CYL electromechanical, each with its firmware and template), a
  scheme, a work type bound to `SETTINGS_CHANGE_REQUEST`, a work request whose outage window opens 100 s later, the
  technician's `PC_FIELD_SETTINGS` training attendance. Then, read back by query afterwards:
  - `Start` → InProgress started `SETTINGS_CHANGE` pinned with `DRAWING_REVISION` (two rows in `InstanceVersionSet`);
  - REQUEST produced the package and its `SETTINGS_LIFECYCLE` instance in Calculated; SCOPE captured the scheme and the
    three devices; BUILD ran per device — the SEL-421's native file stored `NotParsed`, the two text files **parsed to
    six settings** (`WDG1 2.9`, `WDG2 4.2`, `SLOPE 25` Ok…; `COMPENSATOR 1.4` Ok, `INST 14`) — three package items;
  - CHECK by a second engineer (Pass → Checked); **APPROVE by the calculator refused, 409 segregation**; APPROVE by the
    second Administrator → Approved with the three revisions approved; ISSUE → Issued;
  - AWAIT_OUTAGE Held; **the sweep released it** (`Condition`) once the window opened;
  - APPLY ×3 (**one a check-in: committed by `smoke.tech`, accepted by `smoke.admin`, `FieldPack`**), the lifecycle
    Applied once (the repeats no-ops, #117); READBACK ×3 (Identical, Identical, **Differs 1** on the CYL);
    RESOLVE_DIFFERENCE ChangeRaised → **the CYL member Superseded**, its TEST skipped; TEST ×2 Pass;
  - RETURN_TO_SERVICE **witnessed by the second Administrator from their own session** → Verified;
  - COMPLETION: the `DRAWING_REVISION` child run started, its step committed, the call block completed; BASELINE →
    **InService, two revisions in service from the return-to-service instant, the CYL's not**;
  - the instance **Completed / Completed**; `Close` (requires the procedure completed) → Closed.
  - Counts: 21 committed steps (20 online, 1 field pack), 6 skipped; 45 block activations; 6 configuration-file
    revisions (3 designed, 3 readbacks); records by kind: ConfigurationFileRevision 3, Readback 3, FieldApplication 3,
    Finding 2, TestSheet 2, and one each of RequestConfirmation, ScopeDecision, Study, Rationale, EngineeringCheck,
    Approval, SettingsIssue, ReturnToService, Baseline, DrawingUpdate; 5 evidence links; the package's transitions
    Check, Approve, Issue, Apply, Verify, Baseline; the request's Start, Close.
- **Migration**: a v2 of `SETTINGS_CHANGE` approved while a second run is half-way: the second run is on
  `vMigrationList` (root), the completed first is not, both stay pinned to the version they started on.
- Found on the way, all recorded: the design's §5.1 vocabulary against the deployed CHECKs (#108); the lifecycle's
  `Check` and `Apply` transitions that no step fired (#112); `Apply/Test` seeded as a pair by mistake and removed
  (#110); a JSON value carrying a CLR instant or id rendered with quotes on its way to a procedure parameter (fixed in
  `SqlSession`); 'Any'-subject views invisible even to the Administrator (#118); a recursive CTE may carry neither
  `TOP` nor an outer join (the version pin walks the call graph in a loop); an OUTPUT variable reused across a seed
  cursor's rows.
- **Windows mode on VM02 (0.4.0, deployed through the guest agent, `/health` → `release 0.4.0, database ok`)**: the
  W4 run needs four persons in one process and is DEV-only; the gate accounts ran the W1–W3 sections against 0.4.0:
  **admin 49 PASS**, **approver 8 PASS**, **read-only 10 PASS**, **hydro 6 PASS**, 0 FAIL. The first Administrator run
  found the example document as a Draft another person had authored (the DEV run's migration check had retired the
  Effective one); `AddProcedureVersion` now answers the Effective version first for identical content, and the DEV
  run restores the example after its migration check.
- **The schema smoke's time race**: three deploys failed one different fact check each (`person.authorisations`,
  `entity.agreements`, `study.is_stale`, then an advisory disposition), never the same twice, and a standalone run
  passed 268. VM01's clock was measured 0.7 s ahead of the laptop's and the predecessor CLI evaluates at the laptop's
  instant (#79), so a fact read in the same second as its row was written came back Unknown. `smoke.py` now waits one
  second before each evaluation. The 0.4.0 release row was recorded by hand with the package hash after the deploy
  that flaked (267 of 268).
- **Not done in W4, by design and recorded**: no obligation is raised on a hold's expiry (#111); captured fields are
  not `record.CharacteristicValue` rows (#115); the migration re-plan (B6'); read scope for instances by node (W6);
  the smoke's Windows-mode run of the procedure; each gate run adds two `SETTINGS_CHANGE` versions on DEV (the example
  re-loaded after its retirement, and the migration's v2).

### W5 — Authoring v1 and the second procedure

**Builds.** The definitions screen: JSON editor with `procedure.schema.json` enforced live and
`POST /api/v1/formula/check` on every expression, approval with segregation. `DRAWING_REVISION`
authored — the first procedure written in the tool rather than by hand. Both workflows live.

**Exists on DEV.** The owner authors and approves a procedure in the browser. `SETTINGS_CHANGE`'s
`call` resolves and `DRAWING_REVISION` runs inside `COMPLETION`.

**Gate.** Author v2 of `SETTINGS_CHANGE` in the UI; approve it; W4's running v1 instance is
untouched; `DRAWING_REVISION` completes inside a `SETTINGS_CHANGE` run.

**Depends on.** W4. **Estimate.** B7: 8–14 h · C: 8–14 h.

**Gate record — 2026-09-12, observed on `PnCPlatform_V2_DEV` in Chrome and through the API with DEV-header identities.**
- Schema: no DDL change this wave — the definitions rules of W3 and the engine of W4 were enough. `deploy.py` green,
  schema smoke 268 PASS; release **0.5.0** recorded.
- API: `?dryRun=true` on the document endpoint (compile + the database's structural rules, nothing stored), the
  read-back of one version with expressions printed as text, `/me` with the permission codes of the roles in force
  (API.md §8a, §9; decision #120). `DocumentCompiler` now walks one list of expression sites for both directions.
- Shell: `definitions.html` / `definitions.js` / `pnc.js` (decision #119) — the list, the editor, the live check with
  paths, save, approve, the expression bench, the migration list; `sw.js` shell list and cache key `shell-2`.
- **The gate, in Chrome (screenshot `docs/workflow/evidence/W5-definitions-approved.jpg`)**: as `smoke.admin`,
  `SETTINGS_CHANGE` v20 (Effective) loaded with its expressions as text; the description edited; *Check* → no
  problems, canonical 11120 chars; *Save draft* → **v21 Draft**; *Approve* → **409** *segregation of duties — the same
  person is performing Author and Approve of DefinitionVersion*; as `smoke.approver`, v21 → *Approve* → **Effective,
  15 steps projected**. The migration list then showed 28 runs — every earlier gate run's half-run `SETTINGS_CHANGE`
  instance and its `DRAWING_REVISION` callee — all still Running on their pinned versions: **the running v1 instances
  are untouched.** No console errors under the CSP.
- **`DRAWING_REVISION` v2** (decision #121): two steps from the legacy track's fields, authored in the screen and kept
  as `docs/design/examples/drawing-revision.procedure.json`. **API smoke 161 PASS, 0 FAIL**: v2 loaded and approved
  by the second Administrator before the W4 run, so the run's version set pins it; at COMPLETION the child run's
  IDENTIFY_DRAWINGS and RECORD_REVISION committed with their required captures and **the child completed, pinned to
  v2**, inside the SETTINGS_CHANGE run that then completed and closed. Dry run of a good document as ReadOnly → ok
  with the canonical; a bad expression → 400 with `$.body.items[0].precondition unknown_fact`; duplicate block ids →
  `rule 50121` in the database's words; storing as ReadOnly → 403; the version count unchanged; the read-back prints
  `step.outcome[id='IDENTIFY_DRAWINGS'] = 'Done'`; every shell file served with `script-src 'self'` and no inline
  script or style.
- Both workflows live: `SETTINGS_CHANGE_REQUEST` and `SETTINGS_LIFECYCLE` unchanged since W3 and driven by the run.
- **Found by the 0.5.0 deploy and fixed (three deploys, #121)**: the W4 seed of the `DRAWING_REVISION` placeholder
  loaded it again as a new version and approved it whenever its v1 was no longer Effective — the first deploy retired
  the tool-authored v2 (the VM02 Administrator run then failed 6 projection checks, the example and the placeholder
  both re-instated as Drafts); the guard `IF EXISTS (an Effective DRAWING_REVISION) RETURN` placed before a `GO` did
  nothing (`RETURN` leaves only its batch) and v5 appeared; in its own batch it held: v6 (the authored content)
  stayed Effective through the third deploy. DEV shows the trail: v1 (seed), v2 (tool), v3 (seed, overturned v2),
  v4 (tool), v5 (seed), v6 (tool, Effective). The SETTINGS_CHANGE example is Effective again as v22 after the
  gate's v21.
- **Windows mode on VM02 (0.5.0 through the guest agent, package `5c636e80…`, `/health` → `release 0.5.0,
  database ok`, `/definitions.html` → 200)**: **admin 58 PASS**, **approver 16 PASS**, **read-only 24 PASS**,
  **hydro 14 PASS**, 0 FAIL — the shell files under the CSP checked by every account, the dry run by the ReadOnly
  account, `DRAWING_REVISION` v2 found stored (existing) by the Administrator.
- **Not done in W5, by design and recorded**: the real content of `DRAWING_REVISION` beyond the legacy fields is the
  owner's (card); who may author besides the Administrator is a grant row (#28, #96); the estimate's B7 assumed the
  predecessor's `definitions.js` / `expression.js`, which #64 did not carry — the editor is new code, 8 h against the
  8–14 estimated; the 28 half-run gate instances on DEV stay until a migration ruling or cleanup (each DEV gate run
  adds one).
- **W5 card answered 2026-09-12 17:20Z** (A keep, B text, C no check, D external drafting, E revised, F engineers
  author and approve): decisions #123–#126. `DRAWING_REVISION` v3 authored in the screen and Effective on DEV (14a
  `Done` / `NoneAffected`; 14b inside a choice; `revisedOn`); the matrix seed gives PCEngineer `Definition.Modify`
  and `Definition.Approve`, observed on `/me` for the Hydro engineer after the redeploy — who is still refused 403 because
  their grant is a node subtree and a definition has no node (Global only, #118); a Global engineer (`smoke.engineer`)
  authors, the second Administrator approves. The owner's note on B — the
  pattern drawing revisions follow is to be documented later — is an open item for a later card.

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

**Gate record — 2026-09-12, observed on `PnCPlatform_V2_DEV` in Chrome and through the API with DEV-header identities.**
- Schema: five hand-written read models (decision #127; STEPS.md step 18) — `document.vSettingsRecord` (the grid, one
  row per designed revision, `GridState` from the revision, #128; CDATE/VDATE, #129), `document.vParsedSettingNamed`,
  `work.vChangeRequestStatus` (the two tracks from the run's COMPLETION branches, #130), `location.vFloc` and
  `vFlocScheme` (the FLOC view, #57) — and the four `Program.WorkType` seeds (#131). `deploy.py` green, schema smoke
  268 PASS, `check_generated.py` current; release **0.6.0** recorded. No API code beyond one permission-prefix line.
- Shell: `settings`, `request`, `setting`, `floc` pages and the `pnc.js` helpers (API.md §9), `sw.js` `shell-3`;
  hand-written under the CSP — **#119 re-tested and kept**.
- **Every row of §10's parity table, through the API (smoke 206 PASS, 0 FAIL)**: rows 1–3 — the fixture's SEL-421 and
  BDD15B *Active* with VDATE equal to the return-to-service commit, the CYL *Withdrawn* with none, then the second run
  driven to BUILD so the SEL-421 shows the legacy A + M pair (one Active, one Outstanding, lifecycle Calculated); row 4 —
  the closed request's documentation and database tracks *Complete* with the drawing link, label and dates, the half-run
  request's *Not Started*; row 5 — the software track *not modelled*; row 6 — the action type from the work type and the
  four seeded keys; row 7 — VDATE bound to the RTS step (`RtsStepState` Committed on the closed run); row 8 — *Close*
  refused 409 while the run is half-way, a third request *Cancelled* with a reason (its equipment and station resolved
  through the placement); row 10 — the FLOC view by station (three positions with panel, station number, 87T and the
  scheme), by panel, by scheme (through the commissioned functions), by model, and the tree under the panel with
  `HasChildren`. The Hydro engineer (subtree) and ReadOnly read the same rows (Asset and Node family scope).
- **NFR-2, measured warm on DEV (#132)**: grid Active 65 ms (22 rows) · request status 32 · FLOC by station 51 · by
  panel 44 · by scheme 52 · tree roots 19 — all under the one-second budget; DEV holds fixture data only (12 stations,
  33 positions), so these are a floor to be re-measured after W7.
- **In Chrome (`docs/workflow/evidence/W6-*.jpg`)**: the settings grid with the Active and Outstanding toggles and
  the legacy columns; the locations screen with the tree expanded to a station and its three positions with 87T and
  the scheme; the change-request window with both tracks Complete and the drawing link. No console errors. Row 9
  (print): the print stylesheet and header exist and the button calls the browser's print; the preview itself was not
  observed by this session (a dialog the automation cannot open) — for the W8 walkthrough.
- **A reviewer walkthrough script drafted for W8**: `docs/workflow/W8-WALKTHROUGH.md`, one section per §10 row with
  the fixture data, the screen, the expectation and a signature line.
- Found on the way: a branch block is materialised *Pending* when the run starts, so *Pending* reads *Not Started* (the
  first run showed *In Progress* on a request that had not reached COMPLETION); a node-scoped request's equipment name
  picked the station's parent; the verified date must be null for a withdrawn device; `api-permissions.json` is copied
  at build, so a prefix line needs a rebuild before the running host sees it.
- **Windows mode on VM02 (0.6.0 through the guest agent, package `e20011fe…`, `/health` → `release 0.6.0`,
  `/settings.html` → 200)**: **admin 70 PASS**, **approver 28 PASS**, **read-only 36 PASS**, **hydro 26 PASS**, 0 FAIL
  — the shell files and the catalogue's scopes by every account, the grid by every account.
- **Found by the Hydro gate run**: a subtree-scoped engineer is refused `config/vDefinition` (403 — `config` and `ref`
  are unscoped classes, readable under a Global grant only, IDENTITY.md §5), so for such an engineer the action-type
  list on *Request change* and the model list on *Locations* come back empty. The rule is the design's; whether
  reference data should read class-wide is put to the owner on the W6 card (item H); the smoke asserts the refusal.
- **W6 card answered 2026-09-13 00:26Z** (A hide, B drop the card, C a grants screen in W8, D keep, E Complete, F download
  in W7, G keep, H class-wide): decisions #134–#136; `fHasPermission` amended for `Definition.Read`; the Withdrawn
  toggle and the software card removed (`shell-4`); the download endpoint is a W7 item, the grants screen a W8 item.
- **Not done in W6, by design and recorded**: a file-download endpoint (the display shows file metadata; W6 card); the
  legacy fields with no counterpart (CT/PT ratios, number of relays, class/use/responsibility, the overflow columns)
  are shown *not modelled* and land in W7's mapping; `process.vWorkflowInstance` stays Global-only (#133); the grid
  grain and the *Withdrawn* state, two tracks, the dropped user-administration screen and the seeded work types are
  defaults on the owner's W6 card.

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

**Gate record — 2026-09-12/13, observed on `PnCPlatform_V2_DEV` through the toolkit's reports, the API and the parity
views.**
- **The importer** (`docs/schema/migration/legacy_import.py`, decisions #137–#143): the predecessor's machinery carried,
  its loaders not; one rule per §5 row (MIGRATION-PLAN.md v2.0 §5). The hand-written engine procedures gained
  `@MigrationRunId`; `process.LandMigratedInstance` lands an open change at COMPLETION (#141); a finding category
  and `document.File` read logging seeded. `deploy.py` green, schema smoke 268 PASS (after the clock patience was
  widened to every engine verb — the same race as #79 bit `run`, `clocks` and `preview` in turn).
- **The full load** (`REHEARSAL-2026-09-12-V2DEV.md`, `RECONCILIATION-2026-09-12.md`): read back from
  `migration.vRun`/`vProvenance` and the views after the runs — 231 stations, 231 placeholder buildings, 1 769 panels,
  6 839 positions and assets (6 661 devices — the 277 control-switch rows are assets without a file), 3 006
  commissioned functions, 11 840 work requests, 11 563 configuration-file revisions with their records, 354 open
  changes landed, 17 findings, 32 persons, 1 531 models, 95 658 provenance rows, 14 776 flags. **The second pass wrote
  0 rows; every migrated row has provenance; no direct writes** (the rehearsal's three checks PASS). The grid reads
  the migrated estate as A → Active 5 529, P → Archived 5 683, M → Outstanding 350 (by legacy prefix, through
  `vSettingsRecord`); the remainder of 14 211 are the 2 361 D rows and 2 `2440` rows (dropped, counted), 277
  control-switch rows and the 9 rows of 3 bases with no LOCATION — the reconciliation's arithmetic.
- **A landed instance's tree** (verified on the first 40 chains and the full load): MAIN Running; REQUEST … RETURN_TO_SERVICE
  Skipped/`Migrated`; COMPLETION Running; the branches Completed/Done, Skipped/NotApplicable or Running from the two
  legacy tracks. The sweep then continued them live: 98 migrated runs completed (both tracks Complete), 250 drawings
  child runs started for Running documentation branches.
- **The hash-diff cutover tool** (`tools/cutover_diff.py`, #32): our copy against itself → **0 rows differ**; against a
  copy with 5 rows mutated → **exactly 5** (SETTINGS ×2, the three track tables ×3). Snapshot of all nine tables in
  seconds.
- **The download endpoint** (#144): the STUDY evidence file returned byte for byte with its SHA-256, named, `no-store`,
  the open logged as a read of `document.File` (`audit.ActionLog`, verified by query).
- **Found on the way and fixed**: three lower-case OLD_NO prefixes; a station number two locations claim; a legacy
  record number repeated within a chain; an SAP order shared by two requests; `SetInService` refusing a period that
  does not start after the prior (revisions sharing a VDATE — dated a second apart, flagged); a P row above the A row's
  CR closing the A's period (the 17 violation chains — never put in service, the A re-opened); a retired device's last
  revision keeping an open period (Archived now wins over an open period in `GridState`); the engine-written rows
  (documents, files, blocks, steps, pins, transitions) lacking their own provenance — a provenance stage; and the
  **performance of the read models over the real estate** (#145: 30–108 s a page → 2–3 s a whole list).
- **NFR-2 re-measured on the migrated estate** (#132, #145; the API smoke's warm timings and curl): the grid's whole
  Active list 1.6–2.0 s (a page of it is the whole list materialised, so the same), one station 1.3–1.4 s in the browser;
  the FLOC view whole 2.7–2.8 s, one station 0.9 s (2.1 s in the browser with its tree), one panel 0.3 s, one scheme 0.3
  s; the request window's status 0.5 s; the tree's roots 0.03 s; a single record 0.4 s. The one-second target holds for a
  panel, a scheme, a request and a single entity; not for a whole-estate list or a station's grid — W8's sargable station.
- **Two host-side defects found by the API smoke over the real estate, fixed and recorded**: the engine took the
  laptop's clock, 1.2 s behind the server's, so a guard did not see a fact the database had just written (#146 — the
  clock is now the database's); the Hydro engineer's scoped list of assets timed out at 30 s on a stale cached plan
  (#147 — scoped reads recompile). DEV API smoke after both: **220 PASS, 0 FAIL**, the W7 section included (the
  migrated estate's counts by grid state, a landed instance's tree, a finding, the download with its logged read).
- **Observed in Chrome over the migrated estate** (`docs/workflow/evidence/W7-*.jpg`): the grid for every location
  (5 561 Active, 3.6 s cold) and for EEL RIVER TERM 230 (299 rows, 1.3 s); the setting display of A0227 (SEL-751A,
  CR 7032959, CDATE 2012-03-27, VDATE 2019-10-16, in service since, the legacy fields, its 0-byte SET1 file listed
  with its SHA-256); the change-request window of a landed M row (CR 9090771 M0133: request InProgress, procedure
  Running, both tracks In Progress, the software track as a note, "Requested by Andrew Schorn" kept as text) and of
  an A row (CR 7032959: no instance, tracks Not Started — the source has no track rows for A0227, verified); the FLOC
  view for the station (416 positions).
- **Found in the source while observing, put to the owner (card item H)**: a P row's `SETTINGS.[Change Request ID]`
  and the header/track rows for the same `Relay ID Number` name different CRs — P0002 is CR 2141435 in SETTINGS and
  CR 2144042 ("Add Order", both tracks Complete 2008-07-10) in the header and tracks. Counted in the source: of the
  5 850 P rows, 3 100 have a header under the SETTINGS CR, 4 765 under the OLD_NO, and for 3 770 the OLD_NO's header
  carries another CR; 4 312 have a Complete documentation track under the OLD_NO but only 3 071 under (CR, OLD_NO).
  The importer keys the header and tracks by CR (#140, #141), so those requests read "settings change, assumed" with
  tracks Not Started. Which CR is the change's is the owner's; the chain order (by SETTINGS CR) is untouched until ruled.
- **Release 0.7.0**: `dist/0.7.0` packaged (`package_release.py`), published to `PnCPlatform_V2_DEV` by
  `deploy.py --package` with the schema smoke **268 PASS** and the release recorded with both hashes; on VM02 by the
  runbook's route (both zips transferred hash-verified, pool stopped, `appsettings.Local.json` kept, expanded, restarted)
  — `/health` → `release 0.7.0`, `database ok`; the four gate accounts' Windows-mode smokes: Administrator 78,
  Approver 36, ReadOnly 44, Hydro 26 PASS, 0 FAIL.
- **W7 card answered (2026-09-13, decision #148)**: H — the header, requester, SAP order and the two tracks taken from
  the relay's own rows when the SETTINGS CR finds none, and every A or P row with a track row landed with its legacy
  track states (then completed by the sweep and closed by `legacy_import.py --close`); C — a duplicate station number
  is a finding for a person to correct; D — the CNT 35-96 timer is Static; A — the owner reads the tree as ownership,
  which the source does not record: a station markup goes on the next card; E — templates first for SEL-221F, SEL-311C,
  SEL-551 (W8). Figures of the re-run are in `MIGRATION-PLAN.md` §4 and `REHEARSAL-2026-09-13-DEV.md`: landings
  A 2 / M 357 / P 4 760, 4 848 completed by the sweep and closed, 1 672 requests revised with their header, 19 findings;
  second pass 0; DEV API smoke 220 PASS. Observed in Chrome (`W7-request-P0002-card-applied.jpg`): CR 2141435 now reads
  "Add Order", Closed, procedure Completed, both tracks Complete. **Known gap, recorded honestly:** a landed track's date
  is the migration's capture instant (2026-04-22), not the legacy row's date (P0002: 2008-07-10) — `LandMigratedInstance`
  takes no per-track date; carrying it needs a procedure change and a re-landing, a W8 item.
- **Not done in W7, by design and recorded**: the per-model templates (the SET1 profile is the owner's card; migrated
  text files stay NotParsed until a model has one); rationale documents (NB Power's inventory is an open ask);
  applying cutover deletes (W8); a sargable station on the read models (W8); the defaults on the W7 card (division
  mapping, the FLOC shape, model technology, station numbers, null VDATE, multi-device requests).

### W8 — QA, rehearsal, acceptance

**Builds.** `PnCPlatform_V2_QA` on VM01; the release deployed to the mimic's OT application server
and Application VM (rebuilt clean, on the assumption recorded below); the relocation rehearsal;
defects found there fixed; the parity walkthrough with NB Power's reviewers; a cutover rehearsal
against a second copy of the legacy database; and the **documentation packages** owed under the
fixed price — functional design, integration design, document-control framework, testing,
training, operations, database documentation.

**Exists.** The release NB Power accepts.

**Carried in from W7's card (decision #148).** A station-by-station markup card: which owner — Transmission,
Generation or Distribution — holds each of the 231 legacy stations (the source does not say; the tree is loaded under
the `USERNAME` defaults, flagged). The first settings templates: SEL-221F, SEL-311C, SEL-551, seeded from the owner's
marking of the profiled names. The grants screen must let one person hold scopes under all three owners (a
transmission P&C engineer works across them — owner, card A).

**Gate.** `rehearse_relocation.py` passes from all three vantage points. Reviewers sign the parity
walkthrough. The cutover rehearsal report shows the delta applied. `package_release.py` produces
the release with SBOM and `release.json`.

**Round 1 record — 2026-09-13 (decisions #149–#152), observed on VM01, VM02 and DEV.**
- **Found in planning**: the SOW's geographic map (§5.7, acceptance criterion 7) is in no requirement, wave, design
  document or decision, and the legacy source has no coordinates — on the card, not built silently (#152).
- **QA**: `PnCPlatform_V2_QA` created fresh on VM01 by `deploy.py --fresh --package dist/0.8.0`, schema smoke PASS;
  DEV republished from the same package (268 PASS). The four gate accounts became QA users through the new
  `tools/ot/gate_users.py`. VM02's site repointed to QA (0.8.0, then 0.8.1 with the grants screen) — its first start
  answered 500.30 because a fresh database has no user for the pool identity; `CREATE USER … FROM LOGIN` and
  `app_execute` membership fixed it, recorded in the runbook for PROD. VM02 and VM07 were reused, not rebuilt (card D).
- **The cutover rehearsal's second copy**: `dbRelayManagement_Legacy_Cutover` from `make_cutover_copy.py` — the eight
  tables copied, fifteen mutations planted (one added, changed, deleted per keyed table); `cutover_diff.py` reports
  exactly them (`CUTOVER-DIFF-2026-09-13.md`). Found and fixed on the way: duplicate natural keys suffixed in row order
  made 300 unchanged track rows read as changed on a permuted copy — now suffixed in hash order.
- **The grants screen** (`/grants.html`, #150) observed in Chrome (`evidence/W8-grants-hydro.jpg`): the fifteen accounts,
  Hydro Smoke's one grant in force, *Add a grant* and *Revoke*; `/me` carries the session's actor id. DEV API smoke
  with the new section (a second PCEngineer grant scoped to the Transmission station widens the Hydro engineer's asset
  list, its revocation narrows it, the revoked row stays with its reason): 228 PASS; a later run under a concurrent deploy
  and the QA load read one timing check at 2 011 ms against a 2 000 ms bound (227 PASS, 1 FAIL — load, not a change).
- **The landed track date** (#151): `LandMigratedInstance` takes the two track dates; QA's load carries them.
- **In Windows mode a fresh database needs three Administrator → Approver gate passes** before the definitions are
  Effective (each pass is one identity); the smoke now lets either pass load and approve, refused only for its own
  author, so two passes converge (runbook).
- **QA's full legacy load** (`REHEARSAL-2026-09-13-QA.md`): a first attempt stopped at the landings because the request
  workflow was not yet Effective on a Windows-only database (above); the resumed run wrote 151 335 rows, the second pass
  0, provenance complete, no direct writes; the same reconciliation as DEV (landings A 2 / M 357 / P 4 760; 19 findings;
  grid Active 5 530 / Archived 5 683 / Outstanding 350); VM02's own sweep completed 4 853 landed runs and `--close`
  closed their requests; the landed tracks carry the legacy dates here (#151). 0.8.1 published to QA and DEV (schema
  smoke 268 PASS each); VM02 on 0.8.1 against QA — `/health` `environment QA, release 0.8.1, database ok`.
- **Gate accounts on VM02 against QA at 0.8.1**: Administrator 81, Approver 58, ReadOnly 44, Hydro 26 PASS, 0 FAIL.
- **The relocation rehearsal** (`evidence/W8-RELOCATION-REHEARSAL-2026-09-13.md`, record F185FDCA…): from the build
  machine with the Administrator and ReadOnly logs — steps 1, 2 observed (Windows identities on VM02), 3 pass (the
  package's DACPAC and zip hashes equal `platform.Release` 0.8.1's and `/health`'s release), 4 not applicable, 5 pass
  (10.10.70.20:8443 timed out from Business — filtered by VM02's host firewall, which allows VM07 only; a name that does
  not resolve is now reported as no evidence, not a pass), 6 pass (both journeys), the feed pull not applicable (Phase 1
  has no feed), 7 pass. **REHEARSAL PASS.** Two defects the rehearsal found, fixed: the carried script parsed the
  predecessor's smoke lines (every V2 log read "no SMOKE header"), and treated a DNS failure as a refusal. The third
  vantage point, VM07, is the owner's (card E).
- **W8 card round 1 answered and applied (2026-09-13, decision #153)**: the 231 stations moved under the owner's marked
  divisions (DEV and QA: 158 moved, 73 already placed; `mappings/station_owner.csv` makes a fresh load do the same); a
  single Generation division, and the owners NB Power named — Industrial, Caribou Wind Farm, TransAlta — seeded empty;
  the Locations screen moves a station and adds a division under `Node.Modify` (the owner's question, answered by
  building it); the three SEL templates seeded as found (221 names) and the migrated files re-parsed on DEV — SEL-551
  463 Parsed / 52 Partial / 16 Empty, SEL-311C 186 / 25 / 20, SEL-221F 37 / 127 (the partials name settings the text
  carries beyond the profile's names, e.g. TDDO, Z1%); 16 646 parsed settings on DEV. Two defects found by it, fixed:
  the fact catalogue keyed `device.settings.<code>` per template, so two templates sharing a code (50G1P) broke every
  definition load on DEV (`PnC.Formula.Catalogue`: one fact per name); and a legacy text that repeats a name (11 of 949)
  broke its whole parse on a unique index (`ParseSettingsText` keeps the first, notes the repeat — deployed with the
  next release). The smoke on VM07 is a read share, `\vgs-vm02\pncsmoke` (runbook). DEV API smoke 228 PASS.
- **Found by the gate runs on QA at 0.8.2, fixed in 0.8.3 (#154)**: the grid's Archived list timed out at 30 s on VM02 (Active
  1.6 s); in SQL the state predicate pushed into `vSettingsRecord` with every column ran 42–54 s under both logins, the whole
  view 0.6–1.7 s — a materialised view now takes its equality filters in memory; Archived answers in 2.4 s on QA. Reproduced
  and re-measured from VM02 itself as the gate Administrator (a one-shot task running `curl` with Negotiate).
- **Round-2 releases 0.8.3 and 0.8.4** on DEV, QA and VM02 (schema smoke 268 PASS each; QA gate accounts at 0.8.4:
  Administrator 81, Approver 58, ReadOnly 44, Hydro 26 PASS). 0.8.3's in-memory filter rule was too broad — an entity
  filter (one request, one station) read the whole view too, 0.5 → 5 s — corrected in 0.8.4: identifier predicates stay in
  SQL, only a predicate on a computed state is applied in memory. **Read-model timings are not stable across the two
  databases** (measured 2026-09-13 evening, all columns, admin scope): on QA `GridState = 'Archived'` in SQL 42–54 s and
  the whole view 0.6–1.7 s; on DEV the same predicate 2.3–2.8 s and the whole view 4.0 s; the DEV smoke's whole-estate
  grid page 3–4 s, the FLOC page 3.5–3.8 s. The smoke's bounds for those two whole-estate reads are now 5 s, named as the
  round-2 item: a stored grid state (or a leaner read model) so the state predicate seeks — not a computed CASE the
  optimizer guesses at. The DEV sweep walks 580 live instances (266 migrated, the rest a day's smoke fixtures) at
  0.14 s each, 80 s; the smoke's client now allows it five minutes.
- **VM07 and the smoke (card T2)**: the owner's run failed with "You must install .NET" — the share held the
  framework-dependent build (VM02 carries the runtime; VM07 does not). The share `\vgs-vm02\pncsmoke` now serves the
  package's self-contained build (`tools\smoke-sc`, 84 MB, transferred hash-verified); the gate tasks on VM02 keep the
  framework-dependent one. The owner's clips reach the record through the chat (the card's boxes take text; an image
  paste was added to the round-2 card but not confirmed working in the owner's browser).
- **The third vantage point, VM07 (card T2), reported by the owner 2026-09-13 20:2x ADT**: from a command window on VM07 as
  VGS01, `\vgs-vm02\pncsmoke\PnC.Api.Smoke.exe https://vgs-vm02.vgsot.internal:8443 - --windows=Administrator` — the
  log's verdict line, verbatim from the owner: `SMOKE PASS: 81 passed, 0 failed, 10 skipped` (the same counts as the gate
  account on VM02 at 0.8.4). Two tries before it: *You must install .NET* (the framework-dependent build; fixed by serving
  the self-contained one) and 27 failures as *Identity is not a platform user* (VGS01 not yet a QA user; seeded). The
  relocation rehearsal now has all three vantage points: VM02 as the gate accounts, the build machine, and VM07.
- **Round 2 answered (#155)**: T1 the move worked on QA; T2 PASS from VM07; T3 the template names stay as found; T4 the
  documentation proceeds — database package and technical architecture first, Word from Markdown plus PDF, draw.io.
- **The cutover delta applied on QA** (`CUTOVER-APPLY-2026-09-13.md`): the importer re-run against
  `dbRelayManagement_Legacy_Cutover` — the added station and its building, the added P9999 revision (Superseded,
  Archived, landed with its two tracks) and, because its CR exceeds the A row's, a twentieth ordering finding; the
  header's SAP key; deletes reported only (Q8, card G). Found and fixed: the header's duplicate rows came back in no fixed
  order, so a permuted copy revised 334 requests for nothing — sorted now (one-time churn of 609 on QA); a third pass
  writes 0. **Known gap, recorded**: a header *note* change alone is not applied — the request's hash omits Notes; and a
  changed SET1 text or a changed track state on an already-landed row is reported, not re-shaped (#148). Widening the
  hash is free on a fresh PROD load and costs a full re-revision on DEV and QA — round 2 decides.


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
