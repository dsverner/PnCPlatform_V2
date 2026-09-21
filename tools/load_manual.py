"""load_manual.py - keep a device model's instruction manual with its template (#216).

The owner, 2026-09-21: "I would like to have a copy of the manual kept with the template and accessible for review in a
tab or possibly separate window ... the field staff work on a single monitor."

The manual is a document of class InstructionManual; its revision holds the file (document.File_Write, the same path
every stored file takes) and links About the asset template definition (CharacteristicSchema.AssetTemplate), so every
relay of a model bound to that template opens it. The PDF never enters git (CLAUDE.md: large artefacts stay on Z:) - this
tool reads it from where it is and writes it to the environment named, once: a linked file with the same SHA-256 is left
alone. Not a migration rule (nothing here is legacy data); a per-environment step after deploy, recorded in the runbook.

Usage:
  python tools/load_manual.py --server 10.10.70.25 --database PnCPlatform_V2_DEV --template SEL221F_Template
      --file "Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf"
      --title "SEL-221F-2, -3, -4 / SEL-121F-2, -3 Instruction Manual, date code 981207"
The password comes from PNC_DEV_PWD or dev.local, as the schema tools read it (docs/schema/ddl/tools/smoke.py).
"""
import argparse, hashlib, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "schema", "ddl", "tools"))
import pyodbc  # noqa: E402
import smoke  # noqa: E402  (password())

SYSTEM_ACTOR = "00000000-0000-0000-0000-000000000001"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True); ap.add_argument("--database", required=True)
    ap.add_argument("--template", required=True, help="the asset template's DefinitionKey, e.g. SEL221F_Template")
    ap.add_argument("--file", required=True); ap.add_argument("--title", required=True)
    ap.add_argument("--mime", default="application/pdf")
    a = ap.parse_args()
    if not a.database.startswith("PnCPlatform_V2_"):
        sys.exit("refusing: the database must be a PnCPlatform_V2_* database")
    data = open(a.file, "rb").read()
    sha = hashlib.sha256(data).digest()
    name = os.path.basename(a.file)
    cn = pyodbc.connect("DRIVER={ODBC Driver 17 for SQL Server};SERVER=" + a.server + ";DATABASE=" + a.database + ";UID=dev_pnc;PWD=" + smoke.password() + ";TrustServerCertificate=yes", autocommit=False)
    c = cn.cursor()
    tmpl = c.execute("SELECT EntityId FROM config.vDefinition WHERE DefinitionKind = N'CharacteristicSchema.AssetTemplate' AND DefinitionKey = ?", a.template).fetchone()
    if not tmpl: sys.exit("no asset template " + a.template)
    cls = c.execute("SELECT EntityId FROM config.vDefinition WHERE DefinitionKind = N'CharacteristicSchema.DocumentClass' AND DefinitionKey = N'InstructionManual'").fetchone()
    if not cls: sys.exit("the document class InstructionManual is not seeded on this database")
    have = c.execute("""SELECT f.RowId FROM document.vRevisionLink l JOIN document.vFile f ON f.RevisionRowId = l.RevisionRowId
                        WHERE l.LinkKind = N'About' AND l.SubjectKind = N'Definition' AND l.SubjectEntityId = ? AND f.Sha256 = ?""", tmpl[0], sha).fetchone()
    if have:
        print("already there: file " + str(have[0]) + " (" + name + ", " + str(len(data)) + " bytes, same SHA-256)"); return
    doc = c.execute("""DECLARE @e UNIQUEIDENTIFIER; EXEC document.Document_Add @DocumentClassDefinitionEntityId=?, @Title=?, @Description=?, @ActorId=?, @EntityId=@e OUTPUT; SELECT @e""",
                    cls[0], a.title[:200], "Instruction manual kept with the template " + a.template + " (#216); loaded from " + a.file, SYSTEM_ACTOR).fetchval()
    rev = c.execute("""DECLARE @r UNIQUEIDENTIFIER, @now DATETIMEOFFSET(7) = SYSDATETIMEOFFSET(); EXEC document.Revision_Add @DocumentEntityId=?, @RevisionLabel=N'1', @Status=N'Issued', @IssuedAt=@now, @ChangeNote=?, @ActorId=?, @RowId=@r OUTPUT; SELECT @r""",
                    doc, "as published by the manufacturer", SYSTEM_ACTOR).fetchval()
    c.setinputsizes([(pyodbc.SQL_WVARCHAR, 0, 0), (pyodbc.SQL_WVARCHAR, 0, 0), (pyodbc.SQL_WVARCHAR, 0, 0), (pyodbc.SQL_VARBINARY, 0, 0), (pyodbc.SQL_BINARY, 32, 0), (pyodbc.SQL_WVARCHAR, 0, 0)])
    frow = c.execute("""DECLARE @f UNIQUEIDENTIFIER; EXEC document.File_Write @RevisionRowId=?, @FileName=?, @MimeType=?, @Content=?, @FileRole=N'Attachment', @Sha256=?, @ActorId=?, @RowId=@f OUTPUT; SELECT @f""",
                     rev, name, a.mime, pyodbc.Binary(data), sha, SYSTEM_ACTOR).fetchval()
    c.setinputsizes(None)
    c.execute("EXEC document.RevisionLink_Add @RevisionRowId=?, @LinkKind=N'About', @SubjectKind=N'Definition', @SubjectEntityId=?, @ActorId=?", rev, tmpl[0], SYSTEM_ACTOR)
    cn.commit()
    print("loaded " + name + " (" + str(len(data)) + " bytes) as document " + str(doc) + ", file " + str(frow) + ", About " + a.template)


if __name__ == "__main__":
    main()
