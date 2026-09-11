# PnC.Api W1 — security analysis

**2026-09-11 · `src/PnC.Api` as committed at the end of W1.** Method: every surface the code
exposes was walked adversarially against `docs/design/API.md`, and each claim below was either
read in the source, read in the database code it depends on, or exercised against the running API
on the build laptop. Items marked **fixed** were changed this session and re-verified by the
rewritten smoke (19 checks) or a targeted probe; items marked **carried to W2** are recorded in the
workflow so they cannot be forgotten. Nothing here was inferred without reading it.

The built-in `/security-review` skill could not run: it diffs against `origin/HEAD` and this
repository has no remote yet.

## Findings

| # | Severity | Finding | Where | Outcome |
|---|---|---|---|---|
| 1 | **High** (Windows-auth deployments) | A cross-site page could submit a bodyless or form-encoded POST to a procedure endpoint; the browser attaches the Negotiate identity, and a procedure whose parameters all have defaults would execute as the victim. JSON bodies were parsed, but an empty body became `{}`. | `Endpoints/ApiEndpoints.cs` `ReadBody` | **Fixed.** POST now requires `Content-Type: application/json`; anything else is 415 `unsupported_media_type`. A cross-origin page cannot send that type without a CORS preflight, which the API never answers. Smoke check added (form POST → 415). |
| 2 | **Medium** | The host defaulted the environment name to `DEV` when `ASPNETCORE_ENVIRONMENT` was unset. The DEV-only identity header needs Development mode *and* the DEV name; with this default, one leaked local settings file on a server would have been enough. | `Program.cs` | **Fixed.** Default is `Production`; DEV must be said explicitly. Verified: started without the variable and with the local Development-mode file present, `/api/v1/me` with the header answers 500 `auth_mode`, never an identity. |
| 3 | **Medium** | Error responses lost the security headers: the problem writer called `Response.Clear()`, which discards headers set by the first middleware. Every 401/403/404/409/500 went out without CSP or `Cache-Control: no-store`. | `Endpoints/Problems.cs` | **Fixed.** No `Clear()`; verified the 401 carries CSP and `no-store`. |
| 4 | **Low** | Catalogue identifiers (schema, object, column names from `sys.*`) were bracket-quoted without doubling a `]` inside a name. Only a hostile schema could exploit it, and the schema is the platform's own, but the quoting was not correct. | `Data/SqlSession.cs` | **Fixed.** One `Q()` helper doubles `]` as `QUOTENAME` does; every identifier passes through it. Values never enter SQL text — every filter, parameter and paging value is a `SqlParameter` (verified by reading every `CommandText`). |
| 5 | **Low** | The asserted identity name (DEV header) was unbounded and reached the Event Log unsanitised — log injection with control characters. | `Security/RequestUserMiddleware.cs` | **Fixed.** Names over 200 characters or containing control characters are refused with 401 before lookup or logging. |
| 6 | **Verified, no change** | Session context and connection pooling: `sp_set_session_context … @read_only = 1` on a pooled connection would either leak one person's identity to the next request or fail to set the next one. | `Data/SqlSession.cs` | Probed: 10 rounds of Administrator → ReadOnly → unknown on the same pool, all 30 answers correct. The pool's connection reset clears session context. |
| 7 | **Verified, no change** | A client could omit the subject key from a write body so the permission is decided on the class alone. | `security.fHasPermission` line 38 | Read: a scoped (non-Global) grant with a null subject returns **0**. Fail-closed. |
| 8 | **Verified, no change** | `X-PnC-Delegation` names any GUID. | `personnel.ResolveActor` lines 53–66 | Read: the value only *selects among* delegations already in force to the user's own person; an arbitrary GUID selects nothing. `X-PnC-Sponsored-Person` may name any registered person — that is the database's held-versus-exercised design, and permissions are still decided against the acting user's own grants. |
| 9 | **Verified, no change** | `ActorId` / `MigrationRunId` from a client. | `Data/SqlSession.cs` | Never bound; a body carrying either is refused 400 (smoke check). Attribution is `personnel.ResolveActor`'s from session context. |
| 10 | **Carried to W2** | The subject *kind* passed to `fHasPermission` is the permission map's subject class (`WorkRequest`, `Definition`, `Grant`, …). For Global grants the kind is irrelevant (W1's only grants). For scoped grants the kind must be a `ref.SubjectKind` the function can place; several classes are not. | `Endpoints/ApiEndpoints.cs`, `api-permissions.json` | W2 (roles and scopes) must define subject resolution per procedure and view before any scoped grant exists. Until then no scoped grant is issued. |
| 11 | **Carried to W2** | `subjectKeys` is a fixed list; a procedure whose subject parameter has another name is decided without a subject. Fail-closed for scoped grants (finding 7), so no escalation, but scoped users would be refused work they should be able to do. | `api-permissions.json` | Same W2 item. |
| 12 | **Environment, recorded** | `TrustServerCertificate=true` in the shipped connection string accepts any certificate on the SQL link. The predecessor did the same against VM01's self-signed certificate. | `appsettings.json` | For QA and production: a trusted certificate on the SQL Server and `TrustServerCertificate=false`. Environment configuration, not code. |
| 13 | **Informational** | `/health` reports the release version and environment name to anonymous callers; `/api/v1/catalog` reports every procedure and view to any signed-in user, ReadOnly included. Both agree with the predecessor's design. | | Recorded; a later ruling may gate the catalogue behind a permission. |
| 14 | **Informational** | 409 `constraint` responses carry SQL Server's message, which names constraints and tables. Signed-in users only. | `Endpoints/Problems.cs` | Recorded. |

## What was not found

- No SQL text is built from client values anywhere (every `CommandText` read).
- No credential in the repository: the shipped connection string is integrated security; the local
  file is gitignored and excluded from publish (verified absent from `dist/0.1.0/app`).
- No inline script or style in the shell; CSP `default-src 'self'` on every response including
  errors (verified by header inspection).
- No hard delete anywhere: the smoke's own cleanup is `Person_SoftDelete`.
- The DEV header is never read in Windows mode (code path) and never honoured outside the DEV
  environment name (probed).
