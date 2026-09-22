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
enabled `security.User` by `UserPrincipalName`. IIS presents the name as `DOMAIN\sam`; the user
rows hold the UPN (the predecessor's QA rows read `VGS01@vgsot.internal`, verified 2026-09-11), so
`Auth:UpnSuffix` (`vgsot.internal`) turns `VGSOT\VGS01` into `VGS01@vgsot.internal` before the
lookup — **unverified against IIS this session**; the W1 card carries it. A domain account with no
`security.User` row is refused with 401: **presence in the directory grants nothing** (agrees with
§4.2). W2 adds the directory SID as an alternate key so a renamed account keeps its history.

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

**W2 (IDENTITY.md §5).** A list read of a view with a subject column is gated by `security.fHoldsPermission`
(held in any scope) and its rows filtered by `security.fReadableSubjects`; a write's subject comes from the
map's typed `subjectKeys`. A view with no subject column keeps the class decision.

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

**Paging of the read models (W7, decision #145).** `Api:MaterialiseBeforePaging` lists views the dispatcher reads whole
with a plain `SELECT` (the optimizer's parallel plan) and orders and pages in memory — the parity screens' five views —
because `ORDER BY … OFFSET`, `TOP` or `SELECT INTO` over them cost 10–120 s on the migrated estate where the plain read
costs 1–6 s. `Api:MaxTake` is 10 000 so such a screen reads its list in one call; ordering follows SQL's (nulls first,
numbers and instants by value, text ordinal-ignore-case, `RowSeq` the tiebreaker).

**W8 (decision #154).** A view in `Api:MaterialiseBeforePaging` is read with its scope only; the query string's equality
filters are applied to the materialised rows in memory (a state predicate pushed into SQL measured 42–54 s on QA against
0.6–1.7 s for the whole view).

**W8 (decision #150).** `GET /api/v1/me` also returns `actorId` — the session's own actor as `personnel.ResolveActor`
resolves it from the session context — so a page can name who granted a grant (`security.Grant_Add @GrantedByActorId`)
without inventing an id. The grants screen (`/grants.html`) reads `security/vUser`, `personnel/vPerson`, `security/vRole`,
`security/vGrant` and writes through `security/Grant_Add` and `security/Grant_Revise` (a revoke keeps the row).

**Two rules from the W7 smoke over the real estate.** The engine's instants (guard evaluation, step commits, the sweep)
are the database's `SYSDATETIMEOFFSET()`, read through `SqlSession.NowAsync` — never the host's clock (decision #146). A
scoped list read (joined to `security.fReadableSubjects`) carries `OPTION (RECOMPILE)` so a plan cached for one grant's
readable set never serves another's (#147).

**And one from the estate at 7 909 placements (#222).** The readable set is built in a statement of its own — inserted into a
table variable keyed on its single column — and the view is joined to *that*, not to the function inline. `fReadableSubjects` is
an inline function, so within one statement the read's own filter can be pushed into its body; when that filter names the very
column the scope joins on (`asset/vPlacement?AssetEntityId=…`), it was, and the function's plan changed from seeking the grant's
own subtree to expanding every node in the estate — 87.3 s of an 87.5 s query in one Filter, an "Execution Timeout Expired" 500
over HTTP. The set is identical either way; only where it is evaluated changed. **That statement carries no hint**: almost all of
`fReadableSubjects` is compile time (387 ms compiling, 7 ms running, measured), so an `OPTION (RECOMPILE)` on it would pay that
compile a second time and cost every scoped read about 0.3 s. The read below it keeps its `RECOMPILE` (#147).

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

## 8a. The definitions endpoints — W3

Three fixed routes, mapped before the generic dispatcher (`src/PnC.Api/Endpoints/DefinitionEndpoints.cs`; decision #100):

| Route | Does | Permission |
|---|---|---|
| `POST /api/v1/definitions/documents` `{document, changeNote?}` | validates the authored document against `Schemas/procedure.schema.json` or `workflow.schema.json` (`SchemaCheck`, the subset the two schemas use), parses and type-checks every expression against `compliance.vFactCatalogue` plus the document's own declared names (`DocumentCompiler`), replaces text with canonical AST, calls `process.AddProcedureVersion` / `AddWorkflowVersion` → `{versionRowId, versionNumber, existing}`; **400 `document_invalid`** with `errors[{path, code, message}]`; the database's structural rules answer 409 in the rule's words | `Definition.Modify` |
| `POST /api/v1/definitions/documents/{versionRowId}/approve` `{effectiveFrom?, overrideReason?, overrideApprovedByActorId?}` | `process.ApproveProcedureVersion` (approval + projection, one transaction) or `config.ApproveDefinitionVersion` for a workflow → `{approved, projectedSteps}` | `Definition.Approve` |
| `POST /api/v1/formula/check` `{expression, subjectKind?, env?}` | one expression parsed and typed → `{ok, type, facts, canonical}` or `{ok:false, code, message, position}` — the live check of PROCEDURE-ENGINE §8, W5's editor reuses it | any signed-in user |
| `POST /api/v1/definitions/documents?dryRun=true` `{document}` (W5, #120) | the same compile, then the database's structural rules (`ValidateProcedureDocument` / `ValidateWorkflowDocument`), **nothing stored** → `{ok, kind, key, canonical, canonicalLength}`; 400 `document_invalid` with `errors[{path, code, message}]` — a rule as code `rule 5012x` in its own words at path `$` | any signed-in user |
| `GET /api/v1/definitions/documents/{versionRowId}` (W5, #120) | one stored version → `{kind, key, name, versionNumber, status, effectiveFrom, effectiveTo, approvedAt, changeNote, document, canonical}` — `document` is the payload with every expression site **printed back as grammar text** (`DocumentCompiler.Decompile`, `Printer`); `canonical` the stored text | `Definition.Read` |

`PnC.Api.Smoke` extends the W2 run with the W3 section (the three example documents, the approval by a second
person, the projection counts, the refusals) — 73 checks in DEV mode (161 with W4 and W5, 2026-09-12); in Windows mode the Administrator run authors a
fresh `W3_GATE_APPROVAL` Draft and the Approver run (`--windows=Approver`) approves it.

## 8b. The procedure engine's endpoints — W4

`src/PnC.Api/Endpoints/ProcessEndpoints.cs` (decisions #106, #114, #115). Every write is a `process.*` procedure;
permissions are the map's for that procedure, decided on the work request the run belongs to.

| Route | Does | Permission |
|---|---|---|
| `POST process/workflows/start` `{workflowKey, subjectKind, subjectEntityId, inputs?}` | `process.StartWorkflow`; the started run is advanced | `WorkRequest.Modify` |
| `POST process/workflow-instances/{id}/transitions` `{name, reason?, overrideReason?}` | when-guards evaluated over the subject, then `process.Transition`; a started run is advanced | `WorkRequest.Modify` |
| `GET process/procedure-instances/{id}` | the tree (`vProcedureInstanceTree`) with titles, ready steps and derived due dates (#44) | `WorkRequest.Read` |
| `POST process/procedure-instances/{id}/evaluate` | re-evaluate and advance now (§4.1) | `WorkRequest.Modify` |
| `GET process/step-instances/{id}/draft` | the draft; a read by anyone but the claimant is logged (#68) | `WorkRequest.Read` |
| `POST process/step-instances/{id}/claim` · `release` · `takeover {reason}` · `draft {draft}` · `witness` | the claim (#55) and the attestation (#114) | `Record.Modify` |
| `POST process/step-instances/{id}/commit` `{outcome, capture?, evidence?[{name, mimeType, kind, contentBase64}], overrideReason?}` | validation and competency evaluated here, then `process.CommitStep`; the declared `advances` fired; a branch outcome ends its scope; the run advanced | `Record.Modify` |
| `POST process/step-instances/{id}/checkin` `{capturedBy, capturedAt, …}` | the deferred commit (#115) | `Record.Modify` |
| `POST process/block-instances/{id}/release-hold` `{reason}` | a person releases a hold | `WorkRequest.Modify` |
| `POST process/sweep` | the sweep now | `Grant.Administer` |

`PnC.Api.Smoke`'s W4 section runs the whole fixture (139 checks in DEV mode, 2026-09-12); it needs four identities in one
process and is skipped in Windows mode.

## 8c. The file download — W7

`src/PnC.Api/Endpoints/FileEndpoints.cs` (decision #144; the W6 card's item F, #136). The one route that returns bytes:

| Route | Does | Permission |
|---|---|---|
| `GET /api/v1/files/{fileRowId}` | the file row and its revision's document; the bytes from `document.FileStore` by the file's stream id; the row's SHA-256 compared before anything is sent (500 `integrity` on mismatch); `RedactionStatus` other than None → 403 `redacted`; an archive-tier file (no stream id) → 404 `not_here`; **the open is a logged read** (`audit.LogRead` on `document.File`, in `config.ReadLoggedClass`); answered as an attachment with the stored name and MIME type, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff` | `Document.Read` on the file's document (decided by the database) |

| `POST /api/v1/files/{fileRowId}/link` | #218: a short-lived link to this one file for a desktop application — `{ url, absoluteUrl, expiresAt, fileName, mimeType, officeUrl }`; `url` is `/api/v1/files/{id}/link/{token}/{file name}` (the token and the name in the path: Word requests nothing for a URL without a document extension and drops a query string); `officeUrl` is `ms-word:ofv|u|<absoluteUrl>` for a Word document (`ms-excel` for a workbook), null otherwise; the token names the file, the user and an expiry (`Files:LinkSeconds`, default 90) signed with `Files:LinkKey` (ignored config; a random key per process when absent) | `Document.Read` on the file's document, decided now |
| `GET`/`HEAD /api/v1/files/{fileRowId}/link/{token}/{name}` | the same bytes as the file route, the identity being the token's user (`RequestUserMiddleware`, `FileLinkTokens`) — for that file only; another file, an altered or expired token → 401 `link_invalid`; the read is authorised and logged to that user as any other. `OPTIONS` under `/api/v1/files` answers 204 with `Allow` and no identity (Word probes the link's folder before it fetches; a 401 there ends the open) | as the file route |

The setting display (§9) links every file name to it; the record's Files and records (#218) opens a Word document in Word through the link, a PDF or a text in its own tab, and saves anything else.

`src/PnC.Api/Endpoints/RationaleEndpoints.cs` (#219). The structured rationale, one section per protective element (`RationaleEngine`):

| Route | Does | Permission |
|---|---|---|
| `GET /api/v1/rationale/{settingsRevisionRowId}[?line=<assetEntityId>]` | the model's Effective `Program.Rationale` template (its inputs by section with defaults, its sections), the element map of the relay's `Program.RelayWord` (elements, groups), the line (the scheme's, the stored pick, or `line=`) with the plant facts resolved from the line asset (`LINE_Template` characteristics, the remote terminal's station, the voltage) and the facts missing by name, the position's commissioned functions, the stored inputs, the rationale revision, its files and last result (`rationale.json`) | `ConfigurationFile.Read` on the device |
| `POST /api/v1/rationale/{settingsRevisionRowId}/apply` `{ inputs: {key: value…, FaultStudy: [[…]]}, lineAssetEntityId? }` | an outstanding (Draft) revision only (409 `not_outstanding`): the sections evaluated in map order (grammar-1 formulas over `line.*`, `device.*`, `input.*`, `value.*`, `setting.*`), every owned setting written through `process.SetParsedSetting`, the inputs stored on the Draft rationale revision (`document.CreateRationale`, `document.SetRationaleValue`), MTU/MRI/MTO derived from the elements' marks in the Relay Word's bit order, `rationale.json` and `rationale.docx` (the platform's own WordprocessingML writer, `Documents/DocxWriter.cs`) filed on the rationale revision (the previous pair soft-deleted), `audit.LogAction` rationale-applied; answers the result (sections with statements and values, masks, settings written, range checks, unknowns) | `ConfigurationFile.Modify` on the device |

## 8d. Screens from definitions — W8 (2026-09-15, decisions #165, #167)

- `GET /api/v1/screens` — the Effective `Program.Screen` definitions the person may open (each screen's `permission` is checked
  against the codes `/me` lists; no `Definition.Read` needed): `{ screens: [{ key, name, description, versionRowId, versionNumber,
  menu, permission, screenKind, params }] }`. The React shell builds its navigation from this and routes `/app/s/<key>[/<id>]` to
  the screen kind the definition names (`settingsBook`, `list`, `workItem`, `step`, `record`; schema `docs/design/screen.schema.json`).
- `GET /api/v1/process/step-instances/{id}` — one read for the generic step screen: the step's live state and claim
  (`state, outcome, assignedRoleCode, claimedByActorId, claimedByDisplayName, claimExpiresAt, isClaimant, witnessedBy…, committedAt`),
  its `draft`, its member, its due date, and `definition` — the step node lifted from the pinned procedure document (`title,
  instruction, role, roleCode, capture, outcomes, evidence, signoff, deviation, due, record, produces, advances`). Authorised as
  the draft read (`WorkRequest.Read` on the run's request); a read by anyone but the claimant is logged (#68).
- `POST /api/v1/definitions/documents` accepts `document.kind` = `procedure`, `workflow` or `screen`; the kinds are a table in
  `DefinitionEndpoints.cs` (schema file, definition kind, add/approve procedures, whether expressions compile). A screen document
  compiles nothing: the schema is the whole check and the stored form is the document.

## 8e. The settings template's writer and the edit — W8 (2026-09-16, decision #168)

- `GET /api/v1/settings/{revisionRowId}/rendered` — the revision's parsed settings written as the model's settings text
  (`process.RenderSettingsText`: the template's SET order, `CODE=value` joined by `, `, the logic masks after `LOGIC SETTINGS: `),
  `text/plain`, `Content-Disposition: inline` with the filed file's name. `ConfigurationFile.Read` on the revision's device. For a
  legacy text it is the values as read (order and aliases canonical); for a platform-written file it is the file, byte for byte.
- `POST /api/v1/process/SetParsedSetting` `{ ConfigurationFileRevisionRowId, DeviceEntityId, SettingCode, RawValue }` — one value of an
  outstanding revision, through the dispatcher (`ConfigurationFile.Modify` on `DeviceEntityId`, which must be the revision's device).
  Refused with the procedure's message when the revision is not a draft (50183), the template does not know the code (50182), or the
  value is not a number / whole number / on the closed list (50184). An empty `RawValue` unsets the setting. Returns
  `RangeCheck` / `RangeCheckNote` as the procedure's outputs.
- The file the platform writes is filed by the engine at the settings step (`process.IssueRenderedSettings`, PROCEDURE-ENGINE §5.1
  #168 note); `IssueRenderedSettings`, `RefileRevision` and `CopyRevisionAsDraft` are engine procedures, not callable over HTTP.

## 8f. Primary assets and applicability classifications — W8 (2026-09-16, decision #170)

- `GET /api/v1/asset/vPrimaryAsset?…` — the non-device assets of the Primary class with their station (through their placement) and
  their current classifications summarised (`Classifications`: `Kind=Value; …`). `Asset.Read`.
- `POST /api/v1/asset/RecordClassification` `{ SubjectKind, SubjectEntityId, ClassificationKindCode, ClassificationValue, DeterminedAt?,
  ReferenceDocumentRevisionRowId? }` — one current value per subject and kind, `Basis = Recorded`, the caller as the determiner; an empty
  value withdraws; the history keeps every prior value (`vClassificationHistory`). `Asset.Modify` (Node/Scheme by SubjectKind) on the subject;
  an unknown kind is refused (50231). The kinds: BesStatus, CipImpactRating, NpccBulkPowerSystem, NpccA10, Prc023 — values in the standards'
  own words, chosen on the screen.
- The scheme's "protects" link is the generated `scheme.SchemeProtects_Add` / `_SoftDelete` (`Scheme.Modify` on `SchemeEntityId`); a primary
  asset is created with `asset.Asset_Add` (type Line, Transformer, Bus, Breaker, Generator, Capacitor, Reactor, System) and placed at its
  station with `asset.PlaceAsset`.

## 8g. Compliance — the obligation-rule evaluator, ratings, device and station classifications — W8 (2026-09-16, decision #171)

- `POST /api/v1/compliance/evaluate` `{ subjectKind?, subjectEntityId?, mode: "Preview" | "Effective" }` — every effective
  `Program.ObligationRule` evaluated (PnC.Formula over `compliance.fFactRead`; `asset.formula.<key>` names resolved by evaluating the
  effective `Program.Formula` definitions) for the one subject given, else for the candidates (`compliance.vRuleCandidateDevice`:
  devices that carry a classification or whose scheme protects a classified asset). **Preview** writes nothing and returns the
  verdicts with every fact read (name, parameters, value as read) — the compliance panel's "Evaluate now"; `Obligation.Read`.
  **Effective** opens an `ObligationInstance` (Status Open, the period from the rule's cadence) when the scope is true and none is
  open, closes one (NotApplicable) when it is false, leaves it when Unknown and says so; the facts read become the instance's
  `ObligationInstanceFact` rows; one `RuleEvaluationRun` per rule; `Obligation.Modify`. The same pass runs on a timer
  (`Engine:ComplianceMinutes`, default 60, 0 disables) as the platform's System actor.
  Response: `{ at, mode, rules, subjects, opened, closed, unchanged, unknown, errors, verdicts: [{ ruleKey, ruleName, requirementNumber,
  standardCode, standardVersion, subjectEntityId, result: true|false|unknown|error, error?, unknowns[], reads: [{ name, params, value }],
  instanceRowId?, action: open|close|unchanged|none, evidenceNote }], ruleErrors[], runId }`.
- `asset.AssetRating_Add / _Revise / _SoftDelete` (`Asset.Modify` on `AssetEntityId`) and `GET asset/vAssetRating` — a primary asset's
  ratings in amperes by kind (Continuous, FourHour, FifteenMinute, PracticalLimitation) and season, with the source; entered by hand
  until the ratings connector in the DMZ supplies them (`SourceSystem` names the writer).
- `asset.RecordClassification` now also takes `SubjectKind = Asset` for a **device** (kinds BesCyberAsset, ExternalRoutableConnectivity)
  and `SubjectKind = Node` for a **station** (CipImpactRating); `ref.ClassificationKind.SubjectKinds` says which subjects a kind applies
  to, and `compliance.vFactCatalogue` publishes `device.classification.<Kind>`, `device.station.classification.<Kind>`,
  `device.protects.classification.<Kind>`, `device.protects.bus.classification.<Kind>`, `device.protects.terminal.voltage`,
  `device.protects.name`, `device.protects.rating[kind]` for the rules to read.
- Seeds: `Seed_compliance_Standards_NB.sql` (the standards and requirements in force in NB, quoted), `Seed_config_Formulas_PRC023.sql`
  and `Seed_config_ObligationRules.sql` (generated by `tools/compliance_rules.py` through `tools/FormulaCompile`, the platform's own
  parser: each definition carries the text a person reads and the canonical AST the evaluator runs).

## 9. The PWA shell

**The definitions screen (W5, 2026-09-12; decisions #119, #120, #122).** `/definitions.html` + `definitions.js`, with
`pnc.js` holding what every page shares (the DEV act-as header, the JSON calls). Left: the `Program.Procedure` and
`Program.Workflow` definitions (`config/vDefinition`) with their versions (`config/vDefinitionVersion`: number,
status, approval date; the change note as the tooltip). Right: the document as JSON in a textarea — loaded through
`GET definitions/documents/{versionRowId}` so expressions read as text; **checked 0.7 s after every edit** through
`POST definitions/documents?dryRun=true`, every problem listed with its JSON path and a button that puts the caret on
that line (a small scanner over the text, no reformatting); *Save draft* (`POST definitions/documents` with the change
note; the answer names the version, or says the content is already stored); *Approve* (`…/approve`; the segregation
refusal shown in the rule's words; projected steps on success). *New procedure* starts from a one-step skeleton.
Save and Approve are disabled, with the reason, when `/me`'s permission codes lack `Definition.Modify` /
`Definition.Approve`. Below: the expression bench (`/formula/check` with a subject kind and a `value` type) and the
runs awaiting a version ruling (`process/vMigrationList`). No inline script or style; the service worker's shell list
carries the new files (`shell-2`). Observed in Chrome 2026-09-12: `SETTINGS_CHANGE` v20 loaded, its description
edited, checked (no problems), saved as v21, the author's Approve refused 409 by `security.CheckSegregation`, approved
as the second Administrator → Effective, 15 steps projected; the bench typed `device.settings.SLOPE > 20 % and
device.technology = 'Electromechanical'` → `bool`, two facts; 28 runs on the migration list, every earlier gate run's
half-run instance among them, all still Running on their pinned versions.

**DEV sign-in (2026-09-12, after W3).** When `/health` reports environment `DEV` the shell shows an *act as* field;
the chosen name is kept in the browser's local storage and sent as `X-PnC-Dev-User` on every request, so the owner
can look at the built platform from the laptop at `http://127.0.0.1:5210/` while the Development host runs. In Windows
mode the field never appears (#85: the header is refused outside DEV). Observed in Chrome 2026-09-12: signed in as
the smoke Administrator, the catalogue lists 22 schemas, 537 procedures, 398 views.

**The parity screens (W6, 2026-09-12; decisions #127–#133).** Four pages over the W6 read models (STEPS.md step 18),
each one flat view per panel plus id-keyed detail calls; `pnc.js` gained `fetchAll` (a `skip` loop over the 500-row
pages), `table`, `qs`, `me` (with the permission codes) and the date formats.
- `settings.html` — the legacy main window: the state toggle (Active · Outstanding · Archived · Withdrawn) is
  `?GridState=` on `document/vSettingsRecord`; *Select columns* offers the view's columns from `/api/v1/catalog` and keeps
  the choice in this browser (the legacy columns by default); *Print* prints the grid as filtered and chosen with a header;
  *Set verified date* on a row whose return-to-service step is Ready (claim → witness from a second session → commit or
  check-in); *Request change* on an Active row (`work/WorkRequest_Add` scoped to the device → `process/workflows/start` →
  transition *Start*). `?DeviceEntityId=` and `?WorkRequestEntityId=` narrow it from the other screens.
- `request.html?id=` — the change-request window over `work/vChangeRequestStatus`: header, the two completion tracks
  (status, date, the drawing link, revision and revised date), the software track *not modelled*, the devices in the
  change (the grid filtered), and *Start* / *Post / Close* / *Cancel request* (a reason required) as workflow transitions.
- `setting.html?revision=` — the setting display in the legacy's five groups from the settings record, the parsed
  settings (`document/vParsedSettingNamed`), the revision's files and the run's evidence records (`record/vRecord` →
  `document/vRevisionLink` → `document/vFile`, metadata only — no download endpoint exists); *not modelled* where the
  platform has no counterpart.
- `floc.html` — the Location / Protected Asset / Protection Function view: a lazy tree over `location/vNodeTree`
  (arrows only where `HasChildren`), the positions grid over `location/vFloc`, browse by station or panel (a click in the
  tree), by scheme (`location/vFlocScheme`) or by model; *New setting* raises a request on the position.
`sw.js` shell list carries the eight files (`shell-3`). Observed in Chrome 2026-09-12 on DEV: the grid's Active toggle
(18 rows, 449 ms cold), the request window with both tracks Complete and the drawing link, the setting display with four
parsed BDD15B settings, the locations grid with 33 positions; no console errors under the CSP.

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
                        Problems,Definition,Process}.cs · Definitions/ · Engine/ · api-permissions.json ·
                        appsettings.json · wwwroot/{index.html,app.js,definitions.html,definitions.js,pnc.js,
                        styles.css,sw.js}
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

## 12. Open questions — answered by the W1 card, 2026-09-11

- **Gate location:** a **second IIS site on VGS-VM02, port 8443**, against `PnCPlatform_V2_DEV`; the
  predecessor's site stays (D1, #89). `VGSOT\svc-pncapi` gets `app_execute` on `_V2_DEV` — a role grant
  the owner runs (the statements are in the workflow's W1 gate record).
- **Windows-mode name:** `Auth:UpnSuffix` accepted until W2 keys users by SID (D2).
- **Permission map defaults** accepted for W1, reviewed in W2 (D3). **Catalogue visible to every
  signed-in user** kept (D4). **SQL certificate trust** moves to W8's QA rebuild (D5).

The questions as they stood before the card:

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
