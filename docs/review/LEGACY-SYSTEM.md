# The legacy system — measured

**The application Phase 1 replaces.** This document is the **parity baseline**: reporting parity
with this system is the contractual acceptance gate (Proposal §5), so it is specified here before
anything is built against it.

| | |
|---|---|
| Database | `dbRelayManagement_Legacy` on 10.10.70.25 |
| Source | `Z:\Archive-WorkingData-Cloud\Work\Projects\Setting_Management_CB12` |
| Built with | Embarcadero C++Builder (project files for CB11 and CB12), 17 forms |
| Read | 2026-09-11, by direct query and source inspection |

Every figure below was measured. Nothing is estimated.

> **Phase 1 replaces this application's *functionality* — not its structure or its stack.**
> Reproduce what it does for the people who use it. Do not reproduce its shape.

---

## 1. Size

**9 tables · 48,706 rows · zero business logic in the database.**

All seven "stored procedures" in the database are SQL Server's own `sp_*diagram*` helpers. There
is one scalar function, `fn_diagramobjects`, also SQL Server's. There are **no views**.

Every rule, every query and every report lives in the C++ application, built inline. **There is
nothing to port from the database side** — no stored reports, no business procedures, no
constraints worth carrying.

| Table | Rows | What it holds |
|---|---:|---|
| `SETTINGS` | 14 211 | The settings records. 43 flat columns |
| `Settings Management` | 8 409 | Change-request header |
| `Relay Document Management` | 8 409 | Completion track 1 |
| `Setting Database Management` | 8 408 | Completion track 2 |
| `Setting Software Management` | 8 408 | Completion track 3 |
| `LOCATIONS` | 825 | Location list; 29 are unreferenced by any settings row |
| `Users` | 32 | Application users |
| `Setting Software Data` | 4 | |
| `sysdiagrams` | 0 | SQL Server diagram storage |

---

## 2. The settings record

`SETTINGS` is a flat 43-column table. Its shape is the clearest statement of what the legacy
system could and could not express.

```
OLD_NO · Change Request ID · LOCATION · ASSET · EQUIPMENT · DEVICE · FUNCTIONS
SERIAL_NUMBER · SOFTWARE_VERSION · MANUFACTURER · VOLTAGE · NUMBER OF RELAYS
CT_MAIN1-4 · CT_AUX1-4 · PT_MAIN · PT_AUX
SET1 · SETTINGS2
DESC1-4 · REMARKS1-5
CLASS · USE · RESPONSIBILITY · Bulk_Power_Element · Protection_Group · ELEMENT · LINE_TYPE
CDATE · VDATE · IDATE
```

`DESC1–4` and `REMARKS1–5` are the classic flat-file overflow columns — nine free-text slots
standing in for a relationship the schema could not express. `CT_MAIN1–4` and `CT_AUX1–4` are the
same pattern applied to instrument transformers.

### The two dates that matter

| Column | Meaning | Nulls | 1899-12-30 sentinel | Latest real value |
|---|---|---:|---:|---|
| `CDATE` | **Calculated date** | 1 188 | 54 | 2025-12-10 |
| `VDATE` | **Verified date — when it went into service** | 1 273 | 75 | 2025-12-10 |

The 1899-12-30 values are an empty-date sentinel inherited from the Delphi/VCL date origin, not
real dates. Two rows carry a `CDATE` in the future; the maximum is 2112-03-02.

Content spread: 782 distinct `EQUIPMENT` values · 46 distinct `MANUFACTURER` · 227 distinct
`LOCATION` · 13 771 of 14 211 rows have `SET1` populated.

---

## 3. Record state — encoded in the primary key

The state of a settings record is **the first character of `OLD_NO`**. The application filters on
the string literals `"A%"`, `"M%"` and `"P%"`.

| Prefix | Rows | Meaning |
|---|---:|---|
| `A` | 5 641 | **Active** — in service |
| `M` | 357 | **Outstanding** — a change in flight |
| `P` | 5 850 | **Archived** — superseded |
| `D` | 2 361 | Work request **deleted before completion**. No significance; dropped at cutover |
| `2` | 2 | Malformed |

The 2 361 `D` rows are **17% of the table and unreachable through the application**, which filters
only A, M and P. Their Change Request IDs are real, ranging 4 – 9 449 045; they are not row
counters. The owner has confirmed they carry no significance and are dropped at cutover.

---

## 4. The document rotation

The same three letters drive the settings document filenames. Described by the owner and
corroborated against the data:

1. A device in service has **`A9999.docx`**.
2. A work order is raised against it → a copy is created as **`M9999_12345.docx`**, where `12345`
   is the **Change Request ID**.
3. When all requested work completes:
   - `A9999.docx` is renamed **`P9999_12345.docx`** — archived;
   - `M9999_12345.docx` is renamed **`A9999.docx`** — it becomes the new in-service document.

Two consequences that matter for migration:

- **An archived file's suffix is the Change Request that *ended* that revision, not the one that
  created it.** Reading a `P` filename tells you what superseded it, not what made it.
- **The live `A` file carries no Change Request ID in its name.** Its `SETTINGS` row does, so
  provenance is recoverable — but from the database, never from the filename.

Revision provenance is therefore **reconstructed by chaining**, never read off a filename.

---

## 5. The revision chain — verified integrity

| Check | Result |
|---|---|
| Is `OLD_NO` unique? | **No** — 14 211 rows, 11 718 distinct values |
| Is `(OLD_NO, Change Request ID)` unique? | **Yes — 0 collisions.** This is the natural key |
| Distinct device identities (base number, A/M/P) | 6 842 |
| Bases with more than one `A` row | **0** — one in-service record per device holds without exception |
| Devices with a current in-service record | 5 641 |
| Devices with **no** current record | 1 201 — fully retired |
| Open work at cutover (`M` rows) | 357, one per device |
| Deepest revision history | 11 revisions (base `0439`) |
| Bases where an archived CR **exceeds** the active CR | **17 — genuine ordering violations** |
| A/M/P rows with a Change Request ID below 1000 | 617 — pre-numbering legacy records |

The **base number** — `OLD_NO` minus its state prefix — is the device identity that ties a chain
together. A chain orders by ascending Change Request ID, with the `A` row carrying the highest.
The 17 violations break that rule and must be reconciled explicitly rather than assumed away.

Several revisions within one chain frequently share a `VDATE`, so **verified date alone cannot
order a chain**. Change Request ID is the ordering key.

---

## 6. The change request, and its three parallel tracks

`Settings Management` is the change-request header:

```
Change Request ID · SAP Work Order Numer · Relay ID Number · Notes · Date · Type · Reqested By
```

The column spellings are as found. `SAP Work Order Numer` is populated on **50 of 8 409 rows**, so
the SAP linkage exists but is barely used. The `Date` column is **100% NULL** — 0 of 8 409 rows
carry a value.

`Change Request ID` is **not unique** in this table: 6 NULLs and 894 values appearing more than
once, giving 899 surplus rows.

### Action types

| Type | Count |
|---|---:|
| Change Order | 3 461 |
| Delete Order | 2 871 |
| Add Order | 1 980 |
| **Verify Order** | **77** |
| (null) | 20 |

### The three tracks — the finding that shapes the new design

Each change request is completed across **three separate tables of identical shape**:

| Table | Complete | NA | Change In Progress | null |
|---|---:|---:|---:|---:|
| `Relay Document Management` | 4 445 | 3 615 | 334 | 15 |
| `Setting Database Management` | 5 118 | 2 941 | 334 | 15 |
| `Setting Software Management` | 6 487*| 1 572*| 334 | 15 |

<small>*`Setting Software Management` is the inverse of the others: 6 487 NA against 1 572 Complete.</small>

Each carries `Change Request ID · Relay ID Number · Status · Notes · Date`. These three tables
have dates where the header does not — the latest is 2025-11-27.

**This is not a three-step workflow. It is three concurrent branches, hard-coded as three
tables** — update the documentation, update the settings database, update the settings software —
each independently Complete, NA or Change In Progress, and the request closing when all three
resolve.

That is precisely **capability #9, parallel branches**, from the procedure vocabulary in
`REQUIREMENTS.md` FR-1.2. The new engine does not merely replace this; it generalises it. The
legacy system proved the group needs parallel tracks and could only express them by writing three
tables.

### The software track — owner's ruling, and what the data says

**Owner, 2026-09-11:** *"the software track was never implemented and can be dropped (this can be
verified by noting that all software status' are NA)."*

**Measured** (`Setting Software Management`, re-counted the same day): NA 6 487 · **Complete
1 572** · Change In Progress 334 · null 15. The Complete rows are dated 2005 through 2025, with
spikes in 2018 (234) and 2021 (212); 231 carry no date. **137 of them carry their own notes** —
e.g. *"Settings file on T drive under Norton. 2005-09-27 DML"*, *"Settings file completed and
placed under Norton on 'T' drive"*. So the track was used, by some people, in some years — 19% of
requests marked it Complete — and was not used consistently. "All NA" is the practice as
remembered, not the data as stored.

**Ruling stands.** The software track is dropped from the new procedure (decision #58). Its
**1 906 non-NA rows are not discarded**: they migrate as notes on the change request, so the
history survives even though the branch does not. Reporting parity for the software column is
therefore "not modelled", and the parity screens show two tracks.

---

## 7. Users

32 rows. Three privilege levels — level 2 (4 users), level 5 (17), level 10 (10), one unset.
**31 of 32 rows carry a stored password.** Authentication is the application's own.

This is what Active Directory authentication and the seven account types replace
(`REQUIREMENTS.md` FR-6.1).

---

## 8. The functional surface to replace

Taken from the forms. **This is what reporting parity means** — nothing more than this list.

### Main window
A grid of settings records, with:
- a **state toggle** cycling Active → Outstanding → Archived, which re-filters the grid and
  switches the report variable to match;
- **Select columns** — the user chooses which fields the grid shows;
- **Print** — a report of the current grid, filtered by the selected state;
- a location label and an active-location concept;
- menu: File · Setup · Exit · About · Version · Update Application;
- actions: **Set Verified Date** · **Request Change** · **New Setting**.

Set Verified Date and Request Change are **disabled unless the grid is in the Active state** — a
hard-coded rule of exactly the kind the procedure engine exists to make authorable.

### Change request / status window
Relay ID Number · Notes · Location · Equipment · **Action Type** · Requested By, and the three
tracks — Relay Setting Documentation, Relay Setting Database, Relay Setting Software — each with
its own Date and Status and a **Go to Document** / **Go to Settings Page** link.

Actions: **Post Request/Close** · **Cancel/Delete Work Request** · **Complete Request**.

### Setting display
A read-only then editable view of the flat record, grouped as: General · System Info ·
M/P Information · Aux CT/PT Info · Documentation. Fields as listed in §2.

### Administration
User administration (`prog_frmUsers`), database setup (`prog_dlgDBSetup`), and an application
updater (`progFRM_Update`).

---

## 9. What this tells the new design

1. **Reporting parity is small and now fully specified.** A grid by state, a column chooser, a
   filtered print, a verified-date action, a change request with three tracks, a flat record view,
   user administration. That is the gate.
2. **The group already works in parallel tracks.** The three tables are the evidence. The
   procedure engine must support that as authored structure, not as three more tables.
3. **State is encoded in three places** — the key prefix, the document filename, and the
   application's literal filters. All three must be decoded on migration, and none of them should
   survive into the new model.
4. **There is no history mechanism beyond the chain.** No audit, no attribution of change, no
   record of who approved anything. `Reqested By` is a free-text name on the header. Everything in
   `REQUIREMENTS.md` §5 — point in time, proof, impact, reconstruction — is genuinely new
   capability, not a port.
5. **`Verify Order` is rare — 77 of 8 409.** Verification as a distinct activity barely exists in
   the legacy process, which is worth knowing before assuming the group has an established
   verification practice to preserve.
