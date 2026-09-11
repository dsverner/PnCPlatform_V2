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

Standing instruction, carried forward from `PnCPlatform` at the owner's request.

**Never end a turn with a list of questions or verification steps in the terminal.** Publish a
card and hand over the link — a **test card** (what to check on a screen) or a **decision card**
(open questions the work is blocked on).

- **One card per round**, with its own artifact URL, so an earlier round's answers stay readable.
- Every item states **what is being asked and why it matters**, in a sentence each.
- **Every item shows a concrete example of what is being asked** — the thing as it would actually
  look: a step as the technician sees it, a screen, a data row, a filename, a before and after.
  Never describe a mechanism in the abstract and ask for a ruling on it. Where two options are
  offered, show both as examples side by side. If an item cannot be illustrated, it is not yet a
  decision. Owner's instruction, 2026-09-11, after an abstract design card came back all-keep with
  no notes: *"An example showing what you are asking would be extremely helpful."*
- **Buttons for the discrete answers**, and a **free-text box on every item**, because the useful
  answer is often the one that fits no button.
- **Autosave on every keystroke and click** to the artifact's `db` capability under a stable
  document path. A half-finished round must survive a closed tab.
- **A submit button** recording `submittedAt`. Read the answers back with
  `Artifact action:"read_db"` and act on what the document says, not on what was expected.
- **Scope it explicitly** — an *out of scope* list and an *already known* list, so the owner is
  not made to report what is already logged. This exists because the owner asked for guard rails
  on himself.
- **Keep the terminal reply to the link and the headline.**

Note on the owner's answering style, observed across seven rounds: buttons get answered, free-text
boxes often do not. Prefer putting **propositions to accept, reject or amend** over asking for
narrative.

## Files over ~50 MB

GitHub hard-rejects any push containing a blob over 100 MB, anywhere in history. This bit the
predecessor repositories and left five branches unpushable. Keep large data out of git; if a large
artifact must be versioned, put it on `Z:` and reference it by path.

## Environment

The development and database environment — hosts, zones, the Tailscale path to `10.10.x`, and
where credentials live — is documented at
`C:\Projects\PnCPlatform\docs\reference\dev-environment.md`.

**Reference it by path. Never copy it here**: it describes where secrets are kept.
