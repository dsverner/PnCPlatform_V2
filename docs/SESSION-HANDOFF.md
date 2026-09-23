# Session handoff — where the work stands

Written 2026-09-23, at the end of the session that built #217–#228. Read this first in the next session, then
`docs/decisions/DECISION-LOG.md` (rows #217–#228 carry every reason, measurement and owner quote) and
`docs/OPEN-QUESTIONS.md`. Replace this file at the end of each session; git keeps the earlier ones.

## Where things are

| | |
|---|---|
| Branch | `foundation/documentary-record`, clean, last commit `46a8421` (#228) |
| Remote | **none** — the repository exists only on this laptop (see "Before travelling") |
| DEV database | `PnCPlatform_V2_DEV` on VM01 `10.10.70.25`, deployed with everything to #228 |
| DEV API | `http://127.0.0.1:5210`, React app at `/app/` (run recipe in memory `project-dev-api-run-recipe`) |
| Last results | API smoke 407 PASS / 0 FAIL; schema smoke 269 PASS; wording check 0 |

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

## Waiting on the owner (rulings)

1. **The simple lifecycle lets an applied package be withdrawn.** `SETTINGS_LIFECYCLE_SIMPLE` has `Withdraw` from
   Applied, so under the four-step procedure a request can be cancelled after its settings are on the relay, and the record
   then says the old settings are in service. Recommendation: remove that transition from the definition.
2. (Answered, recorded) Finishing a request from the old program stays with P&C engineers (the workflow's Close role).

## Raised, not built — the next candidates, most important first

1. **A settings record can go in service with a file that no longer matches its settings.** Edits after the settings step
   wrote the file (a direct edit or a #192 re-base) are not written to the file. Measured: the smoke's record B reads
   SLOPE 39 % while its filed `settings.txt` says 35 %, and the next change, copied from the file, started from 35 %. The
   file is what is loaded to the relay. Recommendation: rewrite the file whenever the settings change after that step, and
   copy the in-service settings (not the file) into a new change. **Recommended as the next increment.**
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

## Before travelling (from the 2026-09-23 discussion)

- **Back the repository up off this laptop before leaving.** 160 commits, 32 MB of history, no remote anywhere.
- Every `10.10.x` host is reached through Tailscale already (subnet router `vgs-ct05`); away from home the same tunnel
  crosses the internet. Measured at home: 3 ms per database round trip. The chatty links are the API↔database and the
  tools↔database (the import makes ~47,000 calls; the smokes and deploys thousands), so the plan for working remotely is
  in the session's closing reply and in `docs/reference` once decided.
