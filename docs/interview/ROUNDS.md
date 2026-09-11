# The interview — seven rounds, verbatim

The owner's answers to the requirements interview, 2026-09-10 to 2026-09-11, recorded exactly as
captured from each round's decision card. This is the **provenance record** that
`REQUIREMENTS.md` and `DECISION-LOG.md` cite.

Free-text answers are quoted verbatim, including spelling. Button selections are listed as chosen.
Where a box was left empty, that is recorded too — it is information.

---

## Round 1 — Why is there a V2?

**Q1 — What is V2's relationship to the platform running at 0.10.5?**
Selected: **V2 is the real delivery repo; the old one becomes reference.**

> "I want a full review of the schema based upon an exhaustive interview of the desired outcomes."

**Q2 — What made you start over rather than continue?**
Selected: **I can no longer hold it in my head.**

> "This project is very large and important, we need to make sure that the starting architecture
> sets us up for that end result and not just a phase 1 outcome."

---

## Round 2 — What the platform must answer

**Q1 — When all five phases are done, what is this platform primarily?**
Selected: **The engineering work environment.**

> "Although all of the above a very important, at the end of the day, I am contracted to replace
> the existing engineering environment."

**Q2 — Which of these must the platform answer, cold, years after the fact?**
Selected: **Point in time · Proof of obligation · Impact · Reconstruction.**
Not selected: Change and rationale · Estate · Authorisation.

Which one, if it failed, would be a serious professional problem:
> "impact"

Anything the platform must answer that isn't listed: *(empty)*

---

## Round 3 — One settings change, end to end

**Q1 — Which of these are real, distinct steps in the work today?**
Selected: **all fourteen** — request · scope and design · study · vendor tool · rationale ·
independent check · approval · issue · field application · readback · test · return to service ·
baseline · drawings.

Walkthrough of one real change: *(empty)*
Where the existing environment fails hardest: *(empty)*

**Q2 — Impact: what sets off the search, and how far does it have to reach?**
Selected: **all eight** — standard · advisory · system change · template · primary plant ·
device swap · error found · misoperation.

The worst impact question you've had to answer: *(empty)*
How far the answer has to reach: *(empty)*

---

## Round 4 — How big is this estate

**Q1 — The dials.**

| Dial | Answer |
|---|---|
| Stations and sites | 50–150 |
| Protection devices in scope | 2k–10k |
| Microprocessor share | 25–50% |
| Settings records held | 10k–100k |
| Years of history to migrate | 15–25 yr |
| Documents to hold | 50k–250k |
| Named users | 25–75 |
| Peak concurrent users | <10 |
| Settings changes per year | 100–500 |
| Test records per year | 200–1000 |

**Q2 — One real settings change, walked through** *(carried over from Round 3)*:

> "the setting change walkthrough really does bring to the front what is needed. We need to create
> a process engine that will allow us to create/edit etc. all the various procedures that need to
> be followed in the group...from the setting change process to compliance procedures etc. etc.
> etc. There can be no hard coded procedures"

Where the existing environment fails hardest:

> "at the present time, the setting procedure is hard coded into three very simple steps...in
> service, outstanding and retired, which is entirely inadequate."

Database access note:

> "PnCPlatform_DEV and _QA is the platform to review, details of how to connect can be found in
> the c:\Projects\PnCPlatform repo."

---

## Round 5 — One engine or two

**Q1 — What must a procedure be able to express?**
Selected: ordered steps · data capture · conditional branching · guards and preconditions · role
and competency per step · sign-off with attribution · evidence at a step · parallel branches ·
sub-procedures · timing and due dates · hold points · recorded deviation. **(12 of 14)**
Not selected: iteration over a set · in-flight work pinned to a version.

A procedure that would break the engine: *(empty)*

**Q2 — Are a workflow and a procedure one thing or two?**
Selected: **Two layers, deliberately.**

Anything that should decide this: *(empty)*

---

## Round 6 — Who owns which truth

**Q1 — Two things left out that argue with earlier answers.**

| Conflict | Ruling |
|---|---|
| In-flight work pinned to a procedure version | **Pin it** — in-flight work keeps the version it started on |
| Iteration over a set | **Needed** — a procedure can repeat over a set |

**Q2 — Where does the platform's authority stop?**

| Domain | Answer |
|---|---|
| Functional locations | THEIRS |
| Everything below the panel | OURS |
| Device identity and serial numbers | OURS |
| Relay settings and configuration files | OURS |
| Protection schemes | OURS |
| Wiring, cables and terminations | *unsure* |
| Drawings and schematics | THEIRS |
| Work orders and scheduling | OURS |
| Asset registers, spares, materials | OURS |
| The power-system model | OURS |
| Test and commissioning records | THEIRS |
| People, qualifications, authorisations | OURS |
| Standards and obligations | OURS |
| Events, faults and misoperations | OURS |

Boundary note: *(empty)*

---

## Round 7 — Where the boundary breaks

Five ownership calls that collided with the contract, a settled decision, or each other.

| Conflict | Ruling |
|---|---|
| Work orders | **Split — keep decision 36.** Cascade owns the scheduled order; the platform owns the Work Request |
| Asset registers, spares, materials | **Ours for P&C engineering facts only.** SAP keeps purchase, stock, cost, warranty |
| Test and commissioning records | **Split — the test tool keeps the raw file, we own the result** |
| Drawings and schematics | **Split — they hold the file, we hold what it depicts** |
| Wiring, cables, terminations | **Ours, but not in Phase 1** — the schema carries the shape from the start |

Anything read wrong: *(empty)*

---

## Requirements v0.1 — review marks

31 requirements: **29 keep · 2 change · 0 drop.**

| Requirement | Mark | Note |
|---|---|---|
| FR-6.1 | change | "users will authenticate as themselves and then within the application they will be tied to the account types" |
| NFR-2 | change | "while true, the application must be responsive for usability's sake" |
| All others | keep | |

Overall: *(empty)*

---

## Schema review — verdict

Selected: **Carry the proven subsystems forward; design the procedure engine fresh.**

Reasoning or a fourth option: *(empty)*

---

## Plan-stage answers, 2026-09-11

Asked in the terminal before the first commit was planned.

| Question | Answer |
|---|---|
| Who authors procedures besides you? | **Me now, P&C engineers later** |
| What should the first commit contain? | **Documents only** |
| What stack does V2 carry forward? | **Same as PnCPlatform — .NET + PWA** |

And, in the owner's own words during plan review:

> "note that phase 1 is to replace the functionality, not the application structure or stack"

> "Final data migration will occur only at the end, the client will provide an, up to date, copy
> of the obsolete database (structurally equivalent to dbRelayManagement_Legacy) for us to import
> into our final product. For testing we can import and utilize the flat database, as well as any
> of the other sample databases from the earlier prototypes. our copy of the legacy database and
> the one we will be given will be very close to the same with only about a years worth of setting
> changes (~100) made, as a result, we can import the one we have and then perform an updated
> import of only the differences, when the final import occurs. This will shorten significantly
> the cutover time."

> "D in the OLD_NO signifies that a work request was deleted prior to completion, in our cutover,
> these can be dropped as they have no significance."

> "CData is actually the calculated data and VDate is the verified date (when it went into
> service). These are the two date fields of importance"

> "In your assessment of the document filenames, you are almost correct, when an 'in service'
> device A9999.docs, has a work order placed against it, a new document is created by copying
> A9999.docx called M9999_12345.docx where the 12345 is the "Change Request ID" field in the
> various tables. When all the requested work gets completed, the A9999.docx gets renamed
> P9999_12345.docx, effectively archiving it and the M9999_12345.docx then gets renamed
> A9999.docx, making it the new "in service" document"

---

## An observation about the answers

Across seven rounds, every button was answered and almost every free-text box was left empty. The
exceptions — Round 1, Round 4, and the plan-stage corrections — carry most of the information in
this record. The interview adapted after Round 5 to put propositions in front of the owner rather
than asking for narrative, and the corrections that followed were the sharpest answers of all.
