# Identity, roles and scopes — W2

**v0.2 · 2026-09-12 · W2 specification, as built.** How a directory identity becomes a person with rights, how the
seven account types of the SOW become grants, and how *read scope equals write scope* is enforced on
every list read. Builds on `API.md` (W1) and decision #66; nothing here changes the schema's access
model, which is carried (`security.fHasPermission`, `PnCPlatform` §2.4) — W2 fills it and makes the
API honour it on lists.

---

## 0. The one paragraph

A person signs in as themselves; the platform holds a `security.User` for that identity and
**grants** that tie the person to roles with a **scope**. There is one engineer role, one
technician role, one approver grant and one administrator; an engineer's scope is a **division** of
the location tree — Transmission, Distribution, Generation·Hydro, ·Belledune, ·Coleson — and
everything the person reads or writes is decided by whether the subject lies under that division.
A list never shows a row the person could not open one at a time.

---

## 1. Scope of W2

From `PHASE-1-WORKFLOW.md` W2 and estimate package F.

| Part | What it is |
|---|---|
| Roles | `PCEngineer`, `PCTechnician`, `PCApprover`, `Administrator`, `ReadOnly` active; the predecessor's fourteen others deactivated (soft) |
| Permissions | a role → permission matrix seeded, reviewable on the W2 card (§3) |
| Divisions | five `Division` nodes under one `Owner` node, the scopes of #66, seeded as data (§4) |
| Identity | the directory SID as the user's alternate key, written on first sign-in (§2) |
| Read scope on lists | `security.fReadableSubjects` and the dispatcher's join (§5) — **the new mechanism** |
| Smoke | a third, scoped identity and a fixture that has rows inside and outside its scope (§7) |

**Not in W2:** stations and assets of the real estate (W7 places them under divisions; the source of
the station → division mapping is unknown in the legacy data and is a W7 card item); groups and
delegations beyond what the schema already does; screens (W6).

---

## 2. Identity

**2.1 The key.** W1 matched the IIS name to `security.User.UserPrincipalName` through
`Auth:UpnSuffix`. W2 adds the directory **SID** as the durable key: `security.AlternateKey` with
`KeyKindCode = ActiveDirectorySid` (seeded in `ref.AlternateKeyKind`, `security.User` as subject).
Lookup order on a request: SID → user; else UPN → user, and when found by UPN with no SID key yet,
the SID is **written** (`security.AlternateKey_Add`) and the act logged as `Administrative`. A
renamed account keeps its person; a re-created account with the same name and a new SID is a new
identity until an administrator says otherwise — presence in the directory still grants nothing.

**2.2 DEV mode** has no SID (the header asserts a UPN); the lookup is UPN only, unchanged.

---

## 3. Roles and permissions

`security.Role` already holds nineteen codes from the predecessor's seeds. W2 keeps five active and
deactivates the rest with `security.Role_Deactivate` (soft; nothing is deleted; reactivation is a
row):

| Active | Kind | Meaning (#66, FR-6.1) |
|---|---|---|
| `Administrator` | Positional | authors and approves definitions, grants access — every permission |
| `PCEngineer` | | designs, calculates, checks settings **within scope**; scope is the grant's |
| `PCApprover` | | a separate grant carrying the approvals; held by some engineers, never implied by `PCEngineer` |
| `PCTechnician` | | applies settings, performs tests, captures records within scope |
| `ReadOnly` | | every `.Read` |

`Assignee` (assignment role, work-request scope) and `PlacementOverride` are schema mechanics, not
account types; they stay active and unlisted.

**The matrix** (`PostDeploy/Seed_security_RolePermission.sql`, extended; codes are
`<SubjectClass>.<Verb>` over the twelve seeded classes):

| Class | PCEngineer | PCApprover | PCTechnician | ReadOnly |
|---|---|---|---|---|
| Node, Asset, Device, Scheme, Connection | Read, Modify, Report | Read | Read | Read |
| ConfigurationFile | Read, Modify, Report | Read, **Approve** | Read, Modify (readback, in-service) | Read |
| Document | Read, Modify, Report | Read, **Approve** | Read | Read |
| WorkRequest | Read, Modify, Report | Read, **Approve** | Read, Modify | Read |
| Record | Read, Modify, Report | Read, **Approve** | Read, **Modify** | Read |
| Obligation | Read, Report | Read | Read | Read |
| Definition | Read, **Modify, Approve** (W5 card F, #126; under a Global grant only — a definition has no node) | Read | Read | Read |
| Grant | — | — | — | — |

`Archive` and `Administer` stay the Administrator's everywhere. This is the proposition the W2 card
puts to the owner; the seed is idempotent, so an amendment is a row change and a redeploy.

---

## 4. Scopes

The location tree's grammar already has `Owner → Division → Station` (`ref.LocationNodeTypeParent`).
W2 seeds, as data through `location.AddNode`, one owner and five divisions:

```
NB Power (Owner)
├── Transmission            (Division)
├── Distribution            (Division)
├── Generation · Hydro      (Division)
├── Generation · Belledune  (Division)
└── Generation · Coleson    (Division)
```

An engineer's grant is `PCEngineer` with `ScopeKind = NodeSubtree` on one division; a person with
two divisions holds two grants. `fHasPermission` already decides a subject by its node's `Path`
under the scope node's `Path`, with the asset-class and device-category filters (carried, read this
session). Stations placed under a division in W7 inherit the scope by position; nothing in a station
row names its division.

---

## 5. Read scope on lists — the new mechanism

**The rule.** *Read scope is as strict as write scope* (FR-6.2, #66, PnCPlatform #59). W1 decided a
list read on the class alone: a scoped engineer with any grant on the class could list every row.
That is the predecessor's behaviour (its `ApiEndpoints.cs:75`), and it is wrong for #66's
*"completely separate"*.

**The mechanism, in one paragraph.** The database answers, set-wise, *which subjects of a kind may
this user read*: `security.fReadableSubjects(@userEntityId, @permissionCode, @subjectKind, @at)` is
an **inline** table function returning `SubjectEntityId`. It walks the same grants `fHasPermission`
walks, but forwards: Global → every subject of the kind; NodeSubtree → the nodes under the scope
paths, and the assets placed under them (with the asset-class and device-category filters), and the
records and work requests whose subject is one of those; WorkRequest and OwnershipRelation scopes
likewise. Subject kinds with no node mapping (Document, Obligation, Grant) are readable under Global
only, as `fHasPermission` already rules; **Definition (config, ref) reads are class-wide for any role that carries
`Definition.Read`, whatever the grant's scope** (owner, W6 card H, 2026-09-12, decision #134 — a division-scoped
engineer needs the work types, models and procedures to act at all); definition writes and approvals stay Global-only. The dispatcher adds one clause to a list read:
`WHERE <subject column> IN (SELECT SubjectEntityId FROM security.fReadableSubjects(…))`. The rule is
the database's; the API knows only *which column of this view is the subject and of what kind*.

**Which column, of what kind.** Derived from the catalogue and `ref.SubjectKind`, no per-view
hand-list: the view's base table (the catalogue reads `sys.views` → referenced table); if the
table's registry is a `SubjectKind` table (`asset.AssetRegistry` → Asset family; `location.NodeRegistry`
→ Node family; `record.RecordRegistry`, `work.WorkRequestRegistry`), the subject column is
`EntityId`. Otherwise the first subject column the view carries, in the map's `subjectKeys` order
(`AssetEntityId`, `NodeEntityId`, `SubjectEntityId` with its `SubjectKind` column, …), scoped by that
column's kind. A view with none of these is decided on the class, as today — and the catalogue
reports which rule each view falls under, so the W2 card can show it.

**Single-entity reads and writes** are unchanged: `fHasPermission` on the named subject.

**The list gate (as built).** `fHasPermission` with no subject is Global-only by design, which refused
every list to a scoped engineer. A list read of a scoped view is therefore gated by
`security.fHoldsPermission(@user, @permission, @at)` — *held in any scope* — and its rows are then
filtered by `fReadableSubjects`. A view with no subject mapping keeps the class decision.

**A defect found on the way (API-W2-SECURITY.md #1).** A node's `Path` holds its ancestors' ids only,
so the carried predicate `n.Path LIKE sn.Path + '%'` matched every sibling subtree: a Transmission
grant covered Distribution. Corrected in `fHasPermission` and written correctly here:
`n.EntityId = sn.EntityId OR n.Path LIKE sn.Path + sn.EntityId + '/%'`.

**Cost.** One inline function joined into a paged query over at most a few thousand rows of any kind
(NFR-2 figures); the paths are prefix matches on `location.Node.Path`. Measured on the gate fixture
before W2 closes.

---

## 6. Where the fixture data comes from

The smoke seeds, through the procedures as the SYSTEM actor: the owner and division nodes if
absent; under Generation·Hydro one station with one panel and one asset placed in it; under
Transmission the same; and three identities — Administrator (Global), ReadOnly (Global), and
**a `PCEngineer` scoped to Generation·Hydro**. Everything the smoke creates it soft-deletes at the
end, except the owner and division nodes, which are the platform's.

---

## 7. Gate (from the workflow, made concrete)

Smoke as three identities — Administrator, ReadOnly, and the Hydro-scoped engineer:

1. As Hydro: `GET asset/vAsset` lists the Hydro asset and **not** the Transmission asset; `GET
   location/vNode` lists Hydro's station and panel and not Transmission's; `GET asset/vAsset?EntityId=<Transmission asset>` → 403.
2. As Hydro: a write on the Hydro asset succeeds; the same write on the Transmission asset → 403 with
   an `AccessRefused` row.
3. As Administrator and ReadOnly: both assets listed; ReadOnly's write refused as in W1.
4. `security.vRole`: exactly the five active roles; `vRolePermission` matches §3.
5. **One row visible outside scope is a failure.**

Windows mode: the same as a real `vgsot.internal` account holding the Hydro grant — a dedicated gate
account, created and held for the purpose (W2 card, standing authorisation), so that no gate ever
again needs a person at a console.

---

## 8. Decisions this specification takes

| Proposed | Decision |
|---|---|
| A | Five active roles; the predecessor's other fourteen deactivated, never deleted |
| B | The matrix of §3 as the seeded defaults; Archive and Administer are the Administrator's |
| C | Scopes are `Division` nodes under one `Owner` node, seeded as data; grants are NodeSubtree on a division |
| D | List reads are filtered by `security.fReadableSubjects`, an inline function in the database; the API contributes only the subject column and kind, derived from the catalogue |
| E | The directory SID is written as the user's alternate key on first sign-in and preferred thereafter |
| F | Gate identities are dedicated domain accounts, not the owner's |
