# PnCPlatform_V2

The **delivery repository** for the NB Power Engineering Platform — contract VGS-PRJ-2026-001,
Verner Grid Systems Inc. to New Brunswick Power.

Started 2026-09-11 as an empty repository. Nothing here is inherited wholesale.

## What this platform is

The P&C group's **engineering work environment**, whose distinguishing capability is that
**the procedures the group follows are authored in the application, not written in code** — the
settings-change process, the test procedures, the compliance routines. A change in group practice
is a new definition version, never a software release.

Phase 1 delivers the **Relay Settings Book**. It is the first procedure the engine runs. It is not
the product; it is the proof.

## Why V2 exists

`C:\Projects\PnCPlatform` reached release 0.10.5 with a working .NET API, a PWA, 302 database
tables and 258 design decisions. It was not abandoned for being wrong. It was set aside because
it had grown past the point where one person could hold it in their head, and because the
architecture needed to serve the five-phase end state rather than a Phase 1 outcome.

A measured review (`docs/review/SCHEMA-REVIEW.md`) found the diagnosis narrower than the decision
implied: of 302 tables and 1,183,063 rows, the part that fails the central requirement is
**7 tables and 124 rows** — the procedure and workflow layer.

So V2 **carries forward** the proven subsystems, deliberately and with fresh justification, and
**designs the procedure engine new**.

## Where to start reading

| Document | What it settles |
|---|---|
| `docs/requirements/REQUIREMENTS.md` | What the system must do — 32 requirements, each with its provenance |
| `docs/review/LEGACY-SYSTEM.md` | The application Phase 1 replaces, measured. **Defines reporting parity** — the contractual acceptance gate |
| `docs/review/SCHEMA-REVIEW.md` | The 302-table verdict: what survives, what does not, and why |
| `docs/reference/CARRY-FORWARD-MAP.md` | The subsystem map. Read this second — it is what makes the schema holdable |
| `docs/migration/CUTOVER-STRATEGY.md` | How legacy data arrives, and why not by watermark |
| `docs/decisions/DECISION-LOG.md` | Every decision taken here, numbered, with its reasoning |
| `docs/OPEN-QUESTIONS.md` | What is still unknown. Read before assuming anything is settled |
| `docs/interview/ROUNDS.md` | The owner's answers verbatim — the source most other documents cite |
| `docs/contract/sow-baseline.md` | What was actually agreed with the client |

## Stack

Microsoft SQL Server, a .NET API, and a browser PWA — the same stack as `PnCPlatform`, decided
deliberately rather than by default. Phase 1 replaces the legacy application's **functionality**,
not its structure or stack.

## Reference corpus

`PnCPlatform` and twelve archived predecessor repositories are consultable, indexed at
`Z:\Repos\INDEX.md`. Clone them; do not build from the share.

Rules for using them are in `CLAUDE.md`. The short version: **read before importing**. Lift a
specific idea, schema or algorithm deliberately and record why in the decision log. Never copy a
subsystem because it exists.

## Remotes

Not yet configured. When they are, by convention:

| Remote | Target | Purpose |
|---|---|---|
| `github` | `https://github.com/dsverner/PnCPlatform_V2.git` | source of record, offsite |
| `origin` | `Z:\Repos\PnCPlatform_V2.git` | LAN canonical, no size limits, works offline |

Push to both. The `Z:` share reports a foreign owner SID, so git needs an explicit exception per
repository — see `CLAUDE.md`.

## Status

**Documents only. No code has been written.** This commit establishes the record that the
requirements, the legacy baseline and the carry-forward decisions rest on, before anything is
built against them.
