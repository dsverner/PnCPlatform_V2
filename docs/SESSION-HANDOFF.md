# Session handoff — where the work stands

Written 2026-09-23, at the end of the session that built #217–#228. Read this first in the next session, then
`docs/decisions/DECISION-LOG.md` (rows #217–#228 carry every reason, measurement and owner quote) and
`docs/OPEN-QUESTIONS.md`. Replace this file at the end of each session; git keeps the earlier ones.

## Where things are

| | |
|---|---|
| Branch | `foundation/documentary-record`, clean, last commit `46a8421` (#228) |
| Remote | `origin` = `Z:\Repos\PnCPlatform_V2.git` (pushed 2026-09-23); no GitHub remote (the owner's call) |
| DEV database | `PnCPlatform_V2_DEV` on VM01 `10.10.70.25`, deployed with everything to #228 |
| DEV API | `http://127.0.0.1:5210`, React app at `/app/` (run recipe in memory `project-dev-api-run-recipe`) |
| Last results | API smoke 412 PASS / 0 FAIL (#231, PC02, 2026-09-23); schema smoke on PC02 after #231: 268 + the clock-skew FAIL; schema smoke 269 PASS on the laptop, 268 + 1 clock-skew FAIL on PC02 (below); wording check 0 |

## What this session built (one line each; the log row has the rest)

- **#217** Legacy Word rationale documents imported by a replayable rule, placed by number **and** station (a legacy number
  is reused after retirement).
- **#218** A Word document opens in Word from the record, through a short-lived signed link for that file and user.
- **#219** The runbook `docs/runbook/BRING-A-MODEL-IN.md`; the structured rationale — one section per protective element,
  the settings sheet grouped the same way, supervising settings explicit; the engineer enters inputs once and the platform
  makes the settings values, the settings file and the Word document.
- **#220** The record shows the relay's own History; a change is raised from the record; Files and records lists documents.
- **#221** The whole interface reworded as a P&C person speaks (`docs/design/UI-WORDING.md`, `tools/check_wording.py`).
- **#222** Scoped reads compute their readable set in a statement of their own (the 83 s placement read fixed).
- **#223** A change request offers only the actions that fit; smoke fixtures withdrawn; the Rationale tab follows the work.
- **#224** A record in service or archived is not "in" a change request.
- **#225** The settings file, in every form, on one tab; Files and records is the documents.
- **#226** Screen preferences: parts of a screen shown or hidden per person, defaulted per group, edited at every level;
  hiding is never blocking. Read-only accounts write nothing, their own view included (owner ruling).
- **#227** A change request brought over from the old program is shown and finished the old program's way: two tracks set
  by hand, Finish (refused while a track is in progress; a Delete Order archives the in-service settings with nothing in
  their place), Withdraw with a reason. 23,680 tracks filled by a replayable import rule.
- **#228** Cancelling a request cancels its work and withdraws its settings package (generic, read from the definitions'
  `cancellation` flag); refused once the settings are on the relay under the full lifecycle; older stuck runs repaired.

## Security fixes made this session (all measured on DEV before the fix)

- An OUTPUT `@EntityId` bound from the request body let one person write another's row — fixed in `config.SetViewItem`,
  `asset.SetAssetCharacteristic`, `document.SetRationaleValue`, `asset.DeriveClassification` (#226).
- Every signed-in person could read everyone's screen choices through the generated views (#226).
- `process.Transition`, `CommitStep`, `SaveDraft`, `ClaimStep`, `ReleaseHold`, `SetBlockState`, `StartWorkflow` were
  callable through the generic endpoint with the engine's own inputs: a technician cancelled a request needing the engineer
  role by naming an unrelated step; a step commit took `ValidationOk`/`CompetencyOk`/`CapturedByActorId` as given. Now
  refused there; the dedicated endpoints keep their codes under `"endpoints"` in `api-permissions.json` (#228).

## Owner rulings of 2026-09-23 — to act on first, on PC02

1. **Remove `Withdraw` from Applied in `SETTINGS_LIFECYCLE_SIMPLE`** ("yes remove it"). **Done as #229** (2026-09-23, PC02). The definition is
   `docs/design/examples/settings-lifecycle-simple.workflow.json`; it reaches DEV through the API smoke's
   `LoadApprove("settings-lifecycle-simple.workflow.json", "SETTINGS_LIFECYCLE_SIMPLE")` (`src/PnC.Api.Smoke/Program.cs:2300`) —
   check how LoadApprove versions and approves before relying on it. Runs already started keep their pinned version. After
   the change, a request under the four-step procedure is refused a cancel once its package is Applied (50178), as the full
   lifecycle already is. Log it as #229 with the ruling.
2. **Build the fix for the out-of-date settings file next** ("Agreed") — **done as #230** (2026-09-23, PC02); it raised a new
   ruling (below, "Raised, not built" item 1). Original note: Research
   was started and stopped for the move; redo it: every place the file is written (`IssueRenderedSettings`, `RefileRevision`,
   `WriteConfigurationRevision`, the rationale engine), every place rows change on an outstanding record
   (`SetParsedSetting`, `RebaseDraft`, the rationale apply), how `CopyRevisionAsDraft` copies the in-service revision (file
   bytes) versus an outstanding basis (rendered rows), and whether one primitive already renders rows to the file.
3. (Answered earlier, recorded) Finishing a request from the old program stays with P&C engineers.

## State at the move to PC02 (2026-09-23, morning)

- The laptop's DEV API is **stopped**; start it on PC02 (memory `project-dev-api-run-recipe`).
- The **schema smoke on PC02** (log `C:\pc02-setup\schema-smoke.log`) ended `SMOKE FAIL (1)`, 268 PASS: the one failure
  is "the engine moves the open exception … (#23: 1, [])", and it is **clock skew, not a logic fault** — the engine stamps
  the moved exception's `ValidFrom` with its own machine's clock (`ExceptionClocks.cs:30,82` in the predecessor), PC02 ran
  ~209 ms ahead of SQL Server, so the row was valid ~89 ms in the server's future when the check read it. Recorded with the
  recommendation (take "now" from the database, `SYSDATETIMEOFFSET()`) in `docs/OPEN-QUESTIONS.md`. Until that is built, a
  failure of that one check on PC02 is this; any other failure is not. The API smoke on PC02: 407 PASS.
- PC02 was on Wi-Fi by the owner's choice. It is an ASUS ROG Flow X13 laptop: its battery bridges short cuts; whether its
  firmware can power on after an outage is unconfirmed (F2 at start, Advanced Mode).
- **Z: credentials on PC02** were not confirmed saved: if `git push` from PC02 fails, open the Z: share once in the desktop
  session and save them.

## Raised, not built — the next candidates, most important first

1. ~~Settings can still change after they are applied to the relay~~ — **ruled ("a, refuse edits once applied") and built as
   #231** (2026-09-23): locked once loaded; a change is not loaded while its basis is outstanding or has changed.
2. **Block-mode segregation overrides are approved by being named** (`security.CheckSegregation`); latent while every rule
   is WarnAndLog. Make the approval the approver's own act before any rule is switched to Block.
3. Carried from earlier (see `docs/OPEN-QUESTIONS.md`): the settings book's chosen columns and the menu's open groups stay
   per browser (#226, by decision); the client's complete legacy documents share (Z: holds stations E–W only); six station
   folders with no legacy location; compare the relay's online settings with the in-service record (later phase); the
   requirement page (later phase); one device per legacy number in the migration model; per-port configuration; phase units
   as child assets.

## How to work here — lessons this session paid for

- **Run the two smokes one at a time, never together.** The schema smoke takes ~30 min and runs best with the API stopped.
  A dropped connection (10054) mid-run is the network, not a failure — rerun it whole; it sweeps its own leftovers first.
- **Long jobs run detached** (`Start-Process powershell -File <script>` writing a `.done` marker), because the tool
  timeout is 10 minutes: deploy ~4–8 min, schema smoke ~30 min, full import ~10–17 min.
- **The web type check is `npm run build`** in `src/PnC.Web`; a bare `npx tsc --noEmit` at the root checks nothing.
- `tools/check_wording.py` must report 0 before any interface commit; screen text never names our views, procedures or
  permission codes (strip `schema.Procedure:` from a database refusal before showing it).
- Several source files use CRLF; edit them by normalising to LF and writing back with the original ending.
- Smoke variables collide across blocks — prefix a new block's names (`k228_…`).
- A new table needs generated procedures before a hand-written one that calls them can build: deploy the table, run
  `generate.py`, then add the hand-written procedure.
- `process.Transition` and the other engine procedures are **not** callable through the generic endpoint any more; call
  the dedicated `/api/v1/process/...` endpoints.
- Never change a real legacy request or record on DEV to demonstrate something; build a `W4_…` fixture and record it in
  `docs/schema/migration/DEV-ONLY-MUTATIONS.json`.

## The development workstation for the trip (set up 2026-09-23)

The laptop reaches every `10.10.x` host through Tailscale (`vgs-ct05`), so away from home the database would sit an internet
round trip from the API and the tools (the import alone makes ~47,000 calls; 3 ms each at home, measured). The owner chose to
develop on a machine next to the database and use the laptop only as a Remote Desktop screen.

| | |
|---|---|
| Workstation | **VGS-PC02** `10.10.40.69` (`vgs-pc02.home.arpa`), Windows 11 Pro 25H2, Ryzen 9 5980HS / 16 threads, 31 GB, 846 GB free, **on Wi-Fi** |
| Access from the laptop | SSH `vgs-pc02` (key `vernersys01_ed25519`, user `daren`, an administrator); Remote Desktop on with NLA, firewall limited to `10.10.40.0/24` and Tailscale `100.64.0.0/10` |
| Installed | Git 2.55, .NET SDK 10.0.401 + sqlpackage, Node 24.19, Python 3.14.7 (`pyodbc`, `pycdlib`), ODBC Driver 17, Chrome, Tailscale 1.102.4, Claude Code 2.1.280 |
| Repositories | `C:\Projects\PnCPlatform_V2` (this one; `origin` = `\\10.10.40.10\vernersys-share\Repos\PnCPlatform_V2.git`) and `C:\Projects\PnCPlatform` (the predecessor: its engine and `dev.local`), with their ignored settings and credential files copied |
| Claude Code | global `CLAUDE.md`, `settings.json` (standing permissions, hooks), status line, skills, `C:\ss\stage-clip.ps1`, and this project's 29 memory files copied |
| Verified | the API, the smoke tool, the engine, the web app and the database project build (70 s); the predecessor engine also built **Release** (the schema smoke runs it with `-c Release --no-build`); after `tag:business` was applied in Tailscale, SQL round trip median 2.92 ms (laptop 3.09 ms); API smoke 407 PASS on PC02 against its own API |
| Spare | **VGS-DEV01**, Proxmox VM 102 on the Business VLAN, Windows 11 Pro 25H2, no tools; stopped and off at boot; admin in the predecessor's `dev.local` (`DEV01_ADMIN_*`) |

**Still needed from the owner, before leaving:**
1. ~~Tailscale sign-in on PC02~~ **done 2026-09-23**, tagged `tag:business` (without the tag it saw no route to `10.10.0.0/16`) — PC02 cannot reach SQL Server without it (the
   `Business -> OT (MSSQL)` rule names `vgs-ct05` only; measured: `10.10.70.25:1433` does not answer from PC02).
2. **Claude Code sign-in** on PC02 and the **Claude extension** in Chrome there.
3. **The Z: credentials** saved once in an interactive session on PC02, so `git push` to `origin` works.
4. **A network cable** for PC02 if it can take one — a Wi-Fi drop at home cuts the remote session until someone is there.
5. **Power**: set it to come back on after a power cut (BIOS "restore on AC power loss"); sleep is already off on AC.
6. Windows activation on the spare VM, whenever it is used.

**After the Tailscale sign-in (the session does these):** the DEV API on PC02, the API smoke, the schema smoke, and a timed
database round trip from PC02.

## Before travelling (from the 2026-09-23 discussion)

- **Done 2026-09-23**: the repository has an `origin` on Z: (`Z:\Repos\PnCPlatform_V2.git`), all branches and tags pushed.
- Every `10.10.x` host is reached through Tailscale already (subnet router `vgs-ct05`); away from home the same tunnel
  crosses the internet. Measured at home: 3 ms per database round trip. The chatty links are the API↔database and the
  tools↔database (the import makes ~47,000 calls; the smokes and deploys thousands), so the plan for working remotely is
  in the session's closing reply and in `docs/reference` once decided.
