"""#171 (2026-09-16): the single source of the seeded obligation rules and formulas.

Writes docs/schema/ddl/PostDeploy/Seed_config_Formulas_PRC023.sql and Seed_config_ObligationRules.sql. Every expression is
written here as the text a person reads and compiled to its canonical grammar-1 AST by the platform's own parser
(tools/FormulaCompile, a thin console over src/PnC.Formula) — the seed carries both, the evaluator uses the AST, the screen
shows the text. Sources of the rule content: the owner's rulings of 2026-09-16 (DECISION-LOG #171; memory
feedback-applicability-from-primary-assets), PRC-023-6 R1 criteria 1, 2, 12, 13 and §4.2.1 (NERC; NB appendix PRC-023-6-NB-0
makes no change to R1), the SEL-221F manual 2-32 / 5-14 (reach along the line angle; mho diameter = reach / cos(line angle -
MTA)), SPP "Methods to Increase Line Relay Loadability" Fig. 2 (Z30 = Z_MTA cos(MTA - 30)).

usage: python tools/compliance_rules.py            (needs dotnet; runs tools/FormulaCompile)
"""
import io, json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "schema", "ddl", "PostDeploy")

# The standard versions in force in New Brunswick (Seed_compliance_Standards_NB.sql; read from https://nbeub.ca/reliability-standards).
# A rule names its requirement by (standard, version label, number) — compliance.fResolveRequirement — so these labels must
# match the standards seed exactly.
VERSIONS = {   # the NB appendix labels in force on 2026-09-16 (nbeub.ca): the label is the VersionLabel of Seed_compliance_Standards_NB.sql
    "PRC-023": "PRC-023-6-NB-0",
    "CIP-004": "CIP-004-7-NB-0", "CIP-005": "CIP-005-7-NB-0", "CIP-006": "CIP-006-6-NB-0",
    "CIP-007": "CIP-007-6-NB-0", "CIP-010": "CIP-010-4-NB-0", "CIP-011": "CIP-011-3-NB-0",
}

CIP_SCOPE = "device.classification.BesCyberAsset = 'BCA' and device.station.classification.CipImpactRating in {'High', 'Medium'}"
CIP_ERC_SCOPE = CIP_SCOPE + " and device.classification.ExternalRoutableConnectivity = 'ERC'"
CIP_NOTE = ("The platform holds no record kind for this requirement in this phase; the evidence is kept outside the platform. "
            "The obligation is listed so the device's sheet shows what applies to it (owner, 2026-09-16).")

# (key, standard, number, scope text, cadence, note)
CIP_RULES = [
    ("cip004_r2", "CIP-004", "R2", CIP_SCOPE, "once", CIP_NOTE),
    ("cip004_r4", "CIP-004", "R4", CIP_SCOPE, "once", CIP_NOTE),
    ("cip005_r1", "CIP-005", "R1", CIP_ERC_SCOPE, "once", CIP_NOTE + " Applies with external routable connectivity (the owner's list)."),
    ("cip006_r1", "CIP-006", "R1", CIP_SCOPE, "once", CIP_NOTE),
    ("cip007_r1", "CIP-007", "R1", CIP_SCOPE, "once", CIP_NOTE),
    ("cip007_r2", "CIP-007", "R2", CIP_SCOPE, "once", CIP_NOTE),
    ("cip007_r3", "CIP-007", "R3", CIP_SCOPE, "once", CIP_NOTE),
    ("cip007_r4", "CIP-007", "R4", CIP_SCOPE, "once", CIP_NOTE),
    ("cip007_r5", "CIP-007", "R5", CIP_SCOPE, "once", CIP_NOTE),
    ("cip010_r1", "CIP-010", "R1", CIP_SCOPE, "once", CIP_NOTE),
    ("cip010_r2", "CIP-010", "R2", CIP_SCOPE, "once", CIP_NOTE),
    ("cip010_r3", "CIP-010", "R3", CIP_SCOPE, "once", CIP_NOTE),
    ("cip011_r1", "CIP-011", "R1", CIP_SCOPE, "once", CIP_NOTE),
]

PRC_R1_SCOPE = "device.protects.terminal.voltage >= 200kV or device.protects.classification.Prc023 = 'Listed'"
PRC_RECORD = ["asset.formula.prc023_zset", "asset.formula.prc023_line_angle", "asset.formula.prc023_z30",
              "asset.formula.prc023_trip_current", "asset.formula.prc023_load_current", "asset.formula.prc023_criterion",
              "device.settings.Z3%", "device.settings.R1", "device.settings.X1", "device.settings.MTA", "device.settings.50H",
              "device.protects.name", "device.protects.terminal.voltage"]
PRC_RULES = [
    ("prc023_r1", "PRC-023", "R1", PRC_R1_SCOPE, "once",
     "PRC-023-6 R1: any one of criteria 1-13 for the circuit terminal; loadability at 0.85 pu and 30 degrees. The group applies "
     "criterion 1, then 2, then 13, then 12 (owner, 2026-09-16); the formula prc023_criterion records which one the in-service "
     "settings satisfy. Applicability from PRC-023-6 4.2.1.1 (200 kV and above) or the Planning Authority's R6 list (recorded as "
     "the Prc023 classification of the protected asset). NB appendix PRC-023-6-NB-0: no modification."),
    ("prc023_r3", "PRC-023", "R3", "asset.formula.prc023_criterion = '13'", "once",
     "PRC-023-6 R3: a circuit set by criterion 13 (or 7, 8, 9, 12) uses the calculated circuit capability as the Facility Rating, "
     "with the Planning Authority's, Transmission Operator's and Reliability Coordinator's agreement."),
    ("prc023_r4", "PRC-023", "R4", "asset.formula.prc023_criterion = '2'", "every calendar_year",
     "PRC-023-6 R4: a circuit set by criterion 2 is on the list provided to the Planning Authority, Transmission Operator and "
     "Reliability Coordinator at least once each calendar year, no more than 15 months between reports."),
    ("prc023_r5", "PRC-023", "R5", "asset.formula.prc023_criterion = '12'", "every calendar_year",
     "PRC-023-6 R5 (NB appendix): a circuit set by criterion 12 is on the list provided to the Northeast Power Coordinating "
     "Council at least once each calendar year, no more than 15 months between reports."),
]

# (key, name, unit, precision, expression text, description)
FORMULAS = [
    ("prc023_zset", "PRC-023: zone 3 set reach along the line angle", "Ω", 2,
     "to(device.settings.Z3%, 'ratio') * hypot(device.settings.R1, device.settings.X1)",
     "Z3% of |R1 + jX1| (primary ohms) along the positive-sequence line angle — SEL-221F manual 5-14: 'The reach settings for the "
     "phase distance elements are a percentage of the positive-sequence line impedance settings along the line angle.'"),
    ("prc023_line_angle", "PRC-023: positive-sequence line angle", "deg", 2,
     "atan2(device.settings.X1, device.settings.R1)",
     "arctan(X1/R1) — the transmission line angle the manual names (2-32)."),
    ("prc023_z30", "PRC-023: apparent impedance at 30 degrees on the zone 3 mho", "Ω", 2,
     "asset.formula.prc023_zset / cos(asset.formula.prc023_line_angle - device.settings.MTA) * cos(device.settings.MTA - 30deg)",
     "The mho circle passes through the origin with its diameter along the MTA: diameter = set reach / cos(line angle - MTA) "
     "(manual 2-32); the impedance the circle reaches at a 30-degree load angle is diameter x cos(MTA - 30) (SPP, Methods to "
     "Increase Line Relay Loadability, Fig. 2). Steady-state self-polarised circle; the memory-polarised expansion (2-33) is not modelled."),
    ("prc023_trip_current", "PRC-023: zone 3 trip current at 0.85 pu and 30 degrees", "A", 0,
     "0.85 * to(device.protects.terminal.voltage, 'V') * 0.5773503 / asset.formula.prc023_z30",
     "I = 0.85 x V(line-neutral) / Z30, the loadability current PRC-023-6 R1 asks for (0.85 per unit voltage, 30-degree power "
     "factor angle); V(line-neutral) = the terminal's nominal kV / sqrt(3). Checks against SPP Fig. 2: 345 kV, Z30 = 88 ohm -> "
     "1 352 MVA at nominal volts; x 0.85 / 1.5 = 766 MVA (their 8a MVA)."),
    ("prc023_load_current", "PRC-023: the lowest current a load-responsive element trips at", "A", 0,
     "coalesce(min(asset.formula.prc023_trip_current, device.settings.50H), asset.formula.prc023_trip_current)",
     "The zone 3 trip current, or the 50H phase overcurrent pickup when lower (50H is the switch-onto-fault detector and may be in "
     "the unconditional trip mask, manual 5-20; the mask is not decoded here). 50P only supervises the distance elements (5-19), "
     "so it is not a limit by itself. Attachment A 2.2: ground elements are excluded."),
    ("prc023_criterion", "PRC-023: the R1 criterion the in-service settings satisfy (1, 2, 13, 12 in the group's order)", None, None,
     "if(coalesce(asset.formula.prc023_load_current > 1.5 * device.protects.rating[kind='FourHour'], false), '1', "
     "if(coalesce(asset.formula.prc023_load_current > 1.15 * device.protects.rating[kind='FifteenMinute'], false), '2', "
     "if(coalesce(asset.formula.prc023_load_current > 1.15 * device.protects.rating[kind='PracticalLimitation'], false), '13', "
     "if(coalesce(asset.formula.prc023_zset <= 1.25 * hypot(device.settings.R1, device.settings.X1) and device.settings.MTA = 90deg, false), '12', 'None'))))",
     "Criterion 1: not at or below 150 % of the highest seasonal 4-hour Facility Rating (amperes). Criterion 2: 115 % of the "
     "15-minute rating (when one is published). Criterion 13: 115 % of a practical limitation (then R3). Criterion 12: the distance "
     "reach at most 125 % of the line impedance with the MTA at 90 degrees (the SEL-221F's highest, 2-8; then R5). A rating the "
     "platform does not hold skips that criterion (coalesce -> false) instead of leaving the answer unknown. 'None' = no criterion met."),
]


def compile_all(items):
    spec = os.path.join(tempfile.gettempdir(), "pnc_formula_spec.json")
    io.open(spec, "w", encoding="utf-8").write(json.dumps({"items": items}))
    proj = os.path.join(ROOT, "tools", "FormulaCompile")
    r = subprocess.run(["dotnet", "run", "--project", proj, "--", spec], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0 and not r.stdout.strip().startswith("{"):
        sys.exit("FormulaCompile failed:\n" + r.stdout + r.stderr)
    out = json.loads(r.stdout)
    errs = {k: v["error"] for k, v in out.items() if "error" in v}
    if errs:
        sys.exit("expressions that do not compile:\n" + "\n".join(f"  {k}: {e}" for k, e in errs.items()))
    return out


def sql_str(s):
    return "N'" + s.replace("'", "''") + "'"


HEADER = """-- GENERATED by tools/compliance_rules.py — do not edit; change the table there and regenerate. Decision #171 (2026-09-16).
-- {what}
-- Idempotent: a definition gets a version approved only when it has no effective version (a definition left without one by an
-- interrupted seed is completed); a changed rule is a new version added by a person.
IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
IF NOT EXISTS (SELECT 1 FROM [personnel].[Actor] WHERE [ActorId] = @approver)
    INSERT [personnel].[Actor] ([ActorId], [ActorKind], [SystemName]) VALUES (@approver, N'System', N'Platform.SeedApprover');
"""


def definition_block(kind, key, name, description, payload):
    p = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    return f"""
IF NOT EXISTS (SELECT 1 FROM [config].[Definition] d JOIN [config].[DefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[IsDeleted] = 0 AND dv.[Status] = N'Effective'
               WHERE d.[DefinitionKind] = N'{kind}' AND d.[DefinitionKey] = {sql_str(key)} AND d.[IsDeleted] = 0)
BEGIN
    DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @n INT;
    IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'{kind}' AND [DefinitionKey] = {sql_str(key)} AND [IsDeleted] = 0)
        EXEC [config].[AddDefinition] @DefinitionKind = N'{kind}', @DefinitionKey = {sql_str(key)}, @Name = {sql_str(name)},
             @Description = {sql_str(description)}, @ActorId = @author, @EntityId = @e OUTPUT;
    EXEC [config].[AddDefinitionVersion] @DefinitionKey = {sql_str(key)}, @DefinitionKind = N'{kind}', @ChangeNote = N'seed (#171)',
         @PayloadText = {sql_str(p)}, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @n OUTPUT;
    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;
END
GO
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';"""


def main():
    items = [{"id": "f:" + k, "kind": "expression", "text": t} for (k, _, _, _, t, _) in FORMULAS]
    for (k, _, _, scope, cad, _) in CIP_RULES + PRC_RULES:
        items.append({"id": "r:" + k, "kind": "expression", "text": scope})
        items.append({"id": "c:" + k, "kind": "cadence", "text": cad})
    out = compile_all(items)

    # formulas (in dependency order: each names only formulas seeded before it — ValidateProgramFacts needs the fact in the catalogue)
    sql = HEADER.format(what="The PRC-023 loadability formulas (Program.Formula, subject Device): the zone 3 reach, the line angle, the impedance at 30 degrees, the trip current at 0.85 pu, the lowest load-responsive trip current, and the R1 criterion satisfied. Sources in the docstring of the generator and in each formula's description.")
    for (k, name, unit, prec, text, desc) in FORMULAS:
        c = out["f:" + k]
        publishes = {"fact": "asset.formula." + k, "type": "num" if unit is not None else "text"}
        if unit is not None:
            publishes["unit"] = unit
            publishes["precision"] = prec
        payload = {"g": 1, "subjectKind": "Device", "inputs": c["facts"], "expressionText": text, "expression": c["ast"], "publishes": publishes}
        sql += definition_block("Program.Formula", k, name, desc, payload)
    io.open(os.path.join(OUT, "Seed_config_Formulas_PRC023.sql"), "w", encoding="utf-8", newline="\r\n").write(sql + "\n")

    # rules
    sql = HEADER.format(what="The obligation rules (Program.ObligationRule, subject Device): the CIP requirement set for a BES Cyber Asset at a High or Medium impact station (the owner's starter list, 2026-09-16), and PRC-023-6 R1 / R3 / R4 / R5 on the terminals it applies to. The requirement is named by (standard, version in force in NB, number) and must resolve at seed time.")
    for (k, std, num, scope, cad, note) in CIP_RULES + PRC_RULES:
        ver = VERSIONS.get(std)
        if ver is None:
            sys.exit(f"VERSIONS[{std!r}] is not set — fill it from Seed_compliance_Standards_NB.sql before generating")
        c = out["r:" + k]
        payload = {"g": 1, "requirement": {"standard": std, "version": ver, "number": num}, "subjectKinds": ["Device"],
                   "scopeText": scope, "scope": c["ast"], "cadenceText": cad, "cadence": out["c:" + k]["ast"],
                   "evidence": {"recordKinds": [], "minAcceptance": None}, "evidenceNote": note}
        if k == "prc023_r1":
            payload["record"] = PRC_RECORD
        name = f"{ver} {num}" + (" — BES Cyber Asset at a High/Medium station" if std.startswith("CIP") else " — transmission relay loadability")
        sql += definition_block("Program.ObligationRule", k, name, note, payload)
    io.open(os.path.join(OUT, "Seed_config_ObligationRules.sql"), "w", encoding="utf-8", newline="\r\n").write(sql + "\n")
    print("wrote Seed_config_Formulas_PRC023.sql (%d formulas) and Seed_config_ObligationRules.sql (%d rules)" % (len(FORMULAS), len(CIP_RULES) + len(PRC_RULES)))


if __name__ == "__main__":
    main()
