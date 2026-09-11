# Contractual Baseline — NB Power P&C Platform

**Project:** VGS-PRJ-2026-001 · **Client:** New Brunswick Power · **Supplier:** Verner Grid Systems Inc.

Structured extract of the two governing documents. This file is **reference, not proposal** —
it records what was agreed, so design work can be checked against it. Do not edit to reflect
intent; edit only to correct a misreading of the source.

| Source | Location |
|---|---|
| NB Power Scope of Work | `NBP P&C Integration Project - Scope of Work.docx` |
| VGS Proposal (2026-06-29) | SharePoint › Sales & Proposals › PNC Platform (VGS-PRJ-2026-001) |

## Governance rule

**Phase 1 SOW requirements are binding and adhered to as written.**

**Phases 2–5:** the SOW definitions are the baseline. VGS may recommend re-sequencing or
modification where it serves the overall project, but any recommendation to *not* meet a
stated later-phase requirement must carry a documented rationale. Nothing is silently dropped —
see `docs/vision/capability-traceability.md`.

## Commercial

| Item | Value |
|---|---|
| Fixed price | $48,000 CAD, HST excluded |
| Rate basis | $150/hour CAD |
| Effort basis | ~180–240 hours (Phase 1a baseline ~80 h + ~104–163 h added deliverables) |
| Timeline | Phase 1 within **four weeks of project start** |
| Status | **Not started** — ahead of schedule as of 2026-08-30 |

## Phase definitions

| Phase | SOW (governing) | VGS Proposal (diverges from P2 on) |
|---|---|---|
| 1 | Relay Settings Book and Workflows | Platform foundation, Relay Settings Book, workflows, document control, migration, integration readiness |
| 2 | Settings & Configuration Automation and Logic Exports | Asset management, installed-base, lifecycle, replacement planning |
| 3 | Asset Management | System/line modelling, mapping, ASPEN export, validation |
| 4 | Compliance | Event warehouse, event viewing, timeline reconstruction, fault location |
| 5 | Line Constants and Event Recording Analysis | Engineering analytics, model validation, issue reporting |

Phase 1 aligns. **Phases 2–5 diverge** — unresolved, and the reconciliation is a vision-doc output.

### SOW minimum contents, later phases

- **P2** — automated settings-template generation; relay config file import/export; logic extraction from vendor tools; logic comparison and change tracking; reduced manual settings prep; standardized engineering outputs.
- **P3** — asset lifecycle for P&C devices and panels; installed base; model standardization; replacement/obsolescence tracking; maintenance and spares linkage; condition/risk attributes.
- **P4** — compliance evidence retention; traceable approvals; settings verification records; audit reporting; retention/archival controls; standards linkage; audit readiness.
- **P5** — line constants linkage; event/disturbance record storage and retrieval; event analysis tools; correlation of relay operation with settings and model; misoperation review workflows; incident and protection-performance reporting.

## Phase 1 requirements (binding)

### Architecture (§5.2)
- Microsoft SQL Server central repository; designed for scalability, referential integrity, auditability, and integration with Phases 2–5; single authoritative source within the application boundary.
- Web browser UI for **all** end-user access; filtering, search and navigation by station, terminal, asset, functional location, protection scheme, device type.
- NB Power **Active Directory** authentication; role-based access control.

### The seven account types (§5.2.3)
Administrator · Transmission P&C Engineer · Distribution P&C Engineer · Hydro Generation Engineer · Belledune Generation Engineer · Coleson Generation Engineer · P&C Technician

Each with configurable read / modify / approve / archive / report permissions. Scope spans
**Transmission, Distribution and Generation**.

### Data model (§5.3)
- **Cascade functional locations** as primary enterprise-aligned identifier where applicable.
- A **conversion/cross-reference table** for P&C-specific functional locations where enterprise FLocs are insufficiently granular.
- Hierarchy: region → station/site → substation/terminal/generating station → panel/cubicle → relay/device → protection function → associated documents and settings files.
- Structured relationships across site, FLoc, P&C FLoc, device, settings documents, issued revisions, workflow status, approvals, document history, manufacturer/model/firmware, logic/config files, drawings, external system references.
- Integration readiness for **Cascade, SAP, ASPEN OneLiner, Line Constants** — implementable "without fundamental redesign".

### Relay Settings Book (§5.4)
Controlled repository for active, historical and archived settings documentation. Each relay record
stores or references: station/site, FLoc, P&C FLoc, equipment type, protection application,
manufacturer, model, serial, firmware revision, settings documents, issue status, effective date,
revision number, approval history, related drawings, logic/config files, workflow status,
retired/replaced relationships.

**Cradle-to-grave history** — creation, revisions, reviews, approvals, issuance, implementation
status, superseded versions, replacement/retirement, archival, user audit trail, document versions
and timestamps. *No previously approved or issued record may be overwritten in a way that removes
traceability.*

### Document management (§5.5)
- Modify-rights users author in **Word (.docx)**; read-only users view **PDF**.
- System maintains the source ↔ published-PDF relationship.
- Version control: document ID, revision number, issue/effective date, author, reviewer, approver, superseded status, archived status, revision comments.
- **Controlled publishing** — working documents are not automatically issued records; only approved and published documents appear as controlled PDFs to read-only users.

### Workflow (§5.6)
- Minimum states: **Active** · **Outstanding** · **Archive**. *(Note: the practice app used "In Service" rather than "Active"; acceptance tests the SOW wording.)*
- Must be **expandable** to Draft, In Review, Approved, Issued, Implemented, Superseded, Retired, Pending Field Verification — designed in even if not enabled at deployment.
- Future support for assigned actions, due dates, status dashboards, pending-review notification, overdue reporting.

### Geographic mapping (§5.7) — in scope, on the acceptance path
Graphical map identifying terminals, substations and generating stations. Must display sites
geographically, allow selection to view related P&C records, support navigation to station/site
records, filter by facility type/region/operating area, and be designed for future expansion to
asset counts, status indicators and work backlog by location.

### Administration (§5.10)
User role assignment · permission management · workflow configuration · document template
administration · reference data management · audit log access · system configuration · integration
monitoring. **Administrative actions shall be logged and traceable.**

### Data migration (§5.11)
Strategy covering source repository review, required metadata, mapping rules, duplicate handling,
validation, retention of historical revisions, and handling of incomplete/inconsistent records.
Assumptions, limitations and required NB Power support must be identified.

## Phase 1 acceptance criteria (§5.12)

1. Successful Active Directory authentication
2. Correct enforcement of role-based permissions
3. Successful creation and retrieval of relay settings records
4. Storage and controlled presentation of Word and PDF documents
5. Correct operation of **Active, Outstanding and Archive** workflows
6. Complete audit trail for changes to relay records
7. **Successful display and navigation of the geographic map**
8. Successful demonstration of functional location cross-reference capability
9. Acceptable performance and system stability during agreed test scenarios

Testing required: unit, system, integration, UAT, security/access validation, workflow, document
control, and performance appropriate to the architecture.

## Phase 1 deliverables (§5.13) — nineteen

| # | Deliverable |
|---:|---|
| 1 | Requirements specification |
| 2 | Functional design document |
| 3 | Technical architecture document |
| 4 | SQL Server database design and schema |
| 5 | Web application design and deployment architecture |
| 6 | Role and permissions matrix |
| 7 | Workflow design document |
| 8 | Data model including functional location conversion logic |
| 9 | Integration design specification |
| 10 | Document control and revision management design |
| 11 | Geographic mapping design |
| 12 | Test plans and test results |
| 13 | Data migration plan |
| 14 | User training materials |
| 15 | Administrator training materials |
| 16 | Operations and support documentation |
| 17 | Deployed and tested Phase 1 solution |
| 18 | Comprehensive Database Architecture Diagram Package |
| 19 | Comprehensive Database Documentation Package (§5.14) |

### §5.14 Database Documentation Package
Executive summary and architecture (including **DEV / QA / PROD** environment structure and
connection strategies) · logical and physical ERDs with PKs, FKs, cardinality, dependencies ·
searchable data dictionary (types, nullability, defaults, indexing, keys, validation rules) ·
programmable objects catalog (procedures, UDFs, triggers, views — purpose, I/O, dependencies,
logic) · data governance and security protocols (RBAC structure, segregation of duties, masking,
classification, retention, purge) · operational runbook (deployment, schema migration and version
control, CI/CD, backup/restore, DR, performance monitoring, maintenance).

Delivered as Word and/or PDF **plus native diagram files (Visio or approved equivalent)**,
version-controlled and matching the implemented system exactly.

## Key design principles (§9)

Single source of truth · traceability · controlled document management · security by role ·
auditability · scalability · integration readiness · engineering practicality · long-term
maintainability.

## Exclusions (§10, proposal §9)

Full real-time bi-directional enterprise integration on initial deployment · replacement of
enterprise asset-management systems · wholesale migration of historical records without agreed
cleansing rules · advanced analytics/AI/automatic settings generation in Phase 1 · mobile
application development · hardware and infrastructure procurement · live integrations except by
written change order · changes to NB Power security, retention or infrastructure policies.

## Obligations that shape how we work

- **§7** — VGS shall *lead requirements workshops with NB Power stakeholders*. Internal design work prepares for these; it does not replace them.
- **§8** — NB Power provides stakeholder access, legacy records, enterprise system access, AD integration support, infrastructure standards, UAT participation, and timely decisions.
- **§7** — solution designed for maintainability and future expansion; industry-standard development, testing and documentation practice; knowledge transfer to NB Power personnel.

## Known open items

1. **Phases 2–5 divergence** between SOW and proposal — reconciliation required, with rationale.
2. **Workflow state naming** — "Active" (SOW) vs "In Service" (practice app). Acceptance tests SOW wording.
3. **Deployment topology** — which components sit in Business / DMZ / OT, and how ~50 users reach the application. Unresolved; a vision-doc output.
4. **DEV/QA/PROD** — three environments are documentation-mandated; their placement in a CIP-scoped network is undecided.
