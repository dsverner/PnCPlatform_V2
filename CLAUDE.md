# CLAUDE.md — PnCPlatform_V2

Guidance for Claude Code when working in this repository.

## What this is

The delivery repository for the NB Power Engineering Platform, contract VGS-PRJ-2026-001. Started
2026-09-11. See `README.md` for the platform's purpose and `docs/` for everything it rests on.

The **central requirement**, in the owner's words: *"We need to create a process engine that will
allow us to create/edit etc. all the various procedures that need to be followed in the group…
There can be no hard coded procedures."* Any design that puts a procedure in source code has
failed, regardless of how well it works.

## Hard rules — not up for renegotiation

These held across every predecessor and hold here.

- **Never fabricate.** This platform manages protection & control systems for electrical
  infrastructure. A wrong relay setting or protection-logic claim can cause misoperation,
  equipment damage, or injury. If something has not been read, queried or verified, say **"I don't
  know"**. Label a hypothesis explicitly as one. A fabricated finding is a lie regardless of intent.
- **No hard deletes.** Soft-delete only — `IsDeleted` / `IsActive`, `DeletedDate`, `DeletedBy`.
- **Full audit trails.** `CreatedBy` / `CreatedDate` / `ModifiedBy` / `ModifiedDate` on everything;
  audit log tables for actions. Every act is attributed to an **actor**, not to an account type,
  so contractors and departed staff stay attributable.
- **Granular access control.** Role and permission based, fine-grained. Read scope is as strict as
  write scope — the breadth of information held makes visibility itself a security concern.
- **Credentials never in source.** Externalise to ignored config. `.gitignore` already covers
  `connection.ini`, `server.ini`, `dev.local`, `.env`.

## Stack — decided, do not re-litigate

Microsoft SQL Server · a .NET API · a browser PWA. The same stack as `PnCPlatform`, chosen
deliberately by the owner on 2026-09-11.

**Phase 1 replaces the legacy application's functionality — not its structure or stack.** Do not
reproduce the legacy application's shape; reproduce what it does for the people who use it.

## Carry-forward policy

V2 draws on `C:\Projects\PnCPlatform` (release 0.10.5) and twelve archived predecessors indexed at
`Z:\Repos\INDEX.md`. The reviewed verdict is in `docs/review/SCHEMA-REVIEW.md`.

- **Carry forward is deliberate re-justification, never inheritance.** Importing a subsystem means
  reading it, deciding it is right for the stated requirements, and recording that decision in
  `docs/decisions/DECISION-LOG.md` with its reasoning.
- Where a V2 decision agrees with an existing PnCPlatform decision, **cite it**
  (`agrees with PnCPlatform #45`). Do not renumber, and do not assume it transfers untested.
- **The procedure and workflow layer is designed new.** It is the part that failed the review.
  Do not import `config.TestPlanStep`, `config.TestPlanReading`, `work.WorkflowInstance` or
  `work.WorkflowTransition` as a starting point.
- **Clone, don't browse the share.** `Z:` is an SMB mount measured at 154 small-file creates/sec
  against 1,137 on local disk. Never build or run from it.

## Comprehensibility is a requirement

The reason this repository exists is that the predecessor grew past what one person could hold in
their head (`NFR-3`). That makes the following binding, not stylistic:

- **`docs/reference/CARRY-FORWARD-MAP.md` is maintained, not written once.** Anything imported
  gets a line in it.
- A mechanism that cannot be explained in a paragraph is a defect.
- Prefer one convention applied widely over several applied locally. 37% of the predecessor's
  apparent size is a single repeated pattern; that is a feature, provided it is documented.

## Architectural weight versus interface speed

Two distinct budgets, and conflating them is a mistake.

Measured scale: under 10 concurrent users, 100–500 settings changes a year, 2k–10k devices. **No
reasonable architectural choice is excluded by throughput** — full temporal history and an
interpreted definition engine are affordable. Where structural clarity and machine efficiency
conflict, clarity wins and the reason is recorded.

That licence **does not extend to the interface.** Ordinary screens settle within a second, a
search within two, anything longer shows progress and stays usable. A technician waiting on a
screen is not consoled by an elegant schema.

## How to verify, and how to work

Carried forward from the predecessor, after a run of avoidable mistakes there.

- **Verify at the user's layer, not your own.** Before reporting a change as done, observe the
  state the user will actually see — the rendered screen, the running window. A file written, an
  HTTP 200, a config key set: none of these is the thing. Where that layer cannot be observed, say
  the change is **unverified** rather than done.
- **One mechanism per outcome.** Never start a second way of achieving something while the first
  is still in flight.
- **When the owner says something looks wrong, re-examine the whole artefact** they are looking
  at, not only the part just changed.
- **Work in small increments.** Build one thing, show the end state, then continue.
- **Re-check every figure against its source before writing it down.** One row count was wrong
  once in this project's history and was caught only by re-querying.

## How to ask the owner anything

**Ask here, in the terminal, as an ordinary conversation.** Owner's instruction, 2026-09-15: *"I think we have to throw
away the use of cards, that is causing more confusion than it is clearing up… lets stop using those… lets do it here,
as is the normal procedure."* Published cards (artifacts with buttons, autosave and a read-back) are retired; do not
publish one, and do not read old ones for new rulings.

- Ask only what the references cannot answer. The legacy program and Dev_Final are running on the build laptop; their
  screens and code are the specification for behaviour. Reproduce it; ask only where the two disagree or where the
  platform's rules forbid a copy (owner, 2026-09-15: *"I thought that you would be able to click through the other
  applications and with both the visuals and the code in each, be able to come up with something similar"*).
- When a ruling is needed, put the concrete example in the reply (a step as the technician sees it, a before and after)
  and state the options with a recommendation — one question at a time, answered here.
- Verification is the session's job (the checks it can make through the database, the guest agent and Chrome); the
  owner is asked to look only at a finished, working task, shown beside the reference doing the same task.
- The earlier rounds' answers (cards/w8-ux-round4 … round6) remain on record in `docs/decisions/DECISION-LOG.md`.

## Subagents run on Opus

Owner's instruction, 2026-09-16: every subagent spawned with the Agent tool is started with `model: "opus"` (a fork inherits the
parent model and ignores the override; everything else takes it). The reason is context use: the session's own context is the scarce
resource, and a search or review that runs elsewhere should run on the model that carries it best. No exceptions unless the owner
says so for a particular task.

## Files over ~50 MB

GitHub hard-rejects any push containing a blob over 100 MB, anywhere in history. This bit the
predecessor repositories and left five branches unpushable. Keep large data out of git; if a large
artifact must be versioned, put it on `Z:` and reference it by path.

## Environment

The development and database environment — hosts, zones, the Tailscale path to `10.10.x`, and
where credentials live — is documented at
`C:\Projects\PnCPlatform\docs\reference\dev-environment.md`.

**Reference it by path. Never copy it here**: it describes where secrets are kept.
