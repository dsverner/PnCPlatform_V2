# Open questions

What is **not known**, stated plainly rather than filled in. Read this before assuming anything is
settled. When a question is resolved, it stays here with its answer and its source — the record of
what was once unknown is itself useful.

---

## Resolved

### OQ-1 — Who authors procedures besides the owner?
**Resolved 2026-09-11.** The owner now; P&C engineers in a later phase. The first authoring
surface is an expert editor; the model must admit a friendly authoring UI later without being
reshaped. → `DECISION-LOG.md` #28.

### OQ-2 — Does the existing front end permit authoring at all?
**Resolved 2026-09-11, by reading the code.** Yes. `src/PnC.Api/wwwroot/definitions.js` in the
predecessor edits a definition version's payload (`PUT /api/v1/definitions/versions/{id}/payload`)
and approves it (`POST …/approve`), with segregation of duties enforced — approval requires a
different person from the author, with distinct warn-and-log and block override paths.

The editor is a **raw JSON textarea**. So "no hard-coded procedures" is architecturally true in
the predecessor and practically false for anyone but its author. This is why OQ-1 mattered.

### OQ-4 — What does the legacy application actually hold?
**Resolved 2026-09-11, by measurement.** `dbRelayManagement_Legacy` and its C++Builder source were
examined in full. → `docs/review/LEGACY-SYSTEM.md`. Reporting parity is now specified against a
measured surface.

### OQ-5 — Is the existing 302-table schema kept, adapted, or replaced?
**Resolved 2026-09-11.** Carried forward, with the procedure layer (7 tables, 124 rows) designed
new. → `docs/review/SCHEMA-REVIEW.md`, `DECISION-LOG.md` #21–22.

### OQ-6 — What does the `D` prefix in `OLD_NO` mean?
**Resolved 2026-09-11.** A work request deleted before completion. 2 361 rows, dropped at cutover
with a counted, recorded reason. → `DECISION-LOG.md` #31.

---

## Open

### OQ-3 — The SOW and the proposal disagree on the order of phases 2–5

| Phase | SOW (governing) | Proposal |
|---|---|---|
| 2 | Settings & configuration automation, logic exports | Asset management, installed base, lifecycle |
| 3 | Asset management | System modelling, line modelling, mapping, ASPEN export |
| 4 | Compliance | Event warehouse, event viewing, fault location |
| 5 | Line constants and event analysis | Engineering analytics, model validation |

`docs/contract/sow-baseline.md` records this as unresolved and says the reconciliation is a
vision-document output. **It affects what "shape only" must cover first.** Not raised with the
owner yet.

### OQ-7 — The 17 revision-ordering violations and 2 malformed rows

In the legacy data, 17 device chains have an archived Change Request ID that exceeds the active
one, and 2 rows carry the prefix `2` instead of a state letter. Neither can be migrated by rule.
**A ruling is needed before the migration mapping is agreed with the client.** Not raised with the
owner yet. → `docs/migration/CUTOVER-STRATEGY.md` §5.

### OQ-8 — How to order the 617 pre-numbering rows

617 A/M/P rows carry a Change Request ID below 1000 — records that predate the numbering scheme.
Ordering within a chain relies on ascending CR; these break it. **A rule is needed.** Not raised
with the owner yet.

### OQ-9 — What the 1899-12-30 sentinel means

54 `CDATE` and 75 `VDATE` values are the VCL empty-date sentinel. Whether they mean "unknown" or
carry a specific historical meaning has not been asked.

### OQ-10 — What `IDATE` is

`SETTINGS` carries a third date column, `IDATE`, not yet characterised. The owner named `CDATE`
and `VDATE` as the two that matter; `IDATE` was not mentioned.

### OQ-11 — Is Phase 1 buildable in four weeks at $48 000 fixed?

The legacy functional surface is now measured and is **small**, which improves the odds. But
parity plus the procedure engine plus migration is, in my judgement, more than four weeks. A
subset is proposed in `REQUIREMENTS.md` §10. **It has not been agreed with the client.**

### OQ-12 — Data quality of the carried-forward subsystems

`PnCPlatform_DEV` holds 296 200 asset rows and 208 357 location rows. They were counted, not
assessed. Whether they are correct, complete or trustworthy is unknown, and the `migration` schema's
400 800 rows describe migrations already done whose provenance has not been reviewed.

### OQ-13 — `PnCPlatform_QA` versus `_DEV`

Only `_DEV` was read. The QA database may differ.

### OQ-14 — The facts the procedure engine publishes

`docs/design/PROCEDURE-ENGINE.md` §7 proposes fifteen facts (`step.*`, `procedure.*`, `input.*`,
`work.outage_*`, `package.*`, a `.performed_by` path on `record.last`). The catalogue today holds
45 facts, six of them under `record.*` / `person.*` / `work.*`. **Names and types are proposed,
not agreed.** The example's expressions are checked against the proposed set; if the names change,
the example changes with them.

### OQ-15 — Is a step's draft read-logged?

**Partly resolved 2026-09-11 by decision #55:** a draft is readable only by its claimant and the
responsible role, so the population that can read it is small and named. Whether those reads are
*logged* is still not asked. Decision #65 (PnCPlatform) logs reads of configuration files and
evidence packages; a draft is neither until it commits.

### OQ-19 — The typed settings for electromechanical and static relays

Decision #50 forks the build step so that a relay without a settings file records its settings as
typed values. The example uses **tap, time dial, instantaneous** as placeholders. The real set per
device type — and the `CharacteristicDefinition`s that govern them — has not been agreed. The owner
left the R1 free-text box empty, so the fallback stands: derive candidates from the legacy
`DESC1–4` and `REMARKS1–5` columns and put them to the owner as a card.

### OQ-16 — The predecessor's eight draft `Program.Workflow` definitions

All `Status=Draft`, never activated, migrated from a legacy template table. The design recommends
discarding them and authoring fresh — `examples/settings-lifecycle.workflow.json` already
supersedes `SETTINGS_APPROVAL`. Not ruled.

### OQ-17 — A hold past its maximum

`hold.maxDuration` makes a hold overdue and escalates it as a step would. Whether it should also
raise a compliance obligation — a hold is where outstanding compliance work goes quiet — has not
been asked.

### OQ-18 — `security.Role` codes for V2

The examples use `PCEngineer`, `PCApprover`, `PCTechnician`, `Administrator` as placeholders. The
SOW's seven account types have no agreed code mapping yet.

---

## Not questions — next deliverables

These are known work, not unknowns, listed so they are not mistaken for open questions.

- **The procedure engine — designed, not built.** `docs/design/PROCEDURE-ENGINE.md` awaits the
  owner's mark-up; implementation follows approval.
- **The `DRAWING_REVISION` procedure** — referenced by the settings-change example, not authored.
- **The Phase 1 subset agreement** with the client, following OQ-11.
- **Repository remotes** — `github` and `origin` on `Z:` — not yet configured.
