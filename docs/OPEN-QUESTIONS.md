# Open questions

What is **not known**, stated plainly rather than filled in. When a question is resolved, it stays
here with its answer and its source — the record of what was once unknown is itself useful.

**As of 2026-09-11, every question raised so far is resolved.** The owner closed the last eleven
on one card, with the actual legacy rows in front of him for the data rulings. Two remain as
*work items* rather than questions.

---

## Resolved

### OQ-1 — Who authors procedures besides the owner?
The owner now; P&C engineers in a later phase. → `DECISION-LOG.md` #28.

### OQ-2 — Does the existing front end permit authoring at all?
Yes, through a raw JSON textarea with segregation enforced on approval — read from
`definitions.js`. Moot after #64: the application is rewritten.

### OQ-3 — The SOW and the proposal disagree on the order of phases 2–5
**Decided with the client after Phase 1 acceptance.** Shape-only schema covers both orders
equally. → #65.

### OQ-4 — What does the legacy application actually hold?
Measured in full. → `docs/review/LEGACY-SYSTEM.md`.

### OQ-5 — Is the existing 302-table schema kept, adapted, or replaced?
Carried forward, with the procedure layer designed new. → #21–22. The *application* is not
carried. → #64.

### OQ-6 — What does the `D` prefix in `OLD_NO` mean?
A work request deleted before completion; dropped at cutover with a counted reason. → #31.

### OQ-7 — The 17 revision-ordering violations and 2 malformed rows
**The letter is trusted**: `A` stays active, `P` stays history; the 17 chains migrate as-is and
become the platform's first findings, for a person to rule on after cutover. **The 2 rows keyed
`2440`** — a model number typed into the key — are dropped with a counted reason. → #59, #60.

### OQ-8 — How to order the 617 pre-numbering rows
**No rule needed — closed by the data.** Change Request IDs below 1 000 sort first, which is
correct; 334 of the 617 are single-row chains. → #72.

### OQ-9 — What the 1899-12-30 sentinel means
**Unknown.** Migrates as no date; the platform shows *not recorded*. → #62.

### OQ-10 — What `IDATE` is
**Closed by the data:** NULL in all 14 211 rows. Dropped from the mapping. → #72.

### OQ-11 — Is Phase 1 buildable in four weeks at $48 000 fixed?
**No, and the owner has chosen to build it anyway.** The engine is built inside Phase 1; the
excess over the contracted hours is the owner's investment in phases 2–5; documentation packages
are delivered at acceptance. The owner will work more than forty hours a week for this phase,
unquantified. → #63, #71. Estimate: `docs/estimates/PHASE-1-ESTIMATE.md`.

### OQ-14 — The facts the procedure engine publishes
**Accepted as proposed.** The owner read three conditions as authored and found the style right.
→ #67.

### OQ-15 — Is a step's draft read-logged?
**Yes.** Reads of a draft are audit-logged like reads of evidence. → #68.

### OQ-16 — The predecessor's eight draft `Program.Workflow` definitions
**Discarded.** The two new workflow documents supersede them. → #70.

### OQ-17 — A hold past its maximum
**Raises an obligation**, so quiet compliance work is visible where compliance looks. → #69.

### OQ-18 — `security.Role` codes for the seven account types
**One engineer role, `PCEngineer`, with per-person scoped grants** (Transmission, Distribution,
Generation·Hydro, ·Belledune, ·Coleson); `PCTechnician`; `Administrator`; `PCApprover` as a
separate grant. Visibility is strictly per scope — read scope equals write scope (FR-6.2) — so a
Hydro engineer sees Hydro assets and nothing else, and a Transmission engineer sees exactly the
scopes granted. The owner's concern that each be "completely separate" is met by the grant, not
by separate roles. → #66.

### OQ-19 — The typed settings for electromechanical and static relays
**Superseded by a better ruling.** Every device's settings are held as **a file** — the vendor's
native file where one exists, a text file in name=value form where not — parsed against a
**per-device template** that says which settings the device has, and read through **one uniform
accessor** (`device.settings.<key>`; the owner's `X('wdg1') = 2.9`). The legacy `SET1` column is
the text format, and the seed for the templates. → #61.

---

## Work items — not questions

- **OQ-12 — data quality of the carried subsystems.** 296 200 asset rows and 208 357 location
  rows were counted, not assessed. A task for the bring-up.
- **OQ-13 — `PnCPlatform_QA` versus `_DEV`.** Only `_DEV` was read. A task for the bring-up.
- **The 17 flagged chains** (OQ-7) become findings on day one and need a person's ruling each.
- **Per-model settings templates** (OQ-19) are seeded by parsing every model's legacy `SET1`
  patterns; the owner corrects the ones that matter. A task, with a card.
- **The `DRAWING_REVISION` procedure** — referenced, not authored.
- **Repository remotes** — `github` and `origin` on `Z:` — not yet configured.
- **Start date** — not given.
- **The requirement page** (the owner, 2026-09-20, on the record's Standards list after #214: the list is "hardly
  adequate to provide the users with the necessary information to feel comfortable with the requirement… the user
  should be able to explore the details from the applicable standard requirement along with all the relevant system
  information required to meet the standard (this may be a combination of both user decisions and research on the
  standard). Again, this isn't really a phase 1 requirement, but I would like to take this forward"). A page (not a
  popup) opened from an obligation row: the requirement's text as quoted from the standard in force in NB, with the
  clause and the document named (compliance never from memory, #198); the rule's scope in words and the facts the
  platform read; the evidence the platform holds (records, work, files) and what it does not; NB Power's documented
  reading of the requirement (`compliance.Interpretation`, already in the schema) and the person's assertion for the
  period (`compliance.Assertion`, `EvidenceLink`, `EvidencePackage` — the "platform assembles, a person asserts"
  substrate of §12.6, built but without a screen). The research side — what the standard's parts require, part by
  part — is content to be read and seeded from the standard, never written from memory. Phase 2 candidate; the
  substrate is here, the screen is not.
- **Compare the relay's online settings with the in-service record** (the owner, 2026-09-22: a diff between two
  revisions of a device "is not very useful. Users can review the rational of each"; "the one area when a comparison of
  settings would be valuable would be to compare an 'online' version which would be downloaded from the device with what
  is in the database as the in-service setting. Basically a confirmation of what is in service is what you think is in
  service … a much later stage … that would require communications with field devices which hasn't even been planned
  yet"). The schema already takes a captured file (`document.File_Write @IsCapturedFromDevice`, `ConfigurationFile.CaptureKind`)
  and every filed text goes through the same reader, so the comparison is the in-service parsed settings against a
  captured revision's. Later phase; field communications first. The Compare tab was removed in #220.
- **A settings record goes in service with a file that no longer matches its settings** (found in #228, measured on DEV
  2026-09-22): an outstanding record whose settings are edited after its settings step wrote the file — a direct edit, or a
  re-base (#192) — goes in service with the old file. The smoke's `W4_20260923005330 B` reads SLOPE 39 % in its settings and
  `SLOPE=35 %` in its filed `settings.txt`; the next change on the relay, copied from the file, started from 35 %. The file is
  what is loaded to the relay (feedback-native-settings-round-trip), so this is the one that matters. Recommendation: the file
  is rewritten from the settings whenever they change after the settings step (or the edit reopens that step), and a new
  change copies the in-service settings rather than the file, as it already does for an outstanding basis. Not built.
  **Built 2026-09-23 as #230** (the owner: "Agreed"): every change to an outstanding record's settings rewrites its file, so a
  new change copied from the in-service file starts from the settings in service; the copy itself was left as it is (a
  legacy in-service record keeps its vendor bytes). A record whose file holds settings the template does not read is refused
  the edit (7 outstanding on DEV). **Raised by it, a ruling for the owner:** under the four-step procedure the settings can
  still change after they are applied to the relay (a #192 re-base at completion, after INSTALL); the record and its file then
  say something the relay does not hold. Recommendation: refuse edits once the package is Applied, and give a drift found
  after install a route back through re-applying. **Ruled 2026-09-23 ("a, refuse edits once applied") and built as #231** —
  instead of a route back, a change is not loaded while its basis is outstanding or has changed, so nothing drifts after loading.
- **A Block-mode segregation override is approved by being named** (found in #228): `security.CheckSegregation` lifts a
  Block rule when the caller names a different person as `OverrideApprovedByActorId`; nothing shows that person approved.
  Every seeded rule is WarnAndLog, so it is latent. Recommendation: the approval becomes the approver's own act (recorded in
  their own session) before any rule is switched to Block. Not built.
  **Built 2026-09-23 as #232** (the owner: the approver must be "someone who could do the action themselves", option A): the
  approver records the approval from their own session (`security.ApproveOverride`, `POST /api/v1/process/override-approvals`),
  single use, 24 h, withdrawable; a name in a request is refused. The approve control is on the step screen and (#233) on the
  definitions page ("Exception for the author…"). Record acceptance and work assignment have no screen at all yet, so their
  override approval is through the API until those screens are built.
- **The simple settings lifecycle lets an applied package be withdrawn** (#228): `SETTINGS_LIFECYCLE_SIMPLE` has
  `Withdraw` from Applied ("applied to the relay"), so a request under the four-step procedure can be cancelled after its
  settings are on the relay, and the record then says the old settings are in service. The full lifecycle has no such
  transition and the cancel is refused. A ruling for the owner: keep it (the technician puts the old settings back, unrecorded)
  or remove it from the definition (recommended), so the change must be finished or reversed by a new one.
  **Resolved 2026-09-23** — the owner: "yes remove it". Removed from the definition → `DECISION-LOG.md` #229.
- **The platform's "panel" is the old program's EQUIPMENT group, not the physical panel** (raised 2026-09-23, testing the
  settings book). Grouping by Scheme and by Equipment give the same groups: of 5,545 active records on DEV (smoke fixtures
  excluded), scheme name = panel name on 5,530, neither on 15, different on 0 — both were built from the legacy EQUIPMENT value
  (#158). The owner: a panel "should have values such as PNL12A, PNL34 etc."; the platform's panel nodes carry "2101 A-PROT"
  and the like. So a relay's physical place is known only down to the equipment group; the real panels — what cabling, DC feeds
  and panel drawings hang off in later phases — are not held. The owner's ruling: leave the book's two groupings as they are
  (removing Equipment would need remembering to restore it).
  **Resolved the same day** — the owner, shown that a panel is a location node with its own name, description and code:
  "I did not realize that panels were a first class citizen with name, description, code etc. That being the case, I don't see
  an issue at all! The way the client sets up their protections is on a panel level anyway. So, ultimately PNL34A could very well
  be L2103 A-PROT and at the present time the code field can be blank". So a panel's **Name** is the protection panel as the
  client names it (e.g. L2103 A-PROT — what the migration put there, correctly), and its **Code** is the physical panel
  identifier (e.g. PNL34A), blank until known; setting the code completes the FLOC beneath it (RenameNode rewrites the
  descendants). No change made. Still open, and not blocking: where the physical panel codes come from.
- **The engine stamps "now" from the machine it runs on, not from the database** (measured 2026-09-23 on VGS-PC02). The
  first schema smoke on PC02 was 268 PASS / 1 FAIL: "the engine moves the open exception to the new rule version and
  recomputes its clock (#23: 1, [])" (`docs/schema/ddl/tools/smoke.py:686`) — one exception moved, none visible. It is clock
  skew, not a logic fault: `ExceptionClocks.RederiveAsync` takes `at = asAt ?? DateTimeOffset.Now` and writes it as the
  revised row's `ValidFrom` (predecessor engine, `C:\Projects\PnCPlatform\src\PnC.Api\Services\ExceptionClocks.cs:30,82`);
  PC02 ran ~209 ms ahead of SQL Server on VM01, so the moved row became valid ~89 ms in the server's future and the check's
  read, at the server's now, did not see it. The same pattern is in V2's own reads: an as-of view is read at the API's
  `DateTimeOffset.Now` (`src/PnC.Api/Data/SqlSession.cs:131`), so a client behind the server can miss a row just written.
  PC02's time service is now automatic (time.windows.com) and it is still ~209 ms ahead of VM01, so VM01 (time from the OT
  domain controllers) may be the one adrift — UNVERIFIED, VM01's offset against an outside source not measured.
  Recommendation: the engine and the API take "now" from the database (`SYSDATETIMEOFFSET()`) for anything they write or
  read as-of, so one clock orders the record whatever machine the code runs on; separately, measure VM01's and the domain
  controllers' offset. Not built. **Built 2026-09-23 as #233** (the owner: "perform all fixes"): V2's as-of reads and the
  rationale apply take the database's time; the predecessor engine CLI the schema smoke runs defaults every verb to the
  database's time (branch `v2/engine-db-now` in `C:\Projects\PnCPlatform`, not merged there). Still open: VM01's and the domain
  controllers' offset against an outside source, unmeasured.
