# PnC.Api — the application tier

**v0.2 · 2026-09-11 · W1 specification, as built.** What the API skeleton is, why each part is shaped as it
is, and how W1 knows it is done. Later waves extend this document; they do not replace it.

The predecessor's API was **consulted, not copied** (decision #64). Where this design agrees with
`C:\Projects\PnCPlatform\docs\PLATFORM-ARCHITECTURE.md` it says so by section; every such point was
read this session before being adopted. Where it departs, the departure is marked **V2**.

---

## 0. The one paragraph

The API is the database's procedures and views, exposed one operation per procedure and one query
per view, behind a **generic dispatcher** that reads what exists from `sys.*` at start. A handler
authenticates the person, decides one permission with `security.fHasPermission`, sets the session
context the procedures read, calls the procedure or view, and returns what it said — including its
refusals, in its words. **No rule lives in C#.** A rule that exists only in the application tier
is a defect (agrees with PnCPlatform §2.3). Everything else in this document is consequence.

---

## 1. Scope of W1

From `PHASE-1-WORKFLOW.md` W1. Builds `src/PnC.Api` on .NET 10 with:

| Part | What it is |
|---|---|
| Catalog | procedures, parameters, defaults, views and columns, read from `sys.*` at start for the configured schemas |
| Dispatcher | `POST /api/v1/{schema}/{procedure}` · `GET /api/v1/{schema}/{view}` |
| PermissionMap | (schema, object) → `<SubjectClass>.<Verb>` permission code |
| AuthorizationService | one call to `security.fHasPermission`; refusal logged, then 403 |
| Identity | Windows authentication via IIS; the DEV-only header `X-PnC-Dev-User` |
| Fixed endpoints | `/health` · `/api/v1/me` · `/api/v1/catalog` |
| PWA shell | `wwwroot/` — manifest, service worker, one page listing the catalogue |
| `PnC.Api.Smoke` | rewritten to this surface (§8) |
| `package_release.py` | pointed at the new project |

**Not in W1:** roles and scopes as ruled in #66 (W2); the `process` schema (W3); the interpreter
(W4); screens (W6); any React or other UI framework (a W5/W6 ruling); feeds, notifications, rule
runs, forms, definitions and formula endpoints of the predecessor (each returns when its wave
needs it, re-justified then).

---

## 2. Identity and attribution

**2.1 Who the API is to the database.** The server connects as its Windows service account
(`VGSOT\svc-pncapi` on the OT application server), a member of `app_execute` and nothing else:
EXECUTE on procedures, SELECT on views, VIEW DEFINITION for the catalogue, no table permission.
Agrees with PnCPlatform §2.2 and `Roles.sql`. On DEV the connection string is overridden in the
gitignored `appsettings.Local.json` with the tooling's `dev_pnc` login — the documented DEV-only
deviation, and the only one.

**2.2 Who the person is.** IIS authenticates the browser with Windows authentication (Negotiate)
against `vgsot.internal`. The authenticated name is matched, case-insensitively, to exactly one
enabled `security.User` by `UserPrincipalName`. A domain account with no `security.User` row is
refused with 401: **presence in the directory grants nothing** (agrees with §4.2). W2 adds the
directory SID as an alternate key so a renamed account keeps its history; W1 matches on the name.

**2.3 Attribution is the database's.** Before any call the request's connection sets
`SESSION_CONTEXT('UserPrincipalName')`, and `DelegationEntityId` or `SponsoredPersonEntityId`
when the request carries `X-PnC-Delegation` or `X-PnC-Sponsored-Person`. The procedures call
`personnel.ResolveActor` (its resolution order is in the procedure's header). **The server never
passes an `ActorId` of its own choosing**, and `@ActorId` / `@MigrationRunId` are never bound from
a request body. Attribution cannot be forged from the application tier (agrees with §2.2).

**2.4 The DEV-only header.** `X-PnC-Dev-User: <upn>` asserts an identity. It is honoured only when
**both** hold: `Auth:Mode = Development` (set only in the gitignored local settings; the shipped
`appsettings.json` says `Windows`) **and** the environment name is `DEV`. **The host's default
environment name is `Production`** — DEV is said explicitly on the build laptop, never assumed. Development mode in any
other environment fails every request with 500 `auth_mode`, so a misconfigured QA cannot quietly
accept asserted identities. In Windows mode the header is never read. Agrees with the
predecessor's `appsettings.json` and `RequestUserMiddleware`.

---

## 3. The catalogue

Loaded once at start, from the schemas named in `Api:Schemas`:

- **Procedures**: `sys.procedures` × `sys.parameters` × `sys.types` — name, direction, SQL type,
  length/precision/scale. Whether a parameter has a default is **not** in `sys.parameters` for
  T-SQL procedures (`has_default_value` is populated for CLR only — the predecessor found this),
  so the header of `OBJECT_DEFINITION()` is parsed for `= <default>` per parameter. `VIEW
  DEFINITION` on each schema is what makes that possible for `app_execute`.
- **Views**: `sys.views` where the name starts with `v`, with their columns and types; and the
  as-of table functions `f…AsOf`.
- Everything the catalogue holds is what `GET /api/v1/catalog` reports, each entry with the
  permission code the map assigns (§4) or `callable: false`.

`/health` reports `catalogLoadedAt`. A deploy that adds a procedure is followed by an app restart;
that is the whole invalidation story, and it is enough at this scale (NFR-2).

---

## 4. Permission mapping

`PermissionCode = <SubjectClass>.<Verb>` — the vocabulary seeded by
`PostDeploy/Seed_security_Permission.sql` (12 subject classes × Read, Modify, Approve, Archive,
Report, Administer). The map from an API object to a code lives in **`api-permissions.json`**,
shipped beside the binary and part of the release package (so it is versioned and reviewable with
the release, never edited on a server):

```json
{ "subjectClassBySchema": { "asset": "Asset", "device": "Device", "work": "WorkRequest", ... },
  "subjectClassByPrefix": { "document.ConfigurationFile": "ConfigurationFile", ... },
  "procedures": { "personnel.ResolveActor": null, "security.CheckSegregation": null, ... } }
```

Rules, in order:
1. An explicit `procedures` entry wins; `null` means **not callable over HTTP** (404
   `not_callable`).
2. Otherwise a generated procedure is classified by its suffix: `_Add | _Revise | _Update |
   _Append | _Upsert` → `<Class>.Modify`; `_SoftDelete | _Deactivate` → `<Class>.Archive`.
3. **A hand-written procedure absent from the map is not callable.** Safe by default: a new
   procedure reaches the API only when someone has said what right it needs.
4. A view is `<Class>.Read`, class from the prefix rules then the schema.

Agrees with the predecessor's `PermissionMap`. **V2:** the map file is validated at start against
the catalogue — an entry naming a procedure that does not exist fails startup, so the map cannot
silently drift from the schema.

---

## 5. Authorization and read logging

One decision per request: `SELECT security.fHasPermission(@user, @code, @subjectKind,
@subjectEntityId, SYSDATETIMEOFFSET())`. Roles, grants, delegations and scope are the function's
business; the API evaluates none of them (agrees with §2.4). The subject for a write is the first
recognised subject key in the body (`EntityId`, `AssetEntityId`, …, per the map's `subjectKeys`
list); for a read it is the `EntityId` filter when present, else the class alone.

A refusal is written to `audit.ActionLog` as `AccessRefused` (operation, permission, host)
**before** the 403 is returned; an unauthenticated request is 401 and not logged.

**Read logging — V2 departs from the predecessor.** The predecessor hard-coded the one logged
class in C#. Here the API loads `config.vReadLoggedClass` with the catalogue and, for a read of a
view whose base table is listed, calls `audit.LogRead` **before** the rows are returned (FR-6.4;
PnCPlatform #65). Switching a class on is a row, not a release.

---

## 6. The dispatcher

**`POST /api/v1/{schema}/{procedure}`**, body a JSON object, **`Content-Type: application/json` required**
(415 otherwise): a cross-origin page cannot send that type without a CORS preflight this API never
answers, which closes the cross-site form-post route to a Windows-authenticated user's procedures
(`docs/review/API-W1-SECURITY.md` #1).
- Parameters come from the catalogue, never from the body's shape. A body key matches a parameter
  by name, PascalCase or camelCase. Missing and no default → 400 `missing_parameter`; missing with
  a default → omitted so the procedure's own default applies. OUTPUT parameters are returned at the
  top level keyed by name; result sets as `results: [[row, …], …]`. An object or array value is
  passed as JSON text.
- **Errors are the procedures' errors.** `THROW` ≥ 50000 → **409** `application/problem+json`
  `{status, code: "rule", detail: <the procedure's message>, sqlNumber}`. Constraint violations
  (2627, 2601, 547) → 409 `constraint`. Anything else → 500 `internal`, detail withheld, logged.
  Agrees with §2.3.

**`GET /api/v1/{schema}/{view}`**
- Query keys other than `orderBy`, `skip`, `take`, `asOf` are equality filters; `null` means
  `IS NULL`. Every filter and order column is checked against the catalogue (400
  `unknown_column`); nothing from the query string reaches SQL text.
- Ordering is `RowSeq` when present, else the first column; `orderBy` may be `-Name` for DESC and
  `RowSeq` is always the tiebreaker so paging is stable.
- `take` defaults to 100, clamped to `[1, Api:MaxTake]`; `OFFSET … FETCH`.
- `asOf` on an `f…AsOf` function calls it with the instant.

Every request opens one connection, sets session context, does its work, closes. There is no
connection reuse across identities, so a session context can never leak between people.

---

## 7. Fixed endpoints, headers, configuration

| Endpoint | Identity | Returns |
|---|---|---|
| `GET /health` | none; its own connection | `environment`, `release` (latest succeeded `platform.vDeployment` for `DB_NAME()`), `database: ok/unreachable`, `catalogLoadedAt`. **No data.** |
| `GET /api/v1/me` | required | the user (`EntityId`, UPN), person, current grants (`security.fGrantAsOf`) and delegations in force (`fDelegationAsOf`) |
| `GET /api/v1/catalog` | required | every procedure with parameters and permission code; every view with columns and code |

**Security headers on every response** (agrees with the predecessor's first middleware):
`Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'
data:; frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy:
no-referrer`, `Cache-Control: no-store` under `/api`. Consequence for every UI ever served by this
site: **no inline script, no inline style, no runtime fetch outside the origin** — the OT zone
reaches no external network anyway.

**Configuration** (`appsettings.json`, overridden by the gitignored `appsettings.Local.json`):
`Database:ConnectionString` · `Api:Schemas` · `Api:MaxTake` (default 500) · `Auth:Mode`
(`Windows` | `Development`) · `Logging:*`. Nothing secret ships in the repository.

**Packages:** one — `Microsoft.Data.SqlClient` 6.0.2 (in the local NuGet cache; agrees with
PnCPlatform #239, "one package"). `PnC.Formula` is referenced for later waves' checker endpoint,
not used in W1.

---

## 8. `PnC.Api.Smoke` — the W1 gate

Console program, exit 1 on any failure. Usage:

```
PnC.Api.Smoke <api base url> [<connection string> | -] [--windows=Administrator|ReadOnly]
```

DEV mode (no `--windows`): bootstraps three users through the procedures as the SYSTEM actor —
`smoke.admin@…` with a Global `Administrator` grant, `smoke.readonly@…` with `ReadOnly` — and
asserts identity with `X-PnC-Dev-User`. Windows mode: the process's own identity (VGS01 or VGS99
on VGS-VM07), SKIP for checks needing the other identity.

Checks:
1. `/health` — database ok, `release` equals the DacVersion the smoke was built with.
2. `/me` as Administrator — signed in, grant listed.
3. `/me` with no identity → 401; unknown identity → 401.
4. `/catalog` — lists every schema in `Api:Schemas`; > 100 procedures, > 100 views.
5. `GET asset/vAsset?take=5` as ReadOnly → 200.
6. `GET asset/vAsset?NoSuchColumn=1` → 400 `unknown_column`.
7. `POST personnel/Person_Add` as ReadOnly → 403 `forbidden`; as Administrator → 200 with
   `EntityId`; `audit.vActionLog` has an `AccessRefused` row for the ReadOnly user (when a
   connection string is given).
8. `POST personnel/Person_Add` with no body → 400 `missing_parameter`.
9. `POST asset/NoSuchProcedure` → 404 `unknown_procedure`; `POST personnel/ResolveActor` → 404
   `not_callable`.
10. A `THROW` surfaces as 409 `rule` with the procedure's own message (`security.Grant_Add` with a
    `NodeSubtree` scope and no node — the CHECK the schema smoke already relies on).
11. Cleanup: soft-delete what the smoke created. Never a hard delete.

**Gate, as the workflow states it:** smoke from the Application VM: `/health` reports the release;
`/me` as VGS01 and VGS99; `/catalog` lists the schemas; one view read as ReadOnly; one write refused
as ReadOnly and allowed as Administrator. Deployed from a release package.

---

## 9. The PWA shell

`wwwroot/`: `index.html` (no inline script or style — the CSP forbids it), `app.js`, `styles.css`,
`manifest.webmanifest` (name *P&C Platform*, `start_url` and `scope` `/`, `display: standalone`),
`icon.svg`, `sw.js`. The service worker caches the shell files under a versioned cache key and
**bypasses** non-GET, cross-origin, `/api/*` and `/health`, falling back to cache then
`index.html` offline. The one page shows `/health`, `/me` and the catalogue — a person can see who
they are and what exists. Agrees with the predecessor's shell; the React tier is not carried and
its return is a later ruling.

---

## 10. Project layout

```
src/PnC.sln
src/PnC.Api/            Program.cs · Data/{Catalog,SqlSession}.cs · Security/{PermissionMap,
                        AuthorizationService,RequestUserMiddleware}.cs · Endpoints/{Api,
                        Problems}.cs · api-permissions.json · appsettings.json · wwwroot/
src/PnC.Api.Smoke/      Program.cs
src/PnC.Formula/        (carried, W0)
src/PnC.Formula.Conformance/
```

`TreatWarningsAsErrors`, nullable on, `InvariantGlobalization` off (dates carry offsets and are
rendered for people).

---

## 11. Decisions this specification takes

Recorded in `DECISION-LOG.md` when W1 commits; listed here so they can be overturned early.

| Proposed | Decision | Agrees with |
|---|---|---|
| A | Thin handlers; rules only in procedures; a procedure's `THROW` is the API's 409 in the procedure's words | PnCPlatform §2.3 |
| B | Identity: Windows via IIS; user matched by UPN to one enabled `security.User`; directory presence grants nothing; attribution by session context, never an `ActorId` from the tier | §2.2, §4.2 |
| C | The catalogue is read from `sys.*` at start; `OBJECT_DEFINITION` parsed for defaults | predecessor `Catalog.cs` |
| D | The permission map is a JSON file in the release; explicit `null` and unmapped hand-written procedures are not callable; **V2: validated against the catalogue at start** | predecessor `PermissionMap.cs` |
| E | One `fHasPermission` call decides; refusals logged before 403 | §2.4 |
| F | **V2:** read logging driven by `config.ReadLoggedClass` through `audit.LogRead`, not a C# constant | FR-6.4 |
| G | The DEV header needs Development mode **and** the DEV environment name; anything else is a hard failure | predecessor `RequestUserMiddleware` |
| H | One package; CSP with no inline anything; `no-store` on `/api` | PnCPlatform #239, §2.5 |
| I | W1's UI is the hand-written shell only; the UI framework is a W5/W6 ruling | — |

---

## 12. Open questions

- **Where does W1's gate run?** VGS-VM02 currently hosts the predecessor's release against
  `PnCPlatform_QA`, and the workflow assumes the QA VMs are rebuilt clean for W8. Installing the
  V2 API there in W1 means either a second IIS site or replacing the predecessor's. Until ruled,
  W1 verifies the surface on the build laptop (Kestrel, Development mode, `PnCPlatform_V2_DEV`)
  and the Windows-mode run from VGS-VM07 is recorded as **not yet done**.
- **Windows-mode name matching.** Whether the Negotiate identity presents the UPN or
  `DOMAIN\sam` on the OT domain has not been verified this session; W1 matches on UPN and falls
  back to `DOMAIN\sam` against the same column, and W2 settles it with the SID alternate key.
- **`svc-pncapi` on `PnCPlatform_V2_DEV`.** The service account has `app_execute` on `_QA` only.
  Granting it on `_V2_DEV` is environment configuration, done when the gate location is ruled.
