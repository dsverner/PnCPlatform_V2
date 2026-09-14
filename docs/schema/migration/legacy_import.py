"""
W7 — the legacy relay-settings database (dbRelayManagement_Legacy, 9 tables, 48 706 rows) into the platform, one rule
per row of docs/migration/CUTOVER-STRATEGY.md §5 (decisions #31, #34, #56, #58–#62, #72, #137–#143). Writes only through
the deployed procedures with @MigrationRunId, one migration.Provenance row per target row, idempotent on
(target, SourceKey, hash), flags never repairs (common.py, carried from the predecessor under #137).

    python legacy_import.py [--database PnCPlatform_V2_DEV] [--limit N] [--report path]

Stages, in order (each stage's source keys and rules are in MIGRATION-PLAN.md §5 and repeated in the code):
  1 persons        Users → personnel.Person (no accounts, no passwords — #143)
  2 manufacturers  MANUFACTURER → party.Entity + ref.Manufacturer (mappings/manufacturer.csv, else the label)
  3 models         (manufacturer, DEVICE label) → ref.Model (mappings/device_model.csv, else the label; technology flagged)
  4 locations      LOCATIONS + SETTINGS.LOCATION → Station under its division (USERNAME → division, #139), one placeholder
                   Building, one Panel per distinct (station, EQUIPMENT)
  5 devices        one base number (OLD_NO minus prefix) → DevicePosition (named from FUNCTIONS), asset.Asset + device.Device,
                   Installed there, LegacyRecordNumber and SerialNumber keys, ProtectionFunction nodes from the ANSI code in FUNCTIONS
  6 requests       one work.WorkRequest per distinct Change Request ID of the A/M/P rows (header row → type, requester, SAP;
                   the software track's non-NA rows → notes, #58); LegacyChangeRequestNumber / SapWorkOrder keys
  7 revisions      each A/M/P row in ascending CR per base → a SettingsText configuration-file revision from SET1 (#61, #140):
                   P Superseded with its in-service period, A Issued and in service now, M Draft; a record per revision
  8 landings       each M row → process.LandMigratedInstance at COMPLETION with the two tracks (#56, #141)
  9 findings       the 17 chains where an archived CR exceeds the active CR → record.Finding (#59, #142)
 10 report         the reconciliation: every input row under exactly one rule; totals; flags
"""
import argparse, csv, datetime, json, os, re, sys, time
from collections import Counter, defaultdict, OrderedDict
import pyodbc
import common
from common import Run, row_hash, s as strip

SOURCE = "dbRelayManagement_Legacy"
CAPTURE_AT = datetime.datetime(2026, 4, 22)          # dbRelayManagement_legacy.bak on Z:\Reference\SqlBackup (MIGRATION-PLAN §2)
SENTINEL = datetime.datetime(1899, 12, 30)           # the empty-date sentinel (#62)
HERE = os.path.dirname(os.path.abspath(__file__))
TZ = " -03:00"

# USERNAME group → division (decision #139, defaults pending the owner's W7 card)
DIVISION_OF = {"Hydro": "Generation · Hydro", "CCove": "Generation · Coleson", "Gen": "Generation · Belledune", "Dist": "Distribution", "Eng": "Transmission"}
# a manufacturer whose relays are microprocessor-based by default (flagged TechnologyAssumed on every model not in the CSV)
MICRO = {"SEL", "GE", "ERLPHASE", "BECKWITH", "BASLER", "STARTCO", "LITTELFUSE", "IGARD", "ABB", "SIEMENS", "SCHNEIDER", "AREVA", "ALSTOM", "MULTILIN"}
WORKTYPE_OF = {"Change Order": "SETTINGS_CHANGE", "Add Order": "SETTINGS_ADD", "Delete Order": "SETTINGS_DELETE", "Verify Order": "SETTINGS_VERIFY"}
ANSI_RE = re.compile(r"\((\d{2}[A-Z0-9/\-]*)\)")   # "(64TG)", "(21-A)", "(50/51)" inside FUNCTIONS


def dto(d):
    """A legacy datetime as the platform's datetimeoffset text; (None, quality 2, flag) for null, sentinel, pre-1950 or future."""
    if d is None:
        return None, 2, "DateNull"
    if d == SENTINEL or d.year == 1899:
        return None, 2, "DateSentinel"
    if d.year < 1950:
        return None, 2, "DateBefore1950"
    if d > datetime.datetime.now():
        return None, 2, "DateInFuture"
    return d.strftime("%Y-%m-%d %H:%M:%S") + TZ, 0, None


def capture_at():
    return CAPTURE_AT.strftime("%Y-%m-%d %H:%M:%S") + TZ


def read_csv(name):
    p = os.path.join(HERE, "mappings", name)
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


class Importer:
    def __init__(self, run, limit=None, source_db=None):
        self.run = run
        self.limit = limit
        self.src = common.connect(source_db or SOURCE).cursor()   # W8: the cutover rehearsal reads the client's copy; provenance still names SOURCE
        self.rules = Counter()               # reconciliation: rule → rows
        self.examples = defaultdict(list)
        self.persons = {}                    # display name → person entity
        self.manufacturers = {}              # short code → ManufacturerId
        self.models = {}                     # (short code, label) → ModelId
        self.divisions = {}
        self.stations = {}                   # location name → station node
        self.buildings = {}
        self.panels = {}                     # (location, equipment) → panel node
        self.bases = {}                      # base → dict(asset, position, rep row)
        self.requests = {}                   # CR → work request entity
        self.request_scope = {}
        self.ansi = set()
        self.worktypes = {}
        self.t0 = time.time()

    # ------------------------------------------------------------------ helpers
    def rule(self, name, key=None, n=1):
        self.rules[name] += n
        if key is not None and len(self.examples[name]) < 5:
            self.examples[name].append(key)

    def src_rows(self, sql, *p):
        return self.src.execute(sql, *p).fetchall()

    def log(self, msg):
        print(f"  [{time.time() - self.t0:6.0f}s] {msg}", flush=True)

    # ------------------------------------------------------------------ 0 target lookups
    def prepare(self):
        r = self.run
        for name, eid in r.rows("SELECT Name, EntityId FROM location.vNode WHERE NodeTypeCode = N'Division'"):
            self.divisions[name] = str(eid)
        missing = [d for d in set(DIVISION_OF.values()) if d not in self.divisions]
        if missing:
            sys.exit(f"divisions not seeded on the target: {missing}")
        for key in set(WORKTYPE_OF.values()):
            v = r.one("""SELECT TOP (1) v.RowId FROM config.vDefinitionVersion v JOIN config.vDefinition d ON d.EntityId = v.DefinitionEntityId
                         WHERE d.DefinitionKind = N'Program.WorkType' AND d.DefinitionKey = ? AND v.Status = N'Effective' ORDER BY v.VersionNumber DESC""", key)
            if v is None:
                sys.exit(f"work type {key} has no Effective version (Seed_config_WorkTypes.sql)")
            self.worktypes[key] = str(v)
        for code, in r.rows("SELECT AnsiCode FROM ref.vAnsiFunction"):
            self.ansi.add(code)
        for sc, mid in r.rows("SELECT ShortCode, ManufacturerId FROM ref.vManufacturer"):
            self.manufacturers[sc.upper()] = str(mid)
        for code, mid, mfr in r.rows("SELECT m.ModelCode, m.ModelId, mf.ShortCode FROM ref.vModel m JOIN ref.vManufacturer mf ON mf.ManufacturerId = m.ManufacturerId"):
            self.models[(mfr.upper(), code.upper())] = str(mid)
        if r.one("SELECT COUNT(*) FROM ref.vAssetType WHERE AssetTypeCode = N'ProtectiveRelay'") == 0:
            sys.exit("asset type ProtectiveRelay is not seeded")
        r.exec("ref.AssetType_Upsert", AssetTypeCode="CONTROL_SWITCH", Name="Control switch", Description="Legacy DEVICE = CONTROL SWITCH (mappings/asset_type.csv)", AssetClassCode="Secondary", IsDevice=0)
        if ("ref", "AssetType", "AssetType:CONTROL_SWITCH") not in r._existing:
            r.provenance("ref", "AssetType", "AssetType:CONTROL_SWITCH", row_hash("AssetType", "CONTROL_SWITCH"))

    # ------------------------------------------------------------------ 1 persons (#143)
    def persons_stage(self):
        rows = self.src_rows("SELECT [User], [User Level] FROM dbo.Users")
        for name, level in rows:
            name = strip(name)
            if not name:
                self.rule("Users: empty name, not migrated", "(blank)"); continue
            h = row_hash("User", name, level)
            key = f"User:{name}"
            done = self.run.already_loaded("personnel", "Person", key, h)
            if done:
                self.persons[name.lower()] = done[0]; self.rule("Users → personnel.Person", name); continue
            eid = self.run.existing_entity("personnel", "Person", key)
            if eid is None:
                parts = name.split()
                first, last = (parts[0], " ".join(parts[1:])) if len(parts) > 1 else (name, "")
                (eid, rid) = self.run.exec("personnel.Person_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                           FirstName=first[:100], LastName=(last or "—")[:100], DisplayName=name[:200], IsSystemAccount=0,
                                           Notes=f"Migrated from the legacy Users table (level {strip(level)}); the stored password was not migrated (#143).")
                self.run.provenance("personnel", "Person", key, h, entity_id=eid, row_id=rid)
            self.persons[name.lower()] = eid
            self.rule("Users → personnel.Person", name)

    # ------------------------------------------------------------------ 2 manufacturers
    def manufacturers_stage(self):
        mapping = {m["legacy_manufacturer"].strip().upper(): m for m in read_csv("manufacturer.csv")}
        labels = [strip(x[0]) for x in self.src_rows("SELECT DISTINCT MANUFACTURER FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P')")]
        labels = sorted({l for l in labels if l} | {"UNKNOWN"})
        self.mfr_of_label = {}
        for label in labels:
            m = mapping.get(label.upper())
            short = (m["manufacturer_short_code"] if m else re.sub(r"[^A-Z0-9]", "", label.upper())[:20] or "UNKNOWN")
            name = (m["manufacturer_name"] or label) if m else label
            self.mfr_of_label[label.upper()] = short
            if short.upper() in self.manufacturers:
                self.rule("MANUFACTURER → ref.Manufacturer (existing)", label); continue
            key = f"Manufacturer:{short}"
            h = row_hash("Manufacturer", short, name)
            ekey = f"Entity:Manufacturer:{short}"
            if self.run.already_loaded("ref", "Manufacturer", key, h):
                mid = self.run.existing_entity("ref", "Manufacturer", key); self.manufacturers[short.upper()] = mid
                if ("party", "Entity", ekey) not in self.run._existing:   # W8 (#156): the entity written without provenance by an earlier run
                    r = self.run.rows("SELECT e.EntityId, e.RowId FROM ref.vManufacturer m JOIN party.vEntity e ON e.EntityId = m.EntityEntityId WHERE m.ManufacturerId = ?", mid)
                    if r: self.run.provenance("party", "Entity", ekey, row_hash("Entity", short, name), entity_id=str(r[0][0]), row_id=str(r[0][1]))
                continue
            (entity, erow) = self.run.exec("party.Entity_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], Name=name[:200], ShortName=short[:40], EntityKind="Manufacturer")
            self.run.provenance("party", "Entity", ekey, row_hash("Entity", short, name), entity_id=entity, row_id=erow)
            mid = str(__import__("uuid").uuid4())
            self.run.exec("ref.Manufacturer_Upsert", ManufacturerId=mid, EntityEntityId=entity, ShortCode=short[:20])
            self.run.provenance("ref", "Manufacturer", key, h, entity_id=mid, notes=None if m else self.run.flag("ManufacturerFromLabel", f"'{label}' is not in mappings/manufacturer.csv; created as found", label))
            self.manufacturers[short.upper()] = mid
            self.rule("MANUFACTURER → ref.Manufacturer (created)", label)

    # ------------------------------------------------------------------ 3 models
    def models_stage(self):
        mapping = {}
        for m in read_csv("device_model.csv"):
            # the CSV's basis text carries unquoted commas, which shifts the trailing columns: keep only values that are plausible
            sc = (m.get("manufacturer_short_code") or "").strip()
            m["manufacturer_short_code"] = sc if re.fullmatch(r"[A-Z0-9]{1,20}", sc) else ""
            t = (m.get("technology") or "").strip()
            m["technology"] = t if t in ("Electromechanical", "Static", "Microprocessor", "IEC61850") else ""
            n = (m.get("model_name") or "").strip()
            m["model_name"] = n if n and not n.lower().startswith("owner ") else ""
            mapping[m["legacy_device"].strip().upper()] = m
        rows = self.src_rows("SELECT DISTINCT LTRIM(RTRIM(MANUFACTURER)), LTRIM(RTRIM(DEVICE)) FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P')")
        self.model_of = {}
        for mfr, label in rows:
            mfr = strip(mfr) or "UNKNOWN"; label = strip(label) or "UNKNOWN DEVICE"
            short = self.mfr_of_label.get(mfr.upper(), "UNKNOWN")
            m = mapping.get(label.upper())
            if m and m.get("manufacturer_short_code"):
                short = m["manufacturer_short_code"]
            code = (m["model_code"] if m else label)[:100]
            name = (m.get("model_name") or label if m else label)[:200]
            is_switch = label.upper() == "CONTROL SWITCH"
            tech = (m.get("technology") if m else None) or ("Microprocessor" if short.upper() in MICRO else "Electromechanical")
            k = (short.upper(), code.upper())
            self.model_of[(mfr.upper(), label.upper())] = (k, is_switch)
            if k not in self.models:
                # W8 (#153): a model the platform already carries — seeded with its template before the load — is reused, never duplicated
                r = self.run.rows("SELECT TOP (1) m.ModelId FROM ref.vModel m JOIN ref.vManufacturer mf ON mf.ManufacturerId = m.ManufacturerId WHERE mf.ShortCode = ? AND m.ModelCode = ?", short, code)
                if r:
                    self.models[k] = str(r[0][0])
            if k in self.models:
                self.rule("DEVICE → ref.Model (existing)", label); continue
            key = f"Model:{short}:{code}"
            h = row_hash("Model", short, code, name, tech)
            done = self.run.already_loaded("ref", "Model", key, h)
            if done:
                self.models[k] = done[0]; continue
            mid = self.run.existing_entity("ref", "Model", key) or str(__import__("uuid").uuid4())
            self.run.exec("ref.Model_Upsert", ModelId=mid, ManufacturerId=self.manufacturers[short.upper()], ModelCode=code, ModelName=name,
                          AssetTypeCode="CONTROL_SWITCH" if is_switch else "ProtectiveRelay", DeviceCategory=None if is_switch else "Relay", Technology=tech)
            flag = None if (m and m.get("technology")) else self.run.flag("TechnologyAssumed", f"'{label}' ({mfr}) technology {tech} assumed from the manufacturer; the owner's W7 card decides", label)
            self.run.provenance("ref", "Model", key, h, entity_id=mid, notes=flag)
            self.models[k] = mid
            self.rule("DEVICE → ref.Model (created)", label)

    # ------------------------------------------------------------------ 4 locations (#139)
    def node(self, kind, parent, name, key, notes=None, subtype=None):
        h = row_hash(kind, parent, name)
        done = self.run.already_loaded("location", "Node", key, h)
        if done:
            return done[0]
        eid = self.run.existing_entity("location", "Node", key)
        if eid is None:
            (eid, rid) = self.run.exec("location.AddNode", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                       NodeTypeCode=kind, ParentEntityId=parent, Name=name[:200], SubtypeCode=subtype, Notes=notes,
                                       ValidFrom=capture_at(), ValidFromQuality=2)
            self.run.provenance("location", "Node", key, h, entity_id=eid, row_id=rid)
        return eid

    def locations_stage(self):
        groups = defaultdict(Counter)
        for loc, user in self.src_rows("SELECT LTRIM(RTRIM(Location)), LTRIM(RTRIM(USERNAME)) FROM dbo.LOCATIONS"):
            u = strip(user) or "?"
            u = {"eng": "Eng", "dist": "Dist", "gen": "Gen", "hydro": "Hydro", "ccove": "CCove"}.get(u.lower(), u)   # 'eng' and 'Eng' are one group
            groups[strip(loc)][u] += 1
            self.rule("LOCATIONS row → its station's USERNAME groups", loc)
        stnum = {m["legacy_location"].strip().upper(): m["asset_number"].strip() for m in read_csv("station_asset_number.csv")}
        # W8 card A (owner, 2026-09-13; #153): the owner of each station — Transmission / Generation / Distribution (and later
        # Industrial or a merchant owner) — is the owner's markup, not the USERNAME group; a division the mapping names that
        # the tree lacks is created under NB Power
        owner_of_station = {m["legacy_location"].strip().upper(): m["owner"].strip() for m in read_csv("station_owner.csv") if m.get("owner")}
        used = Counter(); owner_of = {}
        for loc, asset, n in self.src_rows("SELECT LTRIM(RTRIM(LOCATION)), ASSET, COUNT(*) FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P') GROUP BY LTRIM(RTRIM(LOCATION)), ASSET"):
            used[(strip(loc), asset)] = n
        settings_locs = {l for (l, _) in used}
        for loc in sorted(set(groups) | settings_locs):
            if not loc:
                continue
            g = groups.get(loc)
            flags = []
            if g:
                user, _ = g.most_common(1)[0]
                if len(g) > 1:
                    flags.append(self.run.flag("StationGroupConflict", f"'{loc}' is listed under {dict(g)}; the most frequent group placed it", loc))
            else:
                user = "Eng"; flags.append(self.run.flag("StationNotInLocations", f"'{loc}' appears in SETTINGS but not in LOCATIONS; placed under Transmission", loc))
            division = DIVISION_OF.get(user)
            if division is None:
                division = "Transmission"; flags.append(self.run.flag("StationGroupUnknown", f"'{loc}' group '{user}' has no division mapping; placed under Transmission", loc))
            marked = owner_of_station.get(loc.upper())
            if marked:
                division = marked; flags = [f for f in flags if "StationGroupConflict" not in f]
                if division not in self.divisions:
                    # a merchant owner named in the markup (TransAlta, Caribou Wind Farm — Owner nodes seeded W8) places the station under
                    # that owner's Generation division; any other name is a division under NB Power, created if the tree lacks it
                    merchant = self.run.rows("SELECT TOP (1) d.EntityId FROM location.vNode o JOIN location.vNode d ON d.ParentEntityId = o.EntityId AND d.NodeTypeCode = N'Division' AND d.Name = N'Generation' WHERE o.NodeTypeCode = N'Owner' AND o.Name = ?", division)
                    if merchant:
                        self.divisions[division] = str(merchant[0][0])
                    else:
                        owner = self.run.rows("SELECT TOP (1) EntityId FROM location.vNode WHERE NodeTypeCode = N'Owner' AND Name = N'NB Power'")[0][0]
                        self.divisions[division] = self.node("Division", str(owner), division, f"Division:{division}", notes="Created for the owner's station markup (W8 card A, #153)")
                self.rule("station placed under the owner's marked division (card A)", loc)
            # the station's asset number: the owner's mapping, else the dominant SETTINGS.ASSET (flagged)
            number = stnum.get(loc.upper())
            if number is None:
                cands = sorted(((n, a) for (l, a), n in used.items() if l == loc), reverse=True)
                if cands:
                    number = f"{cands[0][1]:04d}"; flags.append(self.run.flag("StationNumberAssumed", f"'{loc}' station number {number} from the dominant SETTINGS.ASSET ({cands[0][0]} rows)", loc))
            st = self.node("Station", self.divisions[division], loc, f"Station:{loc}", notes=self.run.join_flags(*flags))
            self.stations[loc] = st
            if number:
                key = f"StationNumber:{loc}"; h = row_hash("StationNumber", loc, number)
                if not self.run.already_loaded("location", "AlternateKey", key, h) and self.run.existing_entity("location", "AlternateKey", key) is None:
                    try:
                        (e, r) = self.run.exec("location.AlternateKey_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], SubjectEntityId=st, KeyKindCode="StationNumber", KeyValue=number, IsPrimaryLabel=1)
                        self.run.provenance("location", "AlternateKey", key, h, entity_id=e, row_id=r)
                        owner_of[number] = loc
                    except pyodbc.IntegrityError:
                        # a station number is unique in the platform; two legacy locations claim the same one. The owner (W7 card C,
                        # 2026-09-13): "an error in the data that the user must mitigate by correcting them" — so a finding on the
                        # station left without a number, not a silent flag (#148)
                        self.run.flag("StationNumberDuplicate", f"'{loc}' station number {number} already belongs to '{owner_of.get(number, '?')}'; no key written; a finding raised (card C)", loc)
                        self.station_number_finding(st, loc, number, owner_of.get(number))
                else:
                    owner_of.setdefault(number, loc)
            self.buildings[loc] = self.node("Building", st, "Building (unknown — legacy has no buildings)", f"Building:{loc}", notes="Placeholder: the legacy database names no building or room; positions sit under a panel named from EQUIPMENT (#139)")
            self.rule("station created / confirmed", loc)
        for loc, equip in self.src_rows("SELECT DISTINCT LTRIM(RTRIM(LOCATION)), LTRIM(RTRIM(EQUIPMENT)) FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P')"):
            loc = strip(loc); equip = strip(equip) or "(no equipment)"
            if loc not in self.buildings:
                continue
            self.panels[(loc, equip)] = self.node("Panel", self.buildings[loc], equip, f"Panel:{loc}|{equip}")
            self.rule("(LOCATION, EQUIPMENT) → Panel", f"{loc} | {equip}")

    def station_number_finding(self, station, loc, number, other):
        """Owner's W7 card C: a station number two legacy locations claim is a data error for a person to correct — a finding on the station left without one."""
        key = f"Finding:StationNumber:{loc}"; h = row_hash("Finding", "StationNumber", loc, number)
        if self.run.already_loaded("record", "Finding", key, h) or self.run.existing_entity("record", "Finding", key):
            self.rule("duplicate station number → a finding on the station left without one (card C)", loc); return
        desc = f"Legacy location '{loc}' carries station number {number}, which already belongs to '{other or 'another station'}'. A station number is unique in the platform; the owner ruled (W7 card C, 2026-09-13) that the duplicate is a data error to be corrected by a person. This station has no number until then."
        (rec, rrow) = self.run.exec("record.Record_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                    RecordKindCode="Finding", SubjectKind="Node", SubjectEntityId=station, OccurredAt=capture_at(), TimeSourceQuality=4,
                                    PerformedByActorId=self.run.actor_id, OverallResult="Informational", Summary=desc[:1000], ValidFrom=capture_at(), ValidFromQuality=2)
        self.run.exec("record.Finding_Add", EntityId=rec, FindingCategoryCode="MigrationReconciliation", Severity="Major", Description=desc, AsFoundValue=f"station number {number} on two locations", ExpectedValue="one location per station number", ValidFrom=capture_at(), ValidFromQuality=2)
        self.run.provenance("record", "Finding", key, h, entity_id=rec, row_id=rrow)
        self.rule("duplicate station number → a finding on the station left without one (card C)", loc)

    def alt_key(self, subject, kind, value, key, h, primary=False, who=None):
        """An asset alternate key, tolerant of a value another asset already carries (unique per kind in the platform): flagged, not written."""
        if self.run.already_loaded("asset", "AlternateKey", key, h) or self.run.existing_entity("asset", "AlternateKey", key):
            return
        try:
            (e, rr) = self.run.exec("asset.AlternateKey_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], SubjectEntityId=subject, KeyKindCode=kind, KeyValue=value, IsPrimaryLabel=1 if primary else 0)
            self.run.provenance("asset", "AlternateKey", key, h, entity_id=e, row_id=rr)
        except pyodbc.IntegrityError:
            self.run.flag(f"{kind}Duplicate", f"{who}: {kind} '{value}' already belongs to another asset; no key written", who)

    # ------------------------------------------------------------------ 5 devices
    def devices_stage(self):
        cols = "OLD_NO, [Change Request ID], LTRIM(RTRIM(LOCATION)), ASSET, LTRIM(RTRIM(EQUIPMENT)), LTRIM(RTRIM(DEVICE)), LTRIM(RTRIM(FUNCTIONS)), LTRIM(RTRIM(SERIAL_NUMBER)), LTRIM(RTRIM(SOFTWARE_VERSION)), LTRIM(RTRIM(MANUFACTURER)), VOLTAGE"
        rows = self.src_rows(f"SELECT {cols} FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) IN ('A','M','P') ORDER BY SUBSTRING(OLD_NO,2,4), [Change Request ID]")
        chains = OrderedDict()
        for r in rows:
            if r[0][0] != r[0][0].upper():
                self.run.flag("PrefixLowerCase", f"{r[0]}/{r[1]}: the state prefix is lower case; read as {r[0][0].upper()}", r[0])
                r = (r[0][0].upper() + r[0][1:],) + tuple(r[1:])
            chains.setdefault(r[0][1:5], []).append(r)
        if self.limit:
            chains = OrderedDict(list(chains.items())[: self.limit])
        self.chains = chains
        for base, rs in chains.items():
            a = [r for r in rs if r[0][0] == "A"]; m = [r for r in rs if r[0][0] == "M"]
            rep = a[0] if a else (m[-1] if m else rs[-1])
            oldno, cr, loc, asset_no, equip, device, functions, serial, sw, mfr, voltage = rep
            loc = strip(loc); equip = strip(equip) or "(no equipment)"; device = strip(device) or "UNKNOWN DEVICE"; functions = strip(functions); mfr = strip(mfr) or "UNKNOWN"
            flags = []
            if len({(strip(r[2]), strip(r[4]) or "(no equipment)") for r in rs}) > 1:
                flags.append(self.run.flag("ChainLocationVaries", f"base {base}: its rows name more than one (LOCATION, EQUIPMENT); the {oldno} row's is used", base))
            panel = self.panels.get((loc, equip))
            if panel is None:
                self.rule("row of a base with no LOCATION/EQUIPMENT panel: counted, not written", base, n=len(rs)); continue
            posname = (functions or device)[:200]
            position = self.node("DevicePosition", panel, posname, f"Position:{base}", notes=self.run.join_flags(*flags))
            (mk, is_switch) = self.model_of[(mfr.upper(), device.upper())]
            model = self.models[mk]
            status = "InService" if a else ("Planned" if m else "OutOfService")
            key = f"Asset:{base}"
            h = row_hash("Asset", base, device, model, status, serial, sw)
            done = self.run.already_loaded("asset", "Asset", key, h)
            asset = done[0] if done else self.run.existing_entity("asset", "Asset", key)
            if asset is None:
                (asset, arow) = self.run.exec("asset.Asset_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                              AssetTypeCode="CONTROL_SWITCH" if is_switch else "ProtectiveRelay", Name=f"{device} [{base}]"[:200], ModelId=model, Status=status,
                                              VoltageClassCode=None, Notes=(f"Legacy record {oldno}; software version {sw}" if sw else f"Legacy record {oldno}"),
                                              ValidFrom=capture_at(), ValidFromQuality=2)
                self.run.provenance("asset", "Asset", key, h, entity_id=asset, row_id=arow)
                if not is_switch:
                    self.run.exec("device.Device_Add", EntityId=asset, PartNumber=device[:100], ValidFrom=capture_at(), ValidFromQuality=2)
                    self.run.provenance("device", "Device", key, h, entity_id=asset)
                (pl, prow) = self.run.exec("asset.PlaceAsset", outputs=[("PlacementEntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                           AssetEntityId=asset, NodeEntityId=position, PlacementKind="Installed" if not is_switch else "Attached", OccurredAt=capture_at(), ValidFromQuality=2)
                self.run.provenance("asset", "Placement", key, h, entity_id=pl, row_id=prow)
                for no in dict.fromkeys(r[0] for r in rs):      # OLD_NO is not unique across a chain's rows: one key per distinct value
                    self.alt_key(asset, "LegacyRecordNumber", no, f"LegacyRecordNumber:{no}", row_hash("LegacyRecordNumber", no, base), primary=(no == oldno), who=base)
                if serial:
                    self.alt_key(asset, "SerialNumber", serial[:200], f"SerialNumber:{base}", row_hash("SerialNumber", base, serial), who=base)
                # the protection function: the ANSI code in FUNCTIONS, else the text as a node function label
                codes = ANSI_RE.findall(functions or "")
                if codes and not is_switch:
                    for code in dict.fromkeys(codes):
                        if code not in self.ansi:
                            self.run.exec("ref.AnsiFunction_Upsert", AnsiCode=code[:10], Name=(functions or code)[:200]); self.ansi.add(code)
                            if ("ref", "AnsiFunction", f"AnsiFunction:{code[:10]}") not in self.run._existing:
                                self.run.provenance("ref", "AnsiFunction", f"AnsiFunction:{code[:10]}", row_hash("Ansi", code[:10]))
                        fnode = self.node("ProtectionFunction", position, code, f"Function:{base}:{code}")
                        self.run.exec("scheme.CommissionedFunction_Add", ProtectionFunctionNodeEntityId=fnode, AnsiCode=code[:10], IsPrincipal=1 if code == codes[0] else 0, ValidFrom=capture_at(), ValidFromQuality=2)
                        self.run.provenance("scheme", "CommissionedFunction", f"Function:{base}:{code}", row_hash("CF", base, code), entity_id=fnode)
                    self.rule("FUNCTIONS with an ANSI code → ProtectionFunction + CommissionedFunction", base)
                elif functions:
                    nk = f"NodeFunction:{base}"; nh = row_hash("NodeFunction", base, functions[:200])
                    if not self.run.already_loaded("location", "NodeFunction", nk, nh) and self.run.existing_entity("location", "NodeFunction", nk) is None:
                        r = self.run.rows("SELECT TOP (1) EntityId, RowId FROM location.vNodeFunction WHERE NodeEntityId = ? AND FunctionLabel = ?", position, functions[:200])
                        if r:   # written by a run before W8 (#156) without its provenance row
                            self.run.provenance("location", "NodeFunction", nk, nh, entity_id=str(r[0][0]), row_id=str(r[0][1]))
                        else:
                            (ne, nr) = self.run.exec("location.NodeFunction_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], NodeEntityId=position, FunctionLabel=functions[:200], ValidFrom=capture_at(), ValidFromQuality=2)
                            self.run.provenance("location", "NodeFunction", nk, nh, entity_id=ne, row_id=nr)
                    self.rule("FUNCTIONS without an ANSI code → NodeFunction label", base)
            self.bases[base] = {"asset": asset, "position": position, "rep": rep, "rows": rs, "switch": is_switch}
            self.rule("base number → DevicePosition + Asset (+ Device, Installed)", base)
            if len(self.bases) % 500 == 0:
                self.log(f"devices: {len(self.bases)} bases")

    def work_key(self, subject, kind, value, key, h, primary=False, who=None):
        """A work-request alternate key, tolerant of a value another request already carries (one SAP order over several CRs): flagged, not written."""
        if self.run.already_loaded("work", "AlternateKey", key, h) or self.run.existing_entity("work", "AlternateKey", key):
            return True
        try:
            (e, rr) = self.run.exec("work.AlternateKey_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], SubjectEntityId=subject, KeyKindCode=kind, KeyValue=value, IsPrimaryLabel=1 if primary else 0)
            self.run.provenance("work", "AlternateKey", key, h, entity_id=e, row_id=rr)
            return True
        except pyodbc.IntegrityError:
            self.run.flag(f"{kind}Duplicate", f"CR {who}: {kind} '{value}' already belongs to another request; no key written", who)
            return False

    # ------------------------------------------------------------------ 6 requests
    def requests_stage(self):
        header = defaultdict(list)
        for cr, sap, relay, notes, typ, by in self.src_rows("SELECT [Change Request ID], [SAP Work Order Numer], [Relay ID Number], [Notes], [Type], [Reqested By] FROM dbo.[Settings Management]"):
            header[cr].append((strip(sap), strip(relay), strip(notes), strip(typ), strip(by)))
        # the header's duplicate rows (894 CRs) come back in no fixed order: sort them so "the first" is the same row on every
        # copy of the source (the cutover rehearsal's copy returned them permuted and 334 requests were revised for nothing)
        for cr in header:
            header[cr].sort(key=lambda h: tuple(x or "" for x in h))
        self.header = header
        # W7 card H (owner, 2026-09-13): the SETTINGS row's Change Request ID and the header / track rows for the same Relay ID
        # Number name different CRs for most P rows (P0002: 2141435 vs 2144042). The SETTINGS CR stays the change (the chain
        # order is untouched); the header's type, requester and SAP order and the two tracks are taken from the relay's own
        # rows when the CR finds none, and the disagreement is flagged (#148).
        hrel = defaultdict(list)
        for cr, hs in header.items():
            for h in hs:
                if h[1]:
                    hrel[h[1]].append((cr, h))
        self.header_cr = {}
        sw = defaultdict(list)
        for cr, relay, status, notes, date in self.src_rows("SELECT [Change Request ID], [Relay ID Number], [Status], [Notes], [Date] FROM dbo.[Setting Software Management] ORDER BY [Change Request ID], [Relay ID Number], [Date], [Status], [Notes]"):
            sw[(cr, strip(relay))].append((strip(status), strip(notes), date))
        self.tracks = {}; self.tracks_by_relay = defaultdict(list)
        for tbl, name in (("Relay Document Management", "doc"), ("Setting Database Management", "db")):
            for cr, relay, status, notes, date in self.src_rows(f"SELECT [Change Request ID], [Relay ID Number], [Status], [Notes], [Date] FROM dbo.[{tbl}]"):
                self.tracks[(name, cr, strip(relay))] = (strip(status), strip(notes), date)
                self.tracks_by_relay[(name, strip(relay))].append((cr, (strip(status), strip(notes), date)))
                self.rule(f"{tbl} row → a completion-track state on its request", f"{cr}/{relay}")
        by_cr = defaultdict(list)
        for base, b in self.bases.items():
            for r in b["rows"]:
                by_cr[r[1]].append((base, r))
        for cr, items in by_cr.items():
            oldnos = [r[0] for _, r in items]
            hdr = [h for h in header.get(cr, []) if h[1] in oldnos] or header.get(cr, [])
            flags = []
            hcr = cr
            if len(header.get(cr, [])) > 1:
                flags.append(self.run.flag("HeaderDuplicated", f"CR {cr} has {len(header[cr])} header rows; the one naming this chain (else the first) is used", cr))
            if not hdr:
                # card H: the relay's own header rows under another CR — the latest one at or below this CR, else the earliest above it
                cands = sorted({c for o in oldnos for (c, _) in hrel.get(o, []) if c != cr})
                if cands:
                    below = [c for c in cands if c <= cr]
                    hcr = below[-1] if below else cands[0]
                    hdr = [h for (c, h) in hrel[oldnos[0]] if c == hcr]
                    flags.append(self.run.flag("HeaderUnderOtherCr", f"CR {cr}/{oldnos[0]}: no header under this CR; the relay's header under CR {hcr} used ({len(cands)} candidate CR(s)) — card H", cr))
            self.header_cr[cr] = hcr
            h0 = hdr[0] if hdr else None
            typ = h0[3] if h0 else None
            wt = WORKTYPE_OF.get(typ or "")
            if wt is None:
                wt = "SETTINGS_CHANGE"; flags.append(self.run.flag("RequestTypeUnknown" if h0 else "RequestNoHeader", f"CR {cr}: {'type ' + repr(typ) if h0 else 'no Settings Management row'}; work type SETTINGS_CHANGE assumed", cr))
            notes = []
            if h0 and h0[2]:
                notes.append(h0[2])
            for oldno in oldnos:
                for status, text, date in (sw.get((cr, oldno)) or sw.get((hcr, oldno)) or []):
                    if status and status != "NA":
                        notes.append(f"Legacy software track ({oldno}): {status}" + (f" {date:%Y-%m-%d}" if date else "") + (f" — {text}" if text else ""))
                        self.rule("Setting Software Management non-NA row → a note on the request (#58)", f"{cr}/{oldno}")
            requested_by = h0[4] if h0 else None
            person = self.persons.get((requested_by or "").lower())
            if requested_by and not person:
                flags.append(self.run.flag("RequesterNotAUser", f"CR {cr}: requested by '{requested_by}', not in Users", cr))
            if len(items) > 1:
                flags.append(self.run.flag("RequestSpansDevices", f"CR {cr} names {len(items)} devices; scoped to the first", cr))
            first_asset = self.bases[items[0][0]]["asset"]
            key = f"WorkRequest:{cr}"
            h = row_hash("WorkRequest", cr, wt, typ, requested_by, h0[0] if h0 else None, "|".join(oldnos), *([hcr] if hcr != cr else []))   # the pre-card hash when the CR's own header serves
            done = self.run.already_loaded("work", "WorkRequest", key, h)
            wr = done[0] if done else self.run.existing_entity("work", "WorkRequest", key)
            title = f"CR {cr} — {typ or 'settings change'} — {', '.join(oldnos[:6])}"[:200]
            fields = dict(WorkTypeDefinitionVersionRowId=self.worktypes[wt], Title=title, ScopeKind="Asset", ScopeEntityId=first_asset,
                          Description=(f"Requested by {requested_by}" if requested_by else None), Notes=("\n".join(notes) or None), ValidFrom=capture_at(), ValidFromQuality=2)
            if wr is None:
                (wr, rr) = self.run.exec("work.WorkRequest_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")], **fields)
                self.run.provenance("work", "WorkRequest", key, h, entity_id=wr, row_id=rr, notes=self.run.join_flags(*flags))
            elif not done:
                # the rule changed under an existing request (card H: its header found by the relay number): revised in place, a new provenance row
                (rr,) = self.run.exec("work.WorkRequest_Revise", outputs=[("RowId", "UNIQUEIDENTIFIER")], EntityId=wr, **fields)
                self.run.provenance("work", "WorkRequest", key, h, entity_id=wr, row_id=rr, notes=self.run.join_flags(*flags))
                self.rule("work request revised in place under a changed rule (card H)", cr)
            if wr is not None:
                self.work_key(wr, "LegacyChangeRequestNumber", str(cr), f"LegacyChangeRequestNumber:{cr}", row_hash("LCR", cr), primary=True, who=cr)
                if h0 and h0[0]:
                    if self.work_key(wr, "SapWorkOrder", h0[0][:200], f"SapWorkOrder:{cr}", row_hash("SAP", cr, h0[0]), who=cr):
                        self.rule("SAP Work Order Numer → SapWorkOrder key", cr)
            self.requests[cr] = wr
            self.rule("Change Request ID (of an A/M/P row) → work.WorkRequest", cr)
            if h0:
                self.rule("Settings Management row → the request's type, requester, notes", cr)
        # header rows that belong to no A/M/P chain: counted, not written
        for cr, hs in header.items():
            if cr not in by_cr:
                d = self.src.execute("SELECT COUNT(*) FROM dbo.SETTINGS WHERE [Change Request ID] = ? AND LEFT(OLD_NO,1) IN ('D','2')", cr).fetchone()[0]
                self.rule("Settings Management row of a dropped chain (D / 2440): counted, not written" if d else "Settings Management row with no SETTINGS row: counted, not written", cr, n=len(hs))
            elif len(hs) > 1:
                self.rule("Settings Management duplicate row (same CR): folded into its request", cr, n=len(hs) - 1)

    # ------------------------------------------------------------------ 7 revisions (#140)
    def revisions_stage(self):
        n = 0
        for base, b in self.bases.items():
            rows = sorted(b["rows"], key=lambda r: r[1])
            if b["switch"]:
                self.rule("CONTROL SWITCH row: asset only, no configuration file (mappings/asset_type.csv)", base, n=len(rows)); continue
            # keyed by (OLD_NO, CR): a base's P rows share one OLD_NO (1 265 bases, 3 579 rows), and a dict keyed by OLD_NO alone gave
            # every superseded revision the last row's text and dates (found 2026-09-13 on the review rows; #156)
            detail = {(r[0], r[1]): d for d, r in zip(self.src_rows(
                "SELECT SET1, SETTINGS2, DESC1, DESC2, DESC3, DESC4, REMARKS1, REMARKS2, REMARKS3, REMARKS4, REMARKS5, CT_MAIN1, CT_MAIN2, CT_MAIN3, CT_MAIN4, PT_MAIN, CT_AUX1, CT_AUX2, CT_AUX3, CT_AUX4, PT_AUX, CLASS, [USE], RESPONSIBILITY, Bulk_Power_Element, Protection_Group, ELEMENT, LINE_TYPE, [NUMBER OF RELAYS], CDATE, VDATE, [Change Request ID], OLD_NO FROM dbo.SETTINGS WHERE SUBSTRING(OLD_NO,2,4) = ? AND LEFT(OLD_NO,1) IN ('A','M','P') ORDER BY [Change Request ID]", base), rows)}
            prev_in_service = None
            a_cr = next((r[1] for r in rows if r[0][0] == "A"), None)
            for r in rows:
                oldno, cr = r[0], r[1]
                d = detail[(oldno, cr)]
                above_a = a_cr is not None and r[0][0] == "P" and cr > a_cr   # an archived CR above the active one: the finding's chain (#59)
                set1, set2 = d[0], d[1]
                cdate, vdate = d[29], d[30]
                prefix = oldno[0]
                key = f"Revision:{oldno}|{cr}"
                h = row_hash("Revision", oldno, cr, set1, set2, cdate, vdate, *d[2:29])
                done = self.run.already_loaded("document", "ConfigurationFile", key, h)
                existing = done[1] if done else self.run.existing_row("document", "ConfigurationFile", key)
                if existing:
                    # a re-run repairs one thing only: an A/P revision that an earlier run left without an in-service period
                    if prefix == "A" and a_cr is not None and any(x[0][0] == "P" and x[1] > a_cr for x in rows):
                        # the violation chain's A row: if a P row above it closed its period, re-open it (in service from one second after that P's start, quality 2)
                        closed = self.run.one("SELECT CONVERT(NVARCHAR(30), InServiceTo, 120) FROM document.vConfigurationFile WHERE RevisionRowId = ?", existing)
                        if closed is not None:
                            reopen = (datetime.datetime.strptime(closed[:19], "%Y-%m-%d %H:%M:%S") + datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S") + TZ
                            try:
                                self.run.exec("document.SetInService", none=True, RevisionRowId=existing, InServiceFrom=reopen, InServiceFromQuality=2, ActorId=self.run.actor_id)
                                self.run.flag("InServiceRestoredForA", f"{oldno}/{cr}: the A row's period had been closed by an archived row above it; re-opened from {reopen[:19]} (#59)", oldno)
                            except pyodbc.Error as e:
                                self.run.flag("InServiceOrder", f"{oldno}/{cr}: re-open refused ({str(e)[:100]})", oldno)
                        prev_in_service = None
                    elif prefix in ("A", "P") and not above_a:
                        cur = self.run.one("SELECT CONVERT(NVARCHAR(30), InServiceFrom, 120) FROM document.vConfigurationFile WHERE RevisionRowId = ?", existing)
                        if cur is None:
                            isf, isq, _ = dto(vdate)
                            if isf is None:
                                a2, _, _ = dto(cdate); isf = a2 or capture_at(); isq = 2
                            if prev_in_service is not None and isf <= prev_in_service:
                                isf = (datetime.datetime.strptime(prev_in_service[:19], "%Y-%m-%d %H:%M:%S") + datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S") + TZ; isq = 2
                            try:
                                self.run.exec("document.SetInService", none=True, RevisionRowId=existing, InServiceFrom=isf, InServiceFromQuality=isq, ActorId=self.run.actor_id)
                                self.run.flag("InServiceRepaired", f"{oldno}/{cr}: in-service period set on a re-run", oldno)
                                prev_in_service = isf
                            except pyodbc.Error as e:
                                self.run.flag("InServiceOrder", f"{oldno}/{cr}: SetInService refused on re-run ({str(e)[:100]})", oldno)
                        else:
                            prev_in_service = cur[:19] + TZ
                    self.rule({"A": "A row → the current revision, in service now", "P": "P row → a superseded revision with its in-service period", "M": "M row → a Draft revision (the open change)"}[prefix], oldno)
                    n += 1; continue
                flags = []
                at, q, f = dto(cdate)
                if at is None:
                    at2, q2, f2 = dto(vdate)
                    at = at2 or capture_at(); q = 2
                    flags.append(self.run.flag("CalculatedDateUnknown", f"{oldno}/{cr}: CDATE {f}; {'VDATE used' if at2 else 'capture date used'}", oldno))
                text = strip(set1)
                if not text:
                    flags.append(self.run.flag("NoSettingsText", f"{oldno}/{cr}: SET1 is empty; an empty settings file was written", oldno))
                status = {"A": "Issued", "P": "Superseded", "M": "Draft"}[prefix]
                (rev, kind) = self.run.exec("process.WriteConfigurationRevision", outputs=[("RevisionRowId", "UNIQUEIDENTIFIER"), ("FileKind", "NVARCHAR(20)")],
                                            DeviceEntityId=b["asset"], CaptureKind="Designed", FileName=f"{oldno}_{cr}.txt", MimeType="text/plain; charset=utf-8",
                                            Content=(text or "").encode("utf-8"), TextContent=None, At=at, FileKindOverride="SettingsText", Status=status)
                # in service: P from its VDATE until the next revision's; A from its VDATE, open (#140); M never;
                # a P row above the A row's CR (the 17 violation chains, #59) is never put in service — the letters say A is active
                if above_a:
                    flags.append(self.run.flag("InServiceViolationChain", f"{oldno}/{cr}: archived row above the active row's CR {a_cr}; left without an in-service period (the finding rules)", oldno))
                elif prefix in ("A", "P"):
                    isf, isq, isflag = dto(vdate)
                    if isf is None:
                        isf = at; isq = 2
                        flags.append(self.run.flag("VerifiedDateUnknown", f"{oldno}/{cr}: VDATE {isflag}; in service from the calculated date, quality 2", oldno))
                    # the chain orders by CR, not by VDATE (§5): a revision whose VDATE is not after the prior period's start
                    # (several revisions share a VDATE; the 17 violations) goes in service one second after it, quality 2, flagged
                    if prev_in_service is not None and isf <= prev_in_service:
                        bumped = (datetime.datetime.strptime(prev_in_service[:19], "%Y-%m-%d %H:%M:%S") + datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S") + TZ
                        flags.append(self.run.flag("InServiceDateAdjusted", f"{oldno}/{cr}: VDATE {isf[:10]} is not after the prior revision's {prev_in_service[:10]}; in service from {bumped[:19]}, quality 2", oldno))
                        isf = bumped; isq = 2
                    try:
                        self.run.exec("document.SetInService", none=True, RevisionRowId=rev, InServiceFrom=isf, InServiceFromQuality=isq, ActorId=self.run.actor_id)
                        prev_in_service = isf
                    except pyodbc.Error as e:
                        flags.append(self.run.flag("InServiceOrder", f"{oldno}/{cr}: SetInService refused ({str(e)[:120]}); left with no in-service period", oldno))
                # the overflow columns as the record's summary (#140: notes, not characteristics — W7 default)
                labels = ["SETTINGS2", "DESC1", "DESC2", "DESC3", "DESC4", "REMARKS1", "REMARKS2", "REMARKS3", "REMARKS4", "REMARKS5", "CT_MAIN1", "CT_MAIN2", "CT_MAIN3", "CT_MAIN4", "PT_MAIN", "CT_AUX1", "CT_AUX2", "CT_AUX3", "CT_AUX4", "PT_AUX", "CLASS", "USE", "RESPONSIBILITY", "Bulk_Power_Element", "Protection_Group", "ELEMENT", "LINE_TYPE", "NUMBER OF RELAYS"]
                extra = "; ".join(f"{l}={strip(v)}" for l, v in zip(labels, d[1:29]) if strip(v) not in (None, "", "0", "False"))
                summary = f"Legacy {oldno}, CR {cr}" + (f"; {extra}" if extra else "")
                (rec, rrow) = self.run.exec("record.Record_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                            RecordKindCode="ConfigurationFileRevision", SubjectKind="Device", SubjectEntityId=b["asset"], SecondSubjectKind="ConfigurationFileRevision", SecondSubjectEntityId=rev,
                                            WorkRequestEntityId=self.requests.get(cr), OccurredAt=at, TimeSourceQuality=4 if q else 3, PerformedByActorId=self.run.actor_id, Summary=summary[:1000],
                                            ValidFrom=at, ValidFromQuality=q)
                self.run.provenance("document", "ConfigurationFile", key, h, row_id=rev, notes=self.run.join_flags(*flags))
                self.run.provenance("record", "Record", key, h, entity_id=rec, row_id=rrow)
                self.rule({"A": "A row → the current revision, in service now", "P": "P row → a superseded revision with its in-service period", "M": "M row → a Draft revision (the open change)"}[prefix], oldno)
                if extra:
                    self.rule("overflow columns (SETTINGS2, DESC, REMARKS, CT/PT, CLASS…) → the record's summary text", oldno)
                n += 1
                if n % 500 == 0:
                    self.log(f"revisions: {n}")

    # ------------------------------------------------------------------ 8 landings (#141)
    def track_for(self, name, cr, oldno, flags):
        """The relay's track row: under its own CR, else under the header's CR, else the relay's latest (card H, #148)."""
        t = self.tracks.get((name, cr, oldno))
        if t:
            return t
        hcr = self.header_cr.get(cr, cr)
        t = self.tracks.get((name, hcr, oldno)) if hcr != cr else None
        if t is None:
            others = [(c, x) for (c, x) in self.tracks_by_relay.get((name, oldno), []) if c != cr]
            if others:
                others.sort(key=lambda cx: (cx[1][2] or datetime.datetime.min, cx[0]))
                hcr, t = others[-1]
        if t:
            flags.append(self.run.flag("TrackUnderOtherCr", f"{oldno}/{cr}: {name} track found under CR {hcr} (SETTINGS and the track disagree) — card H", oldno))
        return t

    def landings_stage(self):
        for base, b in self.bases.items():
            for r in b["rows"]:
                oldno, cr = r[0], r[1]
                # an OLD_NO repeats within a base for P rows (P0005 carries eight CRs): the landing is keyed by row, the M rows keep their W7 key
                key = f"Landing:{oldno}" if oldno[0] == "M" else f"Landing:{oldno}/{cr}"
                flags = []
                doc = self.track_for("doc", cr, oldno, flags); db = self.track_for("db", cr, oldno, flags)
                if oldno[0] != "M" and doc is None and db is None:
                    continue   # an A or P row with no track row anywhere: nothing to land (card H)
                h = row_hash("Landing", oldno, cr, doc[0] if doc else None, db[0] if db else None)
                rule_name = "M row → a SETTINGS_CHANGE run landed at COMPLETION with its two tracks (#56)" if oldno[0] == "M" else f"{oldno[0]} row with track rows → its change landed at COMPLETION with the two tracks (card H, #148)"
                if self.run.already_loaded("process", "ProcedureInstance", key, h):
                    self.rule(rule_name, oldno); continue
                if self.run.existing_entity("process", "ProcedureInstance", key):
                    self.run.flag("LandingNotRepaired", f"{oldno}/{cr}: landed earlier under other track states; a landed run is not re-shaped", oldno)
                    continue
                if oldno[0] == "M" and (doc is None or db is None):
                    flags.append(self.run.flag("TrackRowMissing", f"{oldno}/{cr}: {'documentation' if doc is None else ''}{' and ' if doc is None and db is None else ''}{'database' if db is None else ''} track row missing; branch left Running", oldno))
                cd, _, _ = dto(r[1] and None)
                (wf, pi) = self.run.exec("process.LandMigratedInstance", outputs=[("WorkflowInstanceEntityId", "UNIQUEIDENTIFIER"), ("ProcedureInstanceEntityId", "UNIQUEIDENTIFIER")],
                                         WorkRequestEntityId=self.requests[cr], DocumentationStatus=doc[0] if doc else None, DatabaseStatus=db[0] if db else None,
                                         DocumentationAt=dto(doc[2])[0] if doc and doc[2] else None, DatabaseAt=dto(db[2])[0] if db and db[2] else None, At=capture_at())   # W8 (#149): the track's own date
                self.run.provenance("process", "ProcedureInstance", key, h, entity_id=pi, notes=self.run.join_flags(*flags))
                self.run.provenance("process", "WorkflowInstance", key, h, entity_id=wf)
                self.rule(rule_name, oldno)

    # ------------------------------------------------------------------ 9 findings (#142)
    def findings_stage(self):
        rows = self.src_rows("""SELECT a.b, a.cr, p.maxcr FROM (SELECT SUBSTRING(OLD_NO,2,4) b, [Change Request ID] cr FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1)='A') a
                                JOIN (SELECT SUBSTRING(OLD_NO,2,4) b, MAX([Change Request ID]) maxcr FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1)='P' GROUP BY SUBSTRING(OLD_NO,2,4)) p ON p.b = a.b
                                WHERE p.maxcr > a.cr ORDER BY a.b""")
        for base, acr, pcr in rows:
            if base not in self.bases:
                continue
            key = f"Finding:{base}"; h = row_hash("Finding", base, acr, pcr)
            if self.run.already_loaded("record", "Finding", key, h) or self.run.existing_entity("record", "Finding", key):
                self.rule("chain where an archived CR exceeds the active CR → a finding (#59)", base); continue
            desc = f"Legacy chain {base}: the active record's change request {acr} is lower than an archived record's {pcr}. Migrated as the letters say (A active, P history); a person rules on which is current (decision #59)."
            (rec, rrow) = self.run.exec("record.Record_Add", outputs=[("EntityId", "UNIQUEIDENTIFIER"), ("RowId", "UNIQUEIDENTIFIER")],
                                        RecordKindCode="Finding", SubjectKind="Device", SubjectEntityId=self.bases[base]["asset"], OccurredAt=capture_at(), TimeSourceQuality=4,
                                        PerformedByActorId=self.run.actor_id, OverallResult="Informational", Summary=desc[:1000], ValidFrom=capture_at(), ValidFromQuality=2)
            self.run.exec("record.Finding_Add", EntityId=rec, FindingCategoryCode="MigrationReconciliation", Severity="Major", Description=desc, AsFoundValue=f"A CR {acr}", ExpectedValue=f"A CR ≥ {pcr}", ValidFrom=capture_at(), ValidFromQuality=2)
            self.run.provenance("record", "Finding", key, h, entity_id=rec, row_id=rrow)
            self.rule("chain where an archived CR exceeds the active CR → a finding (#59)", base)

    # ------------------------------------------------------------------ 9b provenance for the engine-written rows
    def provenance_stage(self):
        """WriteConfigurationRevision and LandMigratedInstance write documents, files, blocks, steps, version pins and transitions
        under the run id; each gets its own provenance row here, keyed by the revision or landing it belongs to (the reverse walk)."""
        n = 0
        for key, doc, frow, fent in self.run.rows("""SELECT p.SourceKey, r.DocumentEntityId, f.RowId, f.EntityId
            FROM migration.vProvenance p JOIN migration.vRun mr ON mr.RunId = p.RunId
            JOIN document.vRevision r ON r.RowId = p.TargetRowId LEFT JOIN document.vFile f ON f.RevisionRowId = r.RowId
            WHERE mr.SourceSystem = ? AND p.TargetSchema = 'document' AND p.TargetTable = 'ConfigurationFile'""", SOURCE):
            base = key.split(":", 1)[1][1:5]
            dk = f"Document:{base}"
            if doc and not self.run.existing_entity("document", "Document", dk):
                self.run.provenance("document", "Document", dk, row_hash("Document", base), entity_id=str(doc)); n += 1
            fk = f"File:{key.split(':', 1)[1]}"
            if frow and not self.run.existing_row("document", "File", fk):
                self.run.provenance("document", "File", fk, row_hash("File", key), entity_id=str(fent), row_id=str(frow)); n += 1
        for table, sql in (
            ("BlockInstance", "SELECT p.SourceKey, b.EntityId, b.RowId, b.BlockPath FROM process.vBlockInstance b JOIN migration.vProvenance p ON p.TargetEntityId = b.ProcedureInstanceEntityId AND p.TargetTable = 'ProcedureInstance' WHERE b.MigrationRunId IS NOT NULL"),
            ("StepInstance", "SELECT p.SourceKey, s.EntityId, s.RowId, s.StepId FROM process.vStepInstance s JOIN process.vBlockInstance b ON b.EntityId = s.BlockInstanceEntityId JOIN migration.vProvenance p ON p.TargetEntityId = b.ProcedureInstanceEntityId AND p.TargetTable = 'ProcedureInstance' WHERE s.MigrationRunId IS NOT NULL"),
            ("InstanceVersionSet", "SELECT p.SourceKey, NULL, v.RowId, v.CalleeKey FROM process.vInstanceVersionSet v JOIN migration.vProvenance p ON p.TargetEntityId = v.ProcedureInstanceEntityId AND p.TargetTable = 'ProcedureInstance' WHERE v.MigrationRunId IS NOT NULL"),
            ("WorkflowTransition", "SELECT p.SourceKey, NULL, NULL, CONVERT(NVARCHAR(20), t.TransitionId) FROM process.vWorkflowTransition t JOIN migration.vProvenance p ON p.TargetEntityId = t.WorkflowInstanceEntityId AND p.TargetTable = 'WorkflowInstance' WHERE t.MigrationRunId IS NOT NULL")):
            for key, eid, rid, tag in self.run.rows(sql):
                k = f"{table}:{key.split(':', 1)[1]}:{tag}"
                if ("process", table, k) in self.run._existing:
                    continue
                self.run.provenance("process", table, k, row_hash(table, key, tag), entity_id=str(eid) if eid else None, row_id=str(rid) if rid else None); n += 1
        # W8 (#156): rows an earlier run wrote without provenance — node-function labels, ANSI codes, manufacturer entities
        for key, eid, rid in self.run.rows("""SELECT CONCAT(N'NodeFunction:', SUBSTRING(p.SourceKey, CHARINDEX(N':', p.SourceKey) + 1, 200)), nf.EntityId, nf.RowId
            FROM location.vNodeFunction nf JOIN migration.vProvenance p ON p.TargetEntityId = nf.NodeEntityId AND p.TargetTable = 'Node' AND p.SourceKey LIKE 'Position:%'
            WHERE nf.MigrationRunId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM migration.vProvenance q WHERE q.TargetTable = 'NodeFunction' AND q.TargetEntityId = nf.EntityId)"""):
            self.run.provenance("location", "NodeFunction", key, row_hash("NodeFunction", key), entity_id=str(eid), row_id=str(rid)); n += 1
        for (code,) in self.run.rows("SELECT AnsiCode FROM ref.vAnsiFunction WHERE MigrationRunId IS NOT NULL"):
            k = f"AnsiFunction:{code}"
            if ("ref", "AnsiFunction", k) not in self.run._existing:
                self.run.provenance("ref", "AnsiFunction", k, row_hash("Ansi", code)); n += 1
        for short, eid, rid in self.run.rows("SELECT m.ShortCode, e.EntityId, e.RowId FROM ref.vManufacturer m JOIN party.vEntity e ON e.EntityId = m.EntityEntityId WHERE e.MigrationRunId IS NOT NULL"):
            k = f"Entity:Manufacturer:{short}"
            if ("party", "Entity", k) not in self.run._existing:
                self.run.provenance("party", "Entity", k, row_hash("Entity", short), entity_id=str(eid), row_id=str(rid)); n += 1
        self.log(f"provenance for engine-written rows: {n}")

    # ------------------------------------------------------------------ 10 the reconciliation
    def dropped_counts(self):
        for prefix, n in self.src_rows("SELECT LEFT(OLD_NO,1), COUNT(*) FROM dbo.SETTINGS WHERE LEFT(OLD_NO,1) NOT IN ('A','M','P') GROUP BY LEFT(OLD_NO,1)"):
            self.rule("D row: dropped, counted (#31)" if prefix == "D" else f"row keyed '{prefix}…' (2440): dropped, counted (#60)", prefix, n=n)
        for tbl in ("Relay Document Management", "Setting Database Management", "Setting Software Management"):
            total = self.src.execute(f"SELECT COUNT(*) FROM dbo.[{tbl}]").fetchone()[0]
            matched = self.src.execute(f"SELECT COUNT(*) FROM dbo.[{tbl}] t WHERE EXISTS (SELECT 1 FROM dbo.SETTINGS s WHERE s.[Change Request ID] = t.[Change Request ID] AND s.OLD_NO = LTRIM(RTRIM(t.[Relay ID Number])) AND LEFT(s.OLD_NO,1) IN ('A','M','P'))").fetchone()[0]
            if tbl != "Setting Software Management":
                self.rules[f"{tbl} row → a completion-track state on its request"] = matched
            else:
                self.rules["Setting Software Management row of an A/M/P chain: NA (nothing to carry) or a note (#58)"] = matched
            self.rule(f"{tbl} row of a dropped or unknown chain: counted, not written", tbl, n=total - matched)

    def report(self, path):
        src_totals = {t: self.src.execute(f"SELECT COUNT(*) FROM dbo.[{t}]").fetchone()[0] for t in ("SETTINGS", "Settings Management", "Relay Document Management", "Setting Database Management", "Setting Software Management", "LOCATIONS", "Users")}
        lines = [f"# Reconciliation — {SOURCE} → PnCPlatform_V2_DEV — {datetime.date.today().isoformat()}", "",
                 f"Run `{self.run.run_id}` · {self.run.calls} procedure calls · {round(time.time() - self.t0)} s · limit {self.limit or 'none'}", "",
                 "## Source totals", "", "| Table | Rows |", "|---|---:|"] + [f"| `{t}` | {n:,} |" for t, n in src_totals.items()] + [
                 "", f"Sum: {sum(src_totals.values()):,} (the gate: 14 211 + 8 409 + 8 409 + 8 408 + 8 408 + 825 + 32 = 48 702, plus `Setting Software Data` 4 and `sysdiagrams` 0 = 48 706)", "",
                 "## Every input row under one rule", "", "| Rule | Rows |", "|---|---:|"] + [f"| {k} | {v:,} |" for k, v in sorted(self.rules.items())] + [
                 "", "### SETTINGS arithmetic", "",
                 f"A {self.rules.get('A row → the current revision, in service now', 0):,} + M {self.rules.get('M row → a Draft revision (the open change)', 0):,} + P {self.rules.get('P row → a superseded revision with its in-service period', 0):,} + control-switch rows {self.rules.get('CONTROL SWITCH row: asset only, no configuration file (mappings/asset_type.csv)', 0):,} + D {self.rules.get('D row: dropped, counted (#31)', 0):,} + 2440 {self.rules.get(chr(114) + 'ow keyed ' + chr(39) + '2…' + chr(39) + ' (2440): dropped, counted (#60)', 0):,} + no-panel {self.rules.get('row of a base with no LOCATION/EQUIPMENT panel: counted, not written', 0):,} = {src_totals['SETTINGS']:,}",
                 "", "## Target rows written / skipped (idempotent)", "", "| Target | Written | Skipped |", "|---|---:|---:|"] + [
                 f"| `{t}` | {self.run.written.get(t, 0):,} | {self.run.skipped.get(t, 0):,} |" for t in sorted(set(self.run.written) | set(self.run.skipped))] + [
                 "", "## Flags", "", "| Flag | Count | Examples |", "|---|---:|---|"] + [f"| `{k}` | {v:,} | {'; '.join(self.run.flag_examples.get(k, []))[:300]} |" for k, v in sorted(self.run.flags.items())] + [""]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        return src_totals


def load(database, limit=None, report=None, source_db=None):
    """The rehearsal runner's entry (run_rehearsal.py): one run, the reconciliation written, the run's report returned."""
    if not database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    with Run(SOURCE, CAPTURE_AT, notes=f"W7 legacy import (CUTOVER-STRATEGY §5); limit {limit}", target_db=database) as run:
        imp = Importer(run, limit, source_db)
        for stage in ("prepare", "persons_stage", "manufacturers_stage", "models_stage", "locations_stage", "devices_stage", "requests_stage", "revisions_stage", "landings_stage", "findings_stage", "provenance_stage", "dropped_counts"):
            imp.log(stage); getattr(imp, stage)()
        path = report or os.path.join(HERE, f"RECONCILIATION-{datetime.date.today().isoformat()}.md")
        totals = imp.report(path)
        rep = run.report(); rep["rules"] = dict(imp.rules); rep["source_totals"] = totals; rep["report"] = path
        return rep


def close_landed(database):
    """After the API's sweep has completed landed runs whose two tracks were terminal (Complete / NA), close their requests
    (#148). A separate call, not a load stage: the sweep runs on the host's own cadence, and the rehearsal's second pass
    must write nothing. Idempotent: a closed request is not touched again."""
    if not database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    with Run(SOURCE, CAPTURE_AT, notes="W7 card H: close the landed requests whose runs completed", target_db=database) as run:
        rows = run.rows("""SELECT p.SourceKey, wf.EntityId FROM migration.vProvenance p JOIN migration.vRun r ON r.RunId = p.RunId
            JOIN process.vProcedureInstance pi ON pi.EntityId = p.TargetEntityId
            JOIN process.vWorkflowInstance wf ON wf.EntityId = pi.WorkflowInstanceEntityId
            WHERE r.SourceSystem = ? AND p.TargetTable = 'ProcedureInstance' AND p.SourceKey LIKE 'Landing:%'
              AND pi.State = 'Completed' AND pi.Outcome = 'Completed' AND wf.CurrentState = 'InProgress'""", SOURCE)
        n = 0
        for key, wf in rows:
            oldno = key.split(":", 1)[1]; k = f"Close:{oldno}"; h = row_hash("Close", oldno)
            if run.already_loaded("process", "WorkflowTransition", k, h) or run.existing_entity("process", "WorkflowTransition", k):
                continue
            (to, tid) = run.exec("process.Transition", outputs=[("ToState", "NVARCHAR(40)"), ("TransitionId", "BIGINT")], WorkflowInstanceEntityId=str(wf), TransitionName="Close", Reason="Migrated change completed in the legacy system (W7 card H)", At=capture_at())
            run.provenance("process", "WorkflowTransition", k, h, entity_id=str(wf), notes=f"TransitionId {tid}"); n += 1
        rep = run.report(); rep["closed"] = n
        return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--database", default=common.TARGET_DB)
    ap.add_argument("--limit", type=int, default=None, help="load only the first N base numbers (smoke)")
    ap.add_argument("--report", default=None)
    ap.add_argument("--close", action="store_true", help="close the landed requests whose runs the sweep has completed (card H); no load")
    ap.add_argument("--source-db", default=None, help="read the legacy tables from this database instead of dbRelayManagement_Legacy (the cutover rehearsal's second copy, W8)")
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the target must be a PnCPlatform_V2_* database (#99)")
    rep = close_landed(a.database) if a.close else load(a.database, a.limit, a.report, a.source_db)
    print(json.dumps(rep, indent=1, default=str))


if __name__ == "__main__":
    main()
