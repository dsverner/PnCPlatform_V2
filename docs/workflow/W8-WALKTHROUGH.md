# The parity walkthrough — draft for W8

Drafted in W6 (2026-09-12) for the reviewers' sign-off in W8 (`PHASE-1-WORKFLOW.md` W8 gate: *reviewers sign the
parity walkthrough*; FR-8.2: *reporting parity is the acceptance gate*). One section per row of
`docs/design/PROCEDURE-ENGINE.md` §10, each naming the screen, the fixture data to look at, what the reviewer should see,
and a line to sign. The fixture is a W4/W6 smoke run on the demonstration database (a station under Generation · Hydro
with three relays: an SEL-421, a CGE BDD15B and a Westinghouse CYL); after W7 the same rows exist for the migrated data.

Screens (2026-09-15, #165 — the React screens, from definitions): **Settings** `/app/s/SETTINGS_BOOK` · **Requests** `/app/s/REQUEST_QUEUE` · **Change request** `/app/s/WORK_ITEM/<id>` · **Step** `/app/s/STEP/<id>` · **Record**
`/app/s/SETTINGS_RECORD/<revision>` · **Location report** `/report.html?StationNodeEntityId=&GridState=` (0.9.0) · **Schemes** `/schemes.html` (0.9.0) ·
**Locations** `/floc.html` · **Grants** `/grants.html` · **Definitions** `/definitions.html`. Rows 11–17 (0.9.0) are compared
against the running legacy program and Dev_Final's pilot branch, not against descriptions (decisions #157–#158).

| # | Legacy | Platform | Screen · what to look at | Expected | Reviewer · date |
|---|---|---|---|---|---|
| 1 | Grid state **Active** (`A`) | in service now (`InServiceFrom` set, `InServiceTo` null) | Settings · *Active* | the SEL-421 and BDD15B of the fixture change, verified date = the return-to-service instant; the CYL absent | |
| 2 | Grid state **Outstanding** (`M`) | a change in flight (the package's lifecycle non-terminal) | Settings · *Outstanding* | the second change on the SEL-421: lifecycle *Calculated*, no verified date; the same device also has an Active row | |
| 3 | Grid state **Archived** (`P`) | a later revision closed the in-service period, or the revision/package was superseded or withdrawn | Settings · *Archived* (a withdrawn member's row reads *Withdrawn* inside it — the separate toggle was removed by the W6 card, #134) | after a second change on the SEL-421 goes in service, its first row moves to Archived; the CYL of the first change shows there as Withdrawn | |
| 4 | Track status **Complete / NA / In progress** — documentation, database | the run's COMPLETION branches: Completed / NotApplicable / Running | Change request · *Completion tracks* | the closed fixture request: both tracks *Complete* with dates; the documentation track's *Go to document* link, revision label and revised date; the half-run request: *Not Started* | |
| 5 | Track status — **software** | not modelled (#58) | Change request · *Notes* (the third card was removed by the W6 card) | the legacy software-track rows read as dated notes on the request, as migrated | |
| 6 | Action type **Change / Add / Delete / Verify** | four `Program.WorkType` keys | Change request header · *Action type*; Settings · *Request change*; Locations · *New setting* | the type shown on the request; the four seeded keys offered in the action's dropdown | |
| 7 | **Set Verified Date** | `step.committed_at[id='RETURN_TO_SERVICE']` | Settings · a row whose return-to-service step is *Ready* · *Set verified date* | claim; a second person witnesses from their own session; commit (or check in a field-captured date) — the row's *Verified* fills once BASELINE commits | |
| 8 | **Request Change** / **Post-Close** / **Cancel** | *Start* / *Close* (guarded) / *Cancel* with a reason | Settings · *Request change*; Change request · *Post / Close*, *Cancel request* | a new request raised on the device and started; *Close* refused in the rule's words while the procedure runs; *Cancel* refused without a reason, done with one | |
| 9 | **Print** by state | the grid query, filtered | Settings · *Print* | the browser's print preview shows the grid as filtered and column-chosen, with a header naming the state, the row count, the time and the person | |
| 10 | **Grid by Location / Protected Asset / Protection Function** | the default view over the FLOC tree (#57) | Locations | the tree expands only where there is something beneath; a station shows its positions with panel, device, model, protection functions and schemes; browse by scheme and by model narrows the same grid | |
| 11 | **Main window: the active location, then its equipment groups** (rebuilt 0.9.0, #157–#158) | a location list; groups by functional scheme (the migrated EQUIPMENT text), collapsed with counts; a row unfolds to its card and settings text | Settings · pick *Bathurst Terminal* · open a group · click a row | no rows until a location is chosen; the groups collapsed with a count each; the opened row shows the card and the filed settings text; no legacy record number anywhere on screen; the grouping switch offers Equipment (panel) and Nothing | |
| 12 | **Right-click on a record** | a context menu (also ⋯ and Shift+F10) | Settings · right-click a row | Open the record · Change request · Set verified date (with a date first) · Request change · New setting here (location and scheme prefilled) · Compare revisions; a command the person may not run is greyed, not hidden | |
| 13 | **The change-request window** (rebuilt 0.9.0) | the stage bar from the workflow definition; the header in the legacy order; notes; three tracks side by side with read-only status radios | Change request | the stage bar names the workflow's states with the current one marked; the third track reads *not modelled* (#58); Post request / Close, Go to settings, Go to document | |
| 14 | **The queue** (new, round 5 B5) | `work.vChangeRequestStatus` counted in the browser | Requests | counters for raised, in progress, closed this month, cancelled; a counter filters the list; a row opens the request; an Active grid row whose device has an outstanding request shows a badge | |
| 15 | **Print** (replaces row 9's grid print) | the location report page | Settings · *Print report* | a new tab: the station and number, the state, the date; a section per scheme; each record with its facts and its settings text; the browser's print preview paginates it | |
| 16 | **Compare** (new, round 5 B4) | two revisions of one device side by side | Record · *Compare…* | the device's other revisions offered; differing settings highlighted (or differing text lines when nothing is parsed) | |
| 17 | **Scheme curation** (new, round 5 B11) | `scheme.Scheme_Revise`, `SchemeMember_Revise`, `AddSchemeMember` | Schemes · pick a location | its schemes with member positions; the positions in no scheme; rename, move a position, merge into another (the emptied scheme retired), new scheme, add an unplaced position | |

Also to be shown, from LEGACY-SYSTEM §8 and §9.1: the **column chooser** (Settings · *Select columns*; the legacy
columns as the default), the **record page** (0.9.0: the legacy groups under the platform's names — the CT/PT ratios,
class, use, responsibility, protection group, element, line type and number of relays read back from the migrated
record's detail; descriptions and remarks under Notes; no legacy field name or record number on screen), and that **user administration** is the
**Grants** screen (`/grants.html`, W8; decision #136 amending #130): accounts are the directory's; a person's roles and
scopes are grants an Administrator adds and revokes there, several per person (a transmission engineer under all three
owners — W7 card A).

Sign-off: ____________________ (NB Power reviewer) · ____________________ (supplier) · date ________
