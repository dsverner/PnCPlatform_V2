# The parity walkthrough — draft for W8

Drafted in W6 (2026-09-12) for the reviewers' sign-off in W8 (`PHASE-1-WORKFLOW.md` W8 gate: *reviewers sign the
parity walkthrough*; FR-8.2: *reporting parity is the acceptance gate*). One section per row of
`docs/design/PROCEDURE-ENGINE.md` §10, each naming the screen, the fixture data to look at, what the reviewer should see,
and a line to sign. The fixture is a W4/W6 smoke run on the demonstration database (a station under Generation · Hydro
with three relays: an SEL-421, a CGE BDD15B and a Westinghouse CYL); after W7 the same rows exist for the migrated data.

Screens: **Settings** `/settings.html` · **Change request** `/request.html?id=` · **Setting display**
`/setting.html?revision=` · **Locations** `/floc.html` · **Definitions** `/definitions.html`.

| # | Legacy | Platform | Screen · what to look at | Expected | Reviewer · date |
|---|---|---|---|---|---|
| 1 | Grid state **Active** (`A`) | in service now (`InServiceFrom` set, `InServiceTo` null) | Settings · *Active* | the SEL-421 and BDD15B of the fixture change, verified date = the return-to-service instant; the CYL absent | |
| 2 | Grid state **Outstanding** (`M`) | a change in flight (the package's lifecycle non-terminal) | Settings · *Outstanding* | the second change on the SEL-421: lifecycle *Calculated*, no verified date; the same device also has an Active row | |
| 3 | Grid state **Archived** (`P`) | a later revision closed the in-service period, or the revision/package was superseded or withdrawn | Settings · *Archived*; *Withdrawn* for a device whose member left the change | after a second change on the SEL-421 goes in service, its first row moves to Archived; the CYL of the first change shows under Withdrawn | |
| 4 | Track status **Complete / NA / In progress** — documentation, database | the run's COMPLETION branches: Completed / NotApplicable / Running | Change request · *Completion tracks* | the closed fixture request: both tracks *Complete* with dates; the documentation track's *Go to document* link, revision label and revised date; the half-run request: *Not Started* | |
| 5 | Track status — **software** | not modelled (#58) | Change request · third card | the card says so and points at the request's notes, where the legacy rows land at migration | |
| 6 | Action type **Change / Add / Delete / Verify** | four `Program.WorkType` keys | Change request header · *Action type*; Settings · *Request change*; Locations · *New setting* | the type shown on the request; the four seeded keys offered in the action's dropdown | |
| 7 | **Set Verified Date** | `step.committed_at[id='RETURN_TO_SERVICE']` | Settings · a row whose return-to-service step is *Ready* · *Set verified date* | claim; a second person witnesses from their own session; commit (or check in a field-captured date) — the row's *Verified* fills once BASELINE commits | |
| 8 | **Request Change** / **Post-Close** / **Cancel** | *Start* / *Close* (guarded) / *Cancel* with a reason | Settings · *Request change*; Change request · *Post / Close*, *Cancel request* | a new request raised on the device and started; *Close* refused in the rule's words while the procedure runs; *Cancel* refused without a reason, done with one | |
| 9 | **Print** by state | the grid query, filtered | Settings · *Print* | the browser's print preview shows the grid as filtered and column-chosen, with a header naming the state, the row count, the time and the person | |
| 10 | **Grid by Location / Protected Asset / Protection Function** | the default view over the FLOC tree (#57) | Locations | the tree expands only where there is something beneath; a station shows its positions with panel, device, model, protection functions and schemes; browse by scheme and by model narrows the same grid | |

Also to be shown, from LEGACY-SYSTEM §8 and §9.1: the **column chooser** (Settings · *Select columns*; the legacy
columns as the default), the **setting display** (every legacy group, with *not modelled* where the platform has no
counterpart — CT/PT ratios, number of relays, the free-text overflow columns), and that **user administration** has no
parity screen (accounts are the directory's, roles are grants an Administrator sets — decision #130, pending the owner's
W6 card).

Sign-off: ____________________ (NB Power reviewer) · ____________________ (supplier) · date ________
