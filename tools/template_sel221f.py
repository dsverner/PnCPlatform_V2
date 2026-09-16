"""
template_sel221f.py — the SEL-221F settings template (#168), from the instruction manual, as data.

Source: SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207
(Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf). Every row cites the printed
page it comes from (the SET list 3-24/3-25; Section 5's headings and ranges; the settings sheet; 2-51 for the -3/-4
breaker-failure settings; 3-20 for the logic masks). Category is the manual's own Section-5 heading, verbatim — no
grouping was invented. Where the manual is inconsistent with itself, the row's description says so and which limit
was taken.

Writes two files from this one list, so the reviewable table and the seed cannot disagree:
  docs/schema/ddl/PostDeploy/Seed_config_SettingsTemplate_SEL221F.sql
  docs/design/examples/templates/sel-221f.template.md

Usage: python tools/template_sel221f.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(ROOT, "docs", "schema", "ddl", "PostDeploy", "Seed_config_SettingsTemplate_SEL221F.sql")
DOC = os.path.join(ROOT, "docs", "design", "examples", "templates", "sel-221f.template.md")

KEY = "SETTINGS_TEXT_SEL_221F"
CHANGE_NOTE = "seed v3 (#168): groups by the manual's Specifications headings, the Section-5 heading in each description"
MODEL_CODES = ["SEL-221F Z1-3=.125-64 OHMS", "SEL-221F"]   # the SEL-221S is its own relay (its texts carry 67ND; its own manual) — not this template

# enumerations the template's closed lists use: key -> (name, [(code, name)])
ENUMS = {
    "SEL221F_PSVC": ("SEL-221F PSVC — polarizing and synchronizing voltage checks (3-24, 2-26)", [("N", "None — voltage checking disabled"), ("S", "LSDP — live sync, dead polarizing"), ("P", "LPDS — live polarizing, dead sync"), ("E", "Either")]),
    "SEL221F_SYNCP": ("SEL-221F SYNCP — synchronism-check phase (3-24, 5-13)", [("A", "Phase A"), ("B", "Phase B"), ("C", "Phase C")]),
    "SEL221F_51NC": ("SEL-221F 51NC — residual time-overcurrent curve (3-25, 2-9)", [("1", "Moderately inverse"), ("2", "Inverse"), ("3", "Very inverse"), ("4", "Extremely inverse")]),
    "SEL221F_YN": ("SEL-221F yes/no setting (3-25)", [("Y", "Yes"), ("N", "No")]),
    "SEL221F_REJOE": ("SEL-221F REJOE — remote-end-just-opened enable (3-25, 2-22)", [("N", "Disabled"), ("G", "Enabled, 3G50 qualifies"), ("P", "Enabled, 3P50 qualifies")]),
    "SEL221F_LOPE": ("SEL-221F LOPE — loss-of-potential detection (3-25, Table 2.3 at 2-17)", [("N", "No 21 block, no 52A supervision, no ALARM"), ("Y", "Block 21 on LOP"), ("1", "Block 21; 52A supervises LOP"), ("2", "Block 21; ALARM on LOP"), ("3", "Block 21; 52A supervises; ALARM on LOP"), ("4", "No 21 block; ALARM on LOP")]),
    "SEL221F_AUTO": ("SEL-221F AUTO — autoport (3-25, 5-31)", [("1", "Port 1"), ("2", "Port 2"), ("3", "Ports 1 and 2")]),
}

# (order, code, name, category, datatype, unit, base, min, max, enum, ansi, aliases, format, description-with-cite)
DEC2 = "decimal:2"
ROWS = [
    (1, "ID", "Relay identifier", "Identifier", "Text", None, None, None, None, None, None, None, "text",
          "§ Identifier. Tags every event report; up to 39 characters, later ones ignored (5-4, 5-5; 3-23 'Do not use END at the Relay ID setting'). Not carried in the legacy texts."),
    (2, "R1", "Positive-sequence line resistance", "Distance elements", "Decimal", "Ω", "Primary", 0, 9999, None, "21", None, DEC2,
          "§ R1, X1, R0, X0, and Line Length (LL). 'Positive-sequence primary impedance of line' (3-24). K = (Z0−Z1)/(3·Z1) must satisfy 0.0833 < |K| < 2.0 and 47° < MTA + ∠K < 113° (2-8, 5-6)."),
    (3, "X1", "Positive-sequence line reactance", "Distance elements", "Decimal", "Ω", "Primary", 0, 9999, None, "21", None, DEC2, "§ R1, X1, R0, X0, and Line Length (LL). 'Positive-sequence primary impedance of line' (3-24; 5-5)."),
    (4, "R0", "Zero-sequence line resistance", "Distance elements", "Decimal", "Ω", "Primary", 0, 9999, None, "21", "RO", DEC2, "§ R1, X1, R0, X0, and Line Length (LL). 'Zero-sequence primary impedance of line' (3-24; 5-5). Legacy texts spell it RO (letter O) once."),
    (5, "X0", "Zero-sequence line reactance", "Distance elements", "Decimal", "Ω", "Primary", 0, 9999, None, "21", "XO", DEC2, "§ R1, X1, R0, X0, and Line Length (LL). 'Zero-sequence primary impedance of line' (3-24; 5-5). Legacy alias XO."),
    (6, "LL", "Line length", "Fault location", "Decimal", "mi", None, 0.1, 999, None, None, None, DEC2,
          "§ R1, X1, R0, X0, and Line Length (LL). 'Line length' 0.1–999 miles (3-24). Settings sheet: station #1 (relay) to station #2, the full distance (sheet 6 of 6)."),
    (7, "CTR", "CT ratio", "Current and potential inputs", "Decimal", "ratio", None, 1, 6000, None, None, None, DEC2,
          "§ Current and Potential Transformer Ratio Selection. 'CT ratio (e.g., 600:5, enter 120)' (3-24). The manual is inconsistent: 3-24 and the settings sheet say 1–6000, 5-7 says 1–5000; the SET list's limit is taken. Three phase current inputs IA, IB, IC, 5 A nominal (2-12, 2-1)."),
    (8, "PTR", "PT ratio", "Current and potential inputs", "Decimal", "ratio", None, 1, 10000, None, None, None, DEC2,
          "§ Current and Potential Transformer Ratio Selection. 'PT ratio (e.g., 1200:1, enter 1200)' (3-24; 5-7). Three polarizing potential inputs VA, VB, VC, four-wire wye, 67 V L-N nominal (2-11)."),
    (9, "SPTR", "Synchronizing voltage transformer ratio", "Current and potential inputs", "Decimal", "ratio", None, 1, 10000, None, "25", None, DEC2,
          "§ Current and Potential Transformer Ratio Selection. 'Synchronization voltage transformer ratio' (3-24). PTR:SPTR must be between 0.5 and 1.99 (5-7). One synchronism-checking input VS, 0–120 V L-N (2-11/2-12)."),
    (10, "MTA", "Maximum torque angle", "Distance elements", "Decimal", "deg", None, 47, 90, None, "21", None, DEC2, "§ Maximum Torque Angle (MTA). 'Maximum torque angle for mho elements' 47°–90° (3-24; 2-8; 5-7)."),
    (11, "79OI", "Reclose open interval", "Reclosing", "Decimal", "cycles", None, 0, 8000, None, "79", None, DEC2, "§ Reclosing Open Interval and Reset Time (79OI and 79RS). 'Reclosing relay open interval' 0–8000 cycles in ¼-cycle steps; 0 disables reclosing (3-24; 2-11; 5-8)."),
    (12, "79RS", "Reclose reset time", "Reclosing", "Decimal", "cycles", None, 60, 8000, None, "79", None, DEC2, "§ Reclosing Open Interval and Reset Time (79OI and 79RS). 'Reclosing relay reset time' 60–8000 cycles (3-24; 2-11; 2-25)."),
    (13, "PSVC", "Polarizing and synchronizing voltage checks", "Synchronism and voltage checking", "Enumeration", None, None, None, None, "SEL221F_PSVC", None, None, "text", "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). N none, S live sync/dead polarizing, P live polarizing/dead sync, E either (3-24; 2-26; 5-12)."),
    (14, "27VLO", "Dead voltage threshold", "Synchronism and voltage checking", "Decimal", "kV", "Primary", 0, 2000, None, "27", None, DEC2, "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). 0–2000 kV primary; secondary 0–80.0 V L-N polarizing, 0–125 V L-N sync input (3-24; 5-12)."),
    (15, "59VHI", "Live voltage threshold", "Synchronism and voltage checking", "Decimal", "kV", "Primary", 0, 2000, None, "59", None, DEC2, "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). 0–2000 kV primary; same secondary limits as 27VLO (3-24; 5-12)."),
    (16, "25DV", "Difference voltage threshold", "Synchronism and voltage checking", "Decimal", "kV", "Primary", 0, 2000, None, "25", None, DEC2,
          "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). 0–2000 kV primary (3-24). The manual states the secondary range two ways: 0–125 V (settings sheet) and 0–150 V (2-11, 5-12); the primary limit is what the relay checks at SET."),
    (17, "SYNCP", "Synchronism-check phase", "Synchronism and voltage checking", "Enumeration", None, None, None, None, "SEL221F_SYNCP", "25", None, "text", "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). A, B or C; any phase when VS is not connected (3-24; 5-13)."),
    (18, "25T", "Synchronism-check timer", "Synchronism and voltage checking", "Decimal", "cycles", None, 0, 8000, None, "25", None, DEC2, "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). 0–8000 cycles, ¼-cycle resolution (3-24; 2-11)."),
    (19, "VCT", "Voltage condition timer", "Synchronism and voltage checking", "Decimal", "cycles", None, 0, 8000, None, None, None, DEC2, "§ Close Supervision Settings (PSVC, 27VLO, 59VHI, 25DV, SYNCP, 25T, VCT). 0–8000 cycles (3-24; 2-11)."),
    (20, "A1TP", "A1 output pickup delay", "Miscellaneous timers", "Decimal", "cycles", None, 0, 8000, None, None, None, DEC2, "§ A1 Programmable Output Time Delayed Pickup and Dropout Settings (A1TP, A1TD; SEL-221F-2 Only). 'A1 contact output pickup delay' 0–8000 cycles (3-24; 2-11; 5-13). SEL-221F-2 only."),
    (21, "A1TD", "A1 output dropout delay", "Miscellaneous timers", "Decimal", "cycles", None, 0, 8000, None, None, None, DEC2, "§ A1 Programmable Output Time Delayed Pickup and Dropout Settings (A1TP, A1TD; SEL-221F-2 Only). 'A1 contact output dropout delay' 0–8000 cycles (3-24; 2-11; 5-13). SEL-221F-2 only."),
    (22, "BFIN1", "Breaker failure IN1 enable", "Breaker failure", "Enumeration", None, None, None, None, "SEL221F_YN", "50BF", None, "text", "§ Breaker Failure Logic Settings. Y lets input IN1 start the breaker-failure logic (2-51). SEL-221F-3/121F-3 and -4 only: replaces A1TP."),
    (23, "BFTD", "Breaker failure time delay", "Breaker failure", "Decimal", "cycles", None, 5, 8000, None, "50BF", None, DEC2, "§ Breaker Failure Logic Settings. 5–8000 cycles (2-51; settings sheet). SEL-221F-3/121F-3 and -4 only: replaces A1TD."),
    (24, "Z1%", "Zone 1 reach", "Distance elements", "Decimal", "%", None, 0, 2000, None, "21", "Z1", DEC2, "§ Zone 1 Reach Setting (Z1%). 'Zone 1 reach (percent of line length)' 0–2000 %; secondary 0.125–64 Ω at MTA (3-24; 5-13/5-14; 2-7). Legacy texts spell it Z1 in 15 of 53 records."),
    (25, "Z2%", "Zone 2 reach", "Distance elements", "Decimal", "%", None, 0, 3200, None, "21", "Z2", DEC2, "§ Zone 2 Reach Setting (Z2%). 0–3200 %; Zone 2 ≥ Zone 1 (3-24; 5-14/5-16). Legacy alias Z2."),
    (26, "Z3%", "Zone 3 reach", "Distance elements", "Decimal", "%", None, 0, 3200, None, "21", "Z3", DEC2, "§ Zone 3 Reach Setting (Z3%). 0–3200 %; Zone 3 > Zone 2 (3-24; 5-16). Legacy alias Z3."),
    (27, "Z2DP", "Zone 2 delay, phase-to-phase faults", "Distance elements", "Decimal", "cycles", None, 3, 2000, None, "21", None, DEC2, "§ Zone 2 Phase And Ground Distance Time Delays (Z2DP, Z2DG). 3–2000 cycles in ¼-cycle steps (3-24; 2-9; 5-17)."),
    (28, "Z2DG", "Zone 2 delay, ground faults", "Distance elements", "Decimal", "cycles", None, 3, 2000, None, "21", None, DEC2, "§ Zone 2 Phase And Ground Distance Time Delays (Z2DP, Z2DG). 3–2000 cycles (3-24; 2-9; 5-17)."),
    (29, "Z3D", "Zone 3 delay, phase and ground faults", "Distance elements", "Decimal", "cycles", None, 3, 2000, None, "21", "Z3DP", DEC2, "§ Zone 3 Phase and Ground Time Delay (Z3D). 3–2000 cycles (3-24; 5-17). 2-9 names it Z3DP once."),
    (30, "TDUR", "Minimum trip duration", "Miscellaneous timers", "Decimal", "cycles", None, 0, 2000, None, None, None, DEC2, "§ Trip Duration Timer (TDUR). 'Minimum TRIP output duration' 0–2000 cycles; 0 disables the OPEN command (3-24; 2-11; 5-18). Legacy texts write '12 CYCLES' three times; the unit word is kept in the raw value."),
    (31, "50NG", "Residual or phase overcurrent pickup (sensitive)", "Overcurrent elements", "Decimal", "A", "Primary", 0.25, 50000, None, "50N", None, DEC2, "§ Phase and Residual Overcurrent Element Setting (50NG). 0.25–50000 A primary; secondary 0.5 A to 25×51NP but < 40 A (3-25; 2-9; 5-18/5-19)."),
    (32, "50P", "Phase overcurrent pickup, low set", "Overcurrent elements", "Decimal", "A", "Primary", 0.25, 50000, None, "50", None, DEC2, "§ Low-Set Phase Overcurrent Element Setting (50P). 0.25–50000 A primary; secondary 0.5–40 A (3-25; 2-9; 5-19/5-20)."),
    (33, "50H", "Phase overcurrent pickup, high set", "Overcurrent elements", "Decimal", "A", "Primary", 0.25, 50000, None, "50", None, DEC2, "§ High-Set Phase Overcurrent Element Setting. 0.25–50000 A primary; secondary 0.5–80 A (3-25; 2-9; 5-20)."),
    (34, "51NP", "Residual time-overcurrent pickup", "Overcurrent elements", "Decimal", "A", "Primary", 0.25, 50000, None, "51N", None, DEC2, "§ Residual Time-Overcurrent Settings (51NP, 51NC, 51NTD, 51NTC). 0.25–50000 A primary; secondary 0.5–8.0 A (3-25; 2-9; 5-21)."),
    (35, "51NTD", "Residual time-overcurrent time dial", "Overcurrent elements", "Decimal", None, None, 0.5, 15, None, "51N", None, DEC2, "§ Residual Time-Overcurrent Settings (51NP, 51NC, 51NTD, 51NTC). 0.50–15.00 in 0.01 steps (3-25; 2-9)."),
    (36, "51NC", "Residual time-overcurrent curve", "Overcurrent elements", "Enumeration", None, None, None, None, "SEL221F_51NC", "51N", None, "text", "§ Residual Time-Overcurrent Settings (51NP, 51NC, 51NTD, 51NTC). 1 moderately inverse, 2 inverse, 3 very inverse, 4 extremely inverse (3-25; 2-9)."),
    (37, "51NTC", "Residual time-overcurrent torque control", "Overcurrent elements", "Enumeration", None, None, None, None, "SEL221F_YN", "51N", None, "text", "§ Residual Time-Overcurrent Settings (51NP, 51NC, 51NTD, 51NTC). Y forward-reaching (directional), N nondirectional (3-25; 2-16; 5-21)."),
    (38, "67NP", "Residual instantaneous overcurrent pickup", "Overcurrent elements", "Decimal", "A", "Primary", 0.25, 50000, None, "67N", None, DEC2, "§ 67NP Residual Overcurrent Settings (67NP, 67NTC). 0.25–50000 A primary; secondary 0.5 A to 50×51NP (3-25; 2-10; 5-22)."),
    (39, "67NTC", "Residual instantaneous overcurrent torque control", "Overcurrent elements", "Enumeration", None, None, None, None, "SEL221F_YN", "67N", None, "text", "§ 67NP Residual Overcurrent Settings (67NP, 67NTC). Y or N (3-25; 5-22)."),
    (40, "52BT", "52B time delay (switch-onto-fault)", "Miscellaneous timers", "Decimal", "cycles", None, 0.5, 10000, None, None, None, DEC2, "§ 52BT Setting (52BT) And Switch-Onto-Fault Protection. 0.5–10000 cycles (3-25; 2-11; 5-23/5-24)."),
    (41, "REJOE", "Remote-end-just-opened enable", "Enables", "Enumeration", None, None, None, None, "SEL221F_REJOE", None, None, "text", "§ Remote-End-Just-Opened (REJO) Enable Setting (REJOE). N disable; G enable with 3G50 as qualifier; P enable with 3P50 (3-25; 2-22; 5-25/5-27)."),
    (42, "LOPE", "Loss-of-potential detection", "Enables", "Enumeration", None, None, None, None, "SEL221F_LOPE", None, None, "text", "§ Loss-of-Potential (LOP) Enable Setting, (LOPE). Y, N, 1, 2, 3, 4 per Table 2.3 (3-25; 2-16/2-17; 5-28/5-29)."),
    (43, "TIME1", "Port 1 timeout", "Communications", "Integer", "min", None, 0, 30, None, None, None, "integer", "§ Serial Port(s) Timeout Settings (TIME1, TIME2). 0–30 minutes; 0 never times out (3-25; 5-30)."),
    (44, "TIME2", "Port 2 timeout", "Communications", "Integer", "min", None, 0, 30, None, None, None, "integer", "§ Serial Port(s) Timeout Settings (TIME1, TIME2). 0–30 minutes (3-25; 5-30)."),
    (45, "AUTO", "Autoport", "Communications", "Enumeration", None, None, None, None, "SEL221F_AUTO", None, None, "text", "§ Autoport Designation Setting (AUTO). 1 port 1, 2 port 2, 3 both (3-25; 5-30/5-31)."),
    (46, "RINGS", "Modem answer rings", "Communications", "Integer", None, None, 1, 30, None, None, None, "integer", "§ Modem Answer Ring Setting (RINGS). 1–30 rings (3-25; 5-31)."),
]
MASKS = [("MTU", "Mask for trip unconditional"), ("MPT", "Mask for trip with permissive-trip asserted"), ("MTB", "Mask for trip with block-trip unasserted"),
         ("MTO", "Mask for trip with breaker open (switch-onto-fault)"), ("MA1", "Mask for A1 relay control"), ("MA2", "Mask for A2 relay control"),
         ("MA3", "Mask for A3 relay control"), ("MA4", "Mask for A4 relay control"), ("MRI", "Mask for reclose initiate"), ("MRC", "Mask for reclose cancel")]
for i, (code, name) in enumerate(MASKS, start=47):
    ROWS.append((i, code, name, "Logic settings", "Text", None, None, None, None, None, None, None, "mask3",
                 "§ Logic settings (5-32). One of the ten logic masks: 24 Relay Word bits in three rows of eight, entered as binary, shown as three hex bytes (3-20; 3-14; 5-32). Row 3 bit 2 is TRIP on the -2 and BFT on the -3/-4 (2-51)."))

UNITS_USED = sorted({r[5] for r in ROWS if r[5]})


def q(s):
    return "NULL" if s is None else "N'" + str(s).replace("'", "''") + "'"


def num(v):
    return "NULL" if v is None else repr(v)


def seed():
    L = ["-- GENERATED by tools/template_sel221f.py — do not edit; edit the data there and regenerate.",
         "-- #168 (2026-09-16): the SEL-221F settings template, version 2 of SETTINGS_TEXT_SEL_221F — from the instruction manual",
         "-- (IM 981207): the SET list's order, the manual's own Section-5 headings as categories, units, the primary limits the relay",
         "-- checks at SET, the closed lists as enumerations, the legacy spellings as aliases, the writer's format. Every row's",
         "-- description cites its page. Idempotent: adds the version only when no Effective version carries this change note.",
         "IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish", "GO",
         "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
         "DECLARE @sel UNIQUEIDENTIFIER = (SELECT TOP (1) [ManufacturerId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL');",
         "IF @sel IS NULL THROW 50000, N'Seed_config_SettingsTemplate_SEL221F: the manufacturer SEL is not seeded (Seed_config_SettingsTemplates_SEL.sql runs first).', 1;",
         "-- the closed lists", "DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT;"]
    for key, (name, values) in ENUMS.items():
        L.append(f"IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.Enumeration' AND [DefinitionKey] = {q(key)} AND [IsDeleted] = 0)")
        L.append("BEGIN")
        L.append(f"    SET @e = NULL; SET @v = NULL;")
        L.append(f"    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.Enumeration', @DefinitionKey = {q(key)}, @Name = {q(name)}, @ActorId = @author, @EntityId = @e OUTPUT;")
        L.append(f"    EXEC [config].[AddDefinitionVersion] @DefinitionKey = {q(key)}, @DefinitionKind = N'CharacteristicSchema.Enumeration', @ChangeNote = N'seed (#168)', @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;")
        for i, (code, vname) in enumerate(values, start=1):
            L.append(f"    EXEC [config].[EnumerationValue_Add] @DefinitionVersionRowId = @v, @ValueCode = {q(code)}, @Name = {q(vname)}, @DisplayOrder = {i}, @ActorId = @author;")
        L.append("    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;")
        L.append("END")
    L.append("GO")
    L += ["DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
          "DECLARE @sel UNIQUEIDENTIFIER = (SELECT TOP (1) [ManufacturerId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL');",
          f"DECLARE @note NVARCHAR(200) = {q(CHANGE_NOTE)};",
          "DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @r UNIQUEIDENTIFIER;",
          f"SELECT @def = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'Transform.SettingsParse' AND [DefinitionKey] = {q(KEY)} AND [IsDeleted] = 0;",
          "IF @def IS NULL",
          f"    EXEC [config].[AddDefinition] @DefinitionKind = N'Transform.SettingsParse', @DefinitionKey = {q(KEY)}, @Name = N'SEL-221F — settings template (IM 981207)',",
          "         @Description = N'The SEL-221F-2/-3/-4 settings as the instruction manual (date code 981207) lists them at SET (3-24/3-25) with the ten logic masks (3-20): names, the manual''s Section-5 headings as functional groups, units, primary limits, closed lists, legacy aliases (#168).', @ActorId = @author, @EntityId = @def OUTPUT;",
          "IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @def AND [Status] = N'Effective' AND [ChangeNote] = @note)",
          "BEGIN",
          f"    EXEC [config].[AddDefinitionVersion] @DefinitionKey = {q(KEY)}, @DefinitionKind = N'Transform.SettingsParse', @ChangeNote = @note, @ActorId = @author, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT;",
          "    DECLARE @enum UNIQUEIDENTIFIER;"]
    for (order, code, name, cat, dt, unit, base, mn, mx, enum, ansi, aliases, fmt, desc) in ROWS:
        if enum:
            L.append(f"    SELECT @enum = dv.[RowId] FROM [config].[vDefinition] d JOIN [config].[vDefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[Status] = N'Effective' WHERE d.[DefinitionKind] = N'CharacteristicSchema.Enumeration' AND d.[DefinitionKey] = {q(enum)};")
        L.append(f"    EXEC [config].[SettingDefinition_Add] @DefinitionVersionRowId = @ver, @SettingCode = {q(code)}, @Name = {q(name)}, @Category = {q(cat)}, @DataType = {q(dt)},"
                 f" @UnitCode = {q(unit)}, @Base = {q(base)}, @MinValue = {num(mn)}, @MaxValue = {num(mx)}, @EnumerationDefinitionRowId = {'@enum' if enum else 'NULL'}, @AnsiCode = {q(ansi)},"
                 f" @DisplayOrder = {order}, @Aliases = {q(aliases)}, @Format = {q(fmt)}, @Description = {q(desc)}, @IsCatalogueFact = 1, @ActorId = @author, @RowId = @r OUTPUT;")
    L += ["    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @ver, @ActorId = @approver;", "END",
          "-- the same relay under every model code the legacy data used (#168: a migration finding, not a model merge)",
          "DECLARE @model UNIQUEIDENTIFIER, @code NVARCHAR(200), @fvid UNIQUEIDENTIFIER;",
          "DECLARE mc CURSOR LOCAL FAST_FORWARD FOR SELECT [Code] FROM (VALUES " + ", ".join(f"({q(c)})" for c in MODEL_CODES) + ") x ([Code]);",
          "OPEN mc; FETCH NEXT FROM mc INTO @code;", "WHILE @@FETCH_STATUS = 0", "BEGIN",
          "    SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = @code;",
          "    IF @model IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [ref].[vFirmwareVersion] WHERE [ModelId] = @model AND [ParseTransformDefinitionEntityId] = @def)",
          "    BEGIN",
          "        SET @fvid = ISNULL((SELECT [FirmwareVersionId] FROM [ref].[vFirmwareVersion] WHERE [ModelId] = @model AND [VersionString] = N'n/a'), NEWID());",
          "        EXEC [ref].[FirmwareVersion_Upsert] @FirmwareVersionId = @fvid, @ModelId = @model, @VersionString = N'n/a', @ParseTransformDefinitionEntityId = @def, @ActorId = @author;",
          "    END",
          "    FETCH NEXT FROM mc INTO @code;", "END", "CLOSE mc; DEALLOCATE mc;", "GO", ""]
    return "\n".join(L)


def doc():
    L = ["# SEL-221F settings template — from the instruction manual (IM 981207)", "",
         "Source: *SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual*, date code 981207 — `Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf`.",
         "Page cites are the manual's printed labels (3-24 = Section 3 page 24). **Category is the manual's Specifications-section grouping (2-6…2-13, 2-16, 2-50, 3-2), and each description opens with the manual's own Section-5 heading (§), verbatim.** The order is the SET",
         "command's (3-24/3-25) with the ten logic masks (3-20) after it. Limits are the primary limit check the relay applies at SET; a secondary limit the",
         "manual states is in the description. Where the manual disagrees with itself, the description says so. Seed: `Seed_config_SettingsTemplate_SEL221F.sql`",
         "(generated from `tools/template_sel221f.py`, the single source of this table). Decision #168.", "",
         "Inputs (2-11, 2-12, 2-1): three phase current inputs IA, IB, IC (5 A nominal); three polarizing potential inputs VA, VB, VC in four-wire wye (67 V L-N);",
         "one synchronism-checking input VS (0–120 V L-N). The ratios are the settings CTR, PTR and SPTR.", "",
         "Functions (1-1, 2-2…2-4): three zones of phase and ground distance (21), residual time-overcurrent with selectable curves (51N), residual instantaneous",
         "overcurrent (67N), negative-sequence directional polarization, loss-of-potential detection, switch-onto-fault, remote-end-just-opened, single-shot",
         "reclosing (79), synchronism and voltage checking (25/27/59), fault location, metering; breaker failure on the -3/-4 (2-50).", "",
         "| # | Code | Name | Group (Specifications heading) | Type | Unit | Base | Min | Max | List | ANSI | Aliases | Format | Description and page |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for (order, code, name, cat, dt, unit, base, mn, mx, enum, ansi, aliases, fmt, desc) in ROWS:
        lst = "" if not enum else " / ".join(c for c, _ in ENUMS[enum][1])
        L.append(f"| {order} | `{code}` | {name} | {cat} | {dt} | {unit or ''} | {base or ''} | {'' if mn is None else mn} | {'' if mx is None else mx} | {lst} | {ansi or ''} | {aliases or ''} | {fmt} | {desc} |")
    L += ["", "## Closed lists", ""]
    for key, (name, values) in ENUMS.items():
        L.append(f"- **{key}** — {name}: " + "; ".join(f"`{c}` {n}" for c, n in values))
    L += ["", "## Variants (1-2, 2-51)", "",
          "- SEL-221F-2: A1TP and A1TD present; Relay Word row 3 bit 2 = TRIP.",
          "- SEL-221F-3 / 121F-3 and SEL-221F-4: BFIN1 and BFTD replace A1TP and A1TD; row 3 bit 2 = BFT. The -4 differs from the -3 only in targets and event triggering, not in settings (one settings sheet for both).",
          "", f"Rows: {len(ROWS)} (ID, {len([r for r in ROWS if r[0] <= 46]) - 1} SET settings including the two -3/-4 breaker-failure settings, {len(MASKS)} logic masks). Units used: {', '.join(UNITS_USED)}.", ""]
    return "\n".join(L)


def main():
    os.makedirs(os.path.dirname(DOC), exist_ok=True)
    with open(SEED, "w", encoding="utf-8", newline="\n") as f:
        f.write(seed())
    with open(DOC, "w", encoding="utf-8", newline="\n") as f:
        f.write(doc())
    print(f"{len(ROWS)} settings -> {os.path.relpath(SEED, ROOT)}, {os.path.relpath(DOC, ROOT)}")


if __name__ == "__main__":
    main()
