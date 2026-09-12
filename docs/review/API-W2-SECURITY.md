# PnC.Api W2 — security analysis

**2026-09-12 · the W2 changes: `security.fReadableSubjects`, `security.fHoldsPermission`, the corrected
subtree predicate in `security.fHasPermission`, the dispatcher's scoped list reads, typed subject keys,
and SID registration.** Same method as W1: every surface walked adversarially, every claim read in the
source or the database or exercised against the running API and the V2 database.

## Findings

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | **High, carried code** | `fHasPermission` tested "under the scope node" as `n.Path LIKE sn.Path + '%'`. A node's `Path` holds its ancestors only, so the predicate also matched every *sibling* subtree: a grant on Transmission covered Distribution and every other division under the owner. The predecessor's smoke never placed two scoped subtrees under one parent, so it never saw it. Observed here before the fix: the Hydro-scoped engineer created a node under the Transmission building (the "stray room", soft-deleted after). | **Fixed** in `fHasPermission` and written correctly in `fReadableSubjects`: `n.EntityId = sn.EntityId OR n.Path LIKE sn.Path + sn.EntityId + '/%'`. Verified by the W2 smoke: the same write now answers 403 and leaves an `AccessRefused` row. |
| 2 | **Medium** | A list read by a scoped user was refused outright (403), because `fHasPermission` with no subject is Global-only by design. Fail-closed, but it made the scope model unusable for its own purpose. | **Fixed** with `fHoldsPermission` (any scope) as the list gate, rows then filtered by `fReadableSubjects`. A person holding no grant with the permission still gets 403 and a log row. |
| 3 | **Verified, no change** | The scope clause is built in C#. Could a client influence it? | The column comes from the catalogue (bracket-quoted through `Q`), the family from a fixed C# list, the user id and permission code are parameters. No query-string value enters the clause. |
| 4 | **Verified, no change** | On a mixed-kind view (`SubjectEntityId` with a `SubjectKind` column) a single-entity read takes the kind from the query string. A client could name a kind of its choosing. | `fHasPermission` places only the kinds it knows and returns 0 for the rest; a wrong-but-known kind fails its own lookup. Probed on the V2 database: an invented kind returns an empty result, never a row. Fail-closed. |
| 5 | **Verified, no change** | Writes name their subject through the map's typed keys (`ParentEntityId` → Node, …). A client could omit the key. | With no subject the decision is class-only, which a scoped grant never covers (finding 7 of W1). A Global holder is unaffected. The W2 smoke shows a Hydro write under the Transmission building refused. |
| 6 | **Low** | SID registration writes `security.AlternateKey` on first Windows sign-in, attributed to the user. Could a spoofed SID be registered? | The SID comes from `WindowsIdentity.User`, set by IIS from the Kerberos/NTLM token; it is never read from a header. DEV mode has no SID and never writes one. The write is logged `Administrative`. A future account re-created with the same name gets a different SID and is then found by name, which re-registers the new SID beside the old — W3 should decide whether a second SID on one user is an error; recorded in the open questions. |
| 7 | **Low** | `fHoldsPermission` and `fReadableSubjects` repeat the role-gathering of `fHasPermission` (grants to the user or its groups, delegations in force). Three copies of one rule. | Recorded as debt: a shared inline `security.fRolesInForce` would remove it. Not done in W2 to keep the carried function's shape; the three are tested by the same smoke. |
| 8 | **Measured** | Cost of scoped list reads (NFR-2). | On the V2 database (75 registered assets, 151 nodes, 80 records) as the Hydro engineer: asset/vAsset 32 ms, location/vNode 31 ms, record/vRecord 33 ms; Administrator and ReadOnly comparable. Well inside the one-second budget; to be re-measured on the W7 estate. |

## What was not found

- No SQL text from client values, as in W1 (every `CommandText` re-read after the change).
- No role or scope logic in C#: the API contributes the subject column, the family and the parameters; every decision is a database function.
- No path by which a scoped user reaches a row outside scope through a child view: `vPlacement` (scoped by `AssetEntityId`) shows only the Hydro placement in the smoke; views without any subject column stay class-decided (Global only).
