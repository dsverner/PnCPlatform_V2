"""
Shared machinery for the migration loaders (SCHEMA-DESIGN §1.2, §14; vision §10.7). Carried from the predecessor in W7
(decision #137): the Run / Provenance / idempotence / flag mechanism is unchanged; only the target database default is V2's.

Every loader:
  * opens a migration.Run through migration.Run_Append under a System actor "Migration:<source>";
  * writes target rows only through the deployed procedures, always passing @MigrationRunId;
  * records one migration.Provenance row per target row (SourceKey + SHA-256 of the source row);
  * is idempotent: a source row whose (target, SourceKey, hash) already has provenance is skipped;
  * flags rather than repairs: FLAG:<kind>: text goes into Provenance.Notes and is counted.

Connections use the same dev.local / PNC_DEV_PWD convention as docs/schema/ddl/tools.
"""
import hashlib, os, sys, datetime, json, time
from collections import Counter, defaultdict
import pyodbc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SERVER = os.environ.get("PNC_SERVER", "10.10.70.25")
TARGET_DB = os.environ.get("PNC_TARGET_DB", "PnCPlatform_V2_DEV")   # never the predecessor's PnCPlatform_DEV (#99)
SEED_APPROVER = "00000000-0000-0000-0000-000000000002"   # Platform.SeedApprover (ddl PostDeploy)


def password():
    if os.environ.get("PNC_DEV_PWD"):
        return os.environ["PNC_DEV_PWD"]
    p = os.path.join(ROOT, "dev.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.startswith("PNC_DEV_PWD="):
                return line.split("=", 1)[1].strip()
    sys.exit("No password: set PNC_DEV_PWD or put PNC_DEV_PWD=... in dev.local")


def connect(database, server=SERVER):
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};"
        f"UID=dev_pnc;PWD={password()};TrustServerCertificate=yes", autocommit=True, timeout=30)


def row_hash(*parts):
    """SHA-256 over the canonical text of a source row (None → '', values stripped)."""
    canon = "\x1f".join("" if p is None else str(p).strip() for p in parts)
    return hashlib.sha256(canon.encode("utf-8")).digest()


def s(v, n=None):
    """Trim a legacy char/nchar value; empty → None; optional truncation with a flag by caller."""
    if v is None:
        return None
    v = str(v).strip()
    if v == "":
        return None
    return v if n is None else v[:n]


# ----------------------------------------------------------------------------- date quality

BAD_LOW = datetime.datetime(1950, 1, 1)


def date_quality(d, today=None):
    """Return (datetimeoffset-string-or-None, ValidFromQuality, flag-kind-or-None).
    0 exact; 2 unknown-defaulted for null, Access-null (1899-12-30), < 1950 or in the future."""
    today = today or datetime.datetime.now()
    if d is None:
        return None, 2, "DateNull"
    if d < BAD_LOW:
        return None, 2, "DateAccessNull" if d.year == 1899 else "DateBefore1950"
    if d > today:
        return None, 2, "DateInFuture"
    return d.strftime("%Y-%m-%d %H:%M:%S") + " -03:00", 0, None


# ----------------------------------------------------------------------------- the run

class Run:
    """One migration.Run against the target. Use as a context manager."""

    def __init__(self, source_system, source_capture_at, notes=None, target_db=TARGET_DB):
        self.source_system = source_system
        self.source_capture_at = source_capture_at
        self.notes = notes
        self.con = connect(target_db)
        self.cur = self.con.cursor()
        self.actor_id = self._system_actor(f"Migration:{source_system}")
        self.run_id = None
        self.flags = Counter()
        self.flag_examples = defaultdict(list)
        self.written = Counter()          # target "schema.Table" → rows written this run
        self.skipped = Counter()          # target "schema.Table" → rows already loaded (idempotent)
        self.calls = 0
        self.started = time.time()
        self._existing = {}               # (schema, table, source_key) → (hash, entity_id, row_id)
        self._load_existing()

    # -- actors ---------------------------------------------------------------
    def _system_actor(self, name):
        r = self.cur.execute("SELECT ActorId FROM personnel.vActor WHERE ActorKind = N'System' AND SystemName = ?", name).fetchone()
        if r:
            return str(r[0])
        r = self.cur.execute(
            "SET NOCOUNT ON; DECLARE @a UNIQUEIDENTIFIER; EXEC personnel.Actor_Append @ActorKind=N'System', @SystemName=?, @CreatedAt=?, @ActorId=@a OUTPUT; SELECT @a",
            name, datetime.datetime.now()).fetchone()
        return str(r[0])

    # -- provenance cache -------------------------------------------------------
    def _load_existing(self):
        rows = self.cur.execute("""
            SELECT p.TargetSchema, p.TargetTable, p.SourceKey, p.SourceRowHash, p.TargetEntityId, p.TargetRowId
            FROM migration.vProvenance p JOIN migration.vRun r ON r.RunId = p.RunId
            WHERE r.SourceSystem = ?""", self.source_system).fetchall()
        for sch, tbl, key, h, eid, rid in rows:
            self._existing[(sch, tbl, key)] = (bytes(h) if h is not None else None, str(eid) if eid else None, str(rid) if rid else None)

    def already_loaded(self, schema, table, source_key, h):
        """(entity_id, row_id) if this source row is already in the target with the same hash, else None."""
        e = self._existing.get((schema, table, source_key))
        if e and e[0] == h:
            self.skipped[f"{schema}.{table}"] += 1
            return e[1], e[2]
        return None

    def existing_entity(self, schema, table, source_key):
        """Entity id from an earlier run regardless of hash (for parents that must be resolved)."""
        e = self._existing.get((schema, table, source_key))
        return e[1] if e else None

    def existing_row(self, schema, table, source_key):
        """Row id from an earlier run regardless of hash (for fact versions that must be cited)."""
        e = self._existing.get((schema, table, source_key))
        return e[2] if e else None

    # -- run lifecycle ------------------------------------------------------------
    def __enter__(self):
        r = self.cur.execute(
            "SET NOCOUNT ON; DECLARE @r UNIQUEIDENTIFIER; EXEC migration.Run_Append @SourceSystem=?, @SourceCaptureAt=?, @StartedAt=?, @RunByActorId=?, @Notes=?, @RunId=@r OUTPUT; SELECT @r",
            self.source_system, self.source_capture_at, datetime.datetime.now(), self.actor_id, self.notes).fetchone()
        self.run_id = str(r[0])
        return self

    def __exit__(self, et, ev, tb):
        summary = {"written": dict(self.written), "skipped": dict(self.skipped), "flags": dict(self.flags),
                   "calls": self.calls, "seconds": round(time.time() - self.started, 1),
                   "outcome": "failed" if et else "completed", "error": str(ev)[:400] if ev else None}
        self.cur.execute("EXEC migration.CompleteRun @RunId=?, @Notes=?", self.run_id, json.dumps(summary))
        return False

    # -- writes ---------------------------------------------------------------------
    def exec(self, proc, outputs=(), **params):
        """EXEC a procedure with named parameters; returns the OUTPUT values in order.
        @ActorId and @MigrationRunId are supplied unless the procedure lacks them (pass none=True)."""
        none = params.pop("none", False)
        if not none:
            params.setdefault("ActorId", self.actor_id)
            params.setdefault("MigrationRunId", self.run_id)
        decl = "".join(f"DECLARE @o_{o} {t}; " for o, t in outputs)
        args = ", ".join(f"@{k}=?" for k in params)
        outs = ", ".join(f"@{o}=@o_{o} OUTPUT" for o, _ in outputs)
        sql = f"SET NOCOUNT ON; {decl}EXEC {proc} {args}{', ' if args and outs else ''}{outs};"
        if outputs:
            sql += " SELECT " + ", ".join(f"@o_{o}" for o, _ in outputs) + ";"
        vals = [self._py(v) for v in params.values()]
        self.calls += 1
        cur = self.cur.execute(sql, *vals)
        if outputs:
            row = cur.fetchone()
            return [str(x) if isinstance(x, str) else x for x in row]
        return []

    @staticmethod
    def _py(v):
        if isinstance(v, bool):
            return 1 if v else 0
        return v

    def provenance(self, schema, table, source_key, h, entity_id=None, row_id=None, notes=None):
        self.exec("migration.Provenance_Append", none=True, RunId=self.run_id, TargetSchema=schema, TargetTable=table,
                  TargetEntityId=entity_id, TargetRowId=row_id, SourceKey=source_key, SourceRowHash=h, Notes=notes)
        self._existing[(schema, table, source_key)] = (h, entity_id, row_id)
        self.written[f"{schema}.{table}"] += 1

    def flag(self, kind, text, key=None):
        """Record a flag; returns the 'FLAG:kind: text' line for Provenance.Notes."""
        self.flags[kind] += 1
        if len(self.flag_examples[kind]) < 5:
            self.flag_examples[kind].append(f"{key or ''} {text}".strip())
        return f"FLAG:{kind}: {text}"

    @staticmethod
    def join_flags(*flag_lines):
        lines = [f for f in flag_lines if f]
        return "\n".join(lines) if lines else None

    # -- lookups against the target ------------------------------------------------
    def one(self, sql, *p):
        r = self.cur.execute(sql, *p).fetchone()
        return r[0] if r else None

    def rows(self, sql, *p):
        return self.cur.execute(sql, *p).fetchall()

    def report(self):
        return {"source": self.source_system, "run_id": self.run_id, "actor": self.actor_id,
                "written": dict(sorted(self.written.items())), "skipped": dict(sorted(self.skipped.items())),
                "flags": dict(sorted(self.flags.items())), "flag_examples": {k: v for k, v in self.flag_examples.items()},
                "calls": self.calls, "seconds": round(time.time() - self.started, 1)}


# ----------------------------------------------------------------------------- definitions

def ensure_definition(run, kind, key, name, description=None, source_key=None, h=None):
    """A definition entity by (kind, key); created Draft through config.AddDefinition if absent."""
    eid = run.one("SELECT EntityId FROM config.vDefinition WHERE DefinitionKind=? AND DefinitionKey=?", kind, key)
    if eid:
        return str(eid), False
    (eid,) = run.exec("config.AddDefinition", outputs=[("EntityId", "UNIQUEIDENTIFIER")],
                      DefinitionKind=kind, DefinitionKey=key, Name=name, Description=description)
    run.provenance("config", "Definition", source_key or f"{kind}:{key}", h or row_hash(kind, key, name), entity_id=eid)
    return str(eid), True


def ensure_draft_version(run, kind, key, change_note, payload=None, source_key=None, h=None):
    """The definition's latest version if one exists, else a new Draft version. Returns (version_row_id, created)."""
    r = run.cur.execute("""SELECT TOP 1 v.RowId FROM config.vDefinitionVersion v JOIN config.vDefinition d ON d.EntityId = v.DefinitionEntityId
                           WHERE d.DefinitionKind=? AND d.DefinitionKey=? ORDER BY v.VersionNumber DESC""", kind, key).fetchone()
    if r:
        return str(r[0]), False
    (vid, _) = run.exec("config.AddDefinitionVersion", outputs=[("VersionRowId", "UNIQUEIDENTIFIER"), ("VersionNumber", "INT")],
                        DefinitionKey=key, DefinitionKind=kind, ChangeNote=change_note, PayloadText=payload)
    run.provenance("config", "DefinitionVersion", source_key or f"{kind}:{key}:v1", h or row_hash(kind, key, change_note, payload), row_id=vid)
    return str(vid), True
