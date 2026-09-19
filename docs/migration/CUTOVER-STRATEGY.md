# Cutover strategy — legacy data migration

How data from `dbRelayManagement_Legacy` arrives in the platform, and why not by watermark.

The legacy system is characterised in `docs/review/LEGACY-SYSTEM.md`. This document assumes it.

---

## 1. The owner's plan — adopted

1. **Now:** import our copy of `dbRelayManagement_Legacy` for build and test. The earlier
   prototypes' sample databases may also be used for testing.
2. **At cutover:** the client supplies a current copy, structurally equivalent to ours.
3. Import **only the differences**, so cutover is short.

Our copy and the client's will be close. The plan is right. The obvious implementation of step 3
is not.

---

## 2. Why not a watermark

A watermark delta — "everything with an ID or date past the last one we saw" — needs a reliable
key or a reliable date. The legacy data has neither. Three measured reasons:

| Reason | Measurement |
|---|---|
| **No date on the change-request header.** `Settings Management.[Date]` is entirely empty | 0 of 8 409 rows carry a value |
| **`Change Request ID` is not unique** in the header table | 6 NULL, 894 values appearing more than once, 899 surplus rows |
| **A watermark misses in-place edits.** Correcting an old record moves no watermark, so the correction never transfers | This is the likeliest correction pattern in a flat database |

The third is the decisive one. A watermark that works perfectly for new rows will silently lose
every edit to an existing row, and there is no way to detect that it has.

---

## 3. What to do instead — full-table content-hash diff

The entire legacy database is **48 706 rows**. That is small enough to compare completely.

At cutover:

1. Hash every row of every table in **our** imported copy, keyed by natural key.
2. Hash every row of every table in the **client's** copy, the same way.
3. Compare. Every row is in exactly one of four sets: unchanged · added · changed · deleted.
4. Apply the adds, changes and deletes through the ordinary migration mapping.
5. Record the counts of each set as the cutover's provenance.

Properties:

- **Runs in seconds.** 48 706 rows is trivial.
- **Provably complete.** Nothing depends on a key being unique or a date being populated.
- **Catches back-dated edits**, which a watermark cannot.
- **Independent of any estimate of the change rate** — see §4.

Natural keys for hashing:

| Table | Key |
|---|---|
| `SETTINGS` | `(OLD_NO, Change Request ID)` — verified 0 collisions |
| The three track tables | `(Change Request ID, Relay ID Number)` — to be verified against the client copy |
| `Settings Management` | No reliable key. Hash the whole row; treat duplicates as a set, not a sequence |
| `LOCATIONS`, `Users` | Whole row |

---

## 4. On the change-rate estimate

The owner expects **~100** setting changes in the intervening year.

Measured on in-service records by verified year:

| Year | In-service records verified |
|---|---:|
| 2025 | 666 |
| 2024 | 625 |
| 2023 | 595 |
| 2022 | 411 |
| 2021 | 600 |

The rate is nearer **600 a year**, consistent with the upper half of the Round 4 dial
(100–500). Our copy's latest real `CDATE` and `VDATE` are both **2025-12-10**; as of 2026-09-11 it
is about nine months stale, implying roughly **450** changed records at cutover rather than 100.

The hash-diff approach makes this discrepancy harmless — the cost of the diff does not depend on
its size. That is the main reason to prefer it over any method that does.

---

## 5. The migration mapping

How legacy rows become platform facts. The rules, not the code. **The current, complete register is generated:
`docs/schema/migration/MIGRATION-RULES.md` (from the importer's own rule calls, the seeds that act on migrated data, and the
list of hand edits that are not rules) — #194, owner 2026-09-19: every migration decision is remembered and replayed at the
real cutover on the client's verified copy.**

| Legacy | Becomes | Rule |
|---|---|---|
| **Base number** (`OLD_NO` minus prefix) | The device / setting identity | 6 842 distinct. Ties a revision chain together |
| `A` row | The **current in-service** revision | Exactly one per base — verified 0 violations |
| `P` rows | **Revision history**, ordered by ascending Change Request ID | The `A` row carries the highest CR in its chain. Several revisions may share a `VDATE`, so `VDATE` cannot order |
| `M` rows | **Open work in flight** — 357, one per device | Each becomes a running `SETTINGS_CHANGE` instance **landed at the `COMPLETION` block**, with its two branch states set from the legacy documentation and database tracks (Complete → Completed · NA → NotApplicable · Change In Progress → Running) and steps 1–12 recorded as *migrated — not performed in this platform*, using the migration list's own mechanism (design §6). Owner's ruling #56. Nothing about the earlier steps is invented |
| The three track tables — **software** column | Notes on the migrated request | The software track is not in the new procedure (owner's ruling #58). Its 1 906 non-NA rows — 1 572 Complete, 334 In Progress — are carried as dated notes with their text, never dropped |
| `D` rows | **Dropped** — 2 361 rows | Work request deleted before completion; no significance (owner). Dropped with a **counted, recorded reason**, never silently |
| The 2 rows keyed `2440` | **Dropped, with a counted reason** | A model number typed into the key; one SEL-2440 at Belledune, 2018. Owner's ruling #60 |
| The 17 bases where an archived CR exceeds the active CR | **Migrated as the letters say; each becomes a finding on day one** | `A` active, `P` history, no automatic correction. A person rules on each afterwards. Owner's ruling #59 |
| The 617 A/M/P rows with a CR below 1000 | Ordinary rows | No rule needed: CRs below 1 000 sort first, correctly; 334 are single-row chains (#72) |
| `SET1` (13 771 populated) | **The revision's settings file, text format** | The legacy name=value text *is* the text settings-file format of decision #61. Each populated `SET1` becomes a `ConfigurationFile` of kind `SettingsText` on its revision, parsed later against the device's template |
| `IDATE` | Dropped | NULL in all 14 211 rows (#72) |
| Document filenames `A9999` / `M9999_12345` / `P9999_12345` | State decoded and discarded; the file attaches to its revision | State must **not** survive into filenames |
| `CDATE` | Calculated date on the revision | 1 188 null, 54 sentinel — **sentinel means unknown** (#62): null in the platform |
| `VDATE` | Verified / in-service date on the revision | 1 273 null, 75 sentinel — likewise |
| `Settings Management` row | The Work Request | `SAP Work Order Numer` (50 populated) → the Cascade/SAP link |
| The three track tables | Three **parallel branches** of one procedure instance | Complete / NA / Change In Progress map to branch outcomes |
| `Type` | Work type | Change · Delete · Add · Verify |
| `Users` | Persons, not accounts | Stored passwords are **not** migrated. Identity comes from Active Directory |
| `DESC1-4`, `REMARKS1-5`, `CT_*`, `PT_*` | Characteristics on the revision | Overflow columns become typed characteristic values where a definition exists, free-text notes where not |
| `CLASS`, `USE`, `RESPONSIBILITY`, `Bulk_Power_Element`, `Protection_Group`, `ELEMENT`, `LINE_TYPE`, `NUMBER OF RELAYS` | **Dropped, counted** | Owner's ruling #194 (2026-09-19): "I do not trust any of the data in those fields". The platform's own facts stand in: model technology, the relay's capabilities, the scheme and what it protects, the A-10 bus classification |

---

## 6. What this does not decide

- The **platform-side schema** the mapping lands in. That is the carry-forward map plus the new
  procedure engine, neither of which is code yet.
- Whether the 1899-12-30 sentinel rows should be treated as unknown or as a specific historical
  meaning. The owner has not been asked.
- The rule for ordering the 617 pre-numbering rows and the 17 violations. Both need a ruling before
  the mapping is agreed with the client.
