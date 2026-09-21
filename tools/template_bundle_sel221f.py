"""template_bundle_sel221f.py - the SEL-221F device template, SEL221F_Template (#184), as data.

The owner, 2026-09-18: a TEMPLATE is one per device type, one level below a scheme, named "SEL221F_Template"; it bundles
everything true of the device type itself - its settings list (tools/template_sel221f.py), what it can do
(tools/capability_sel221f.py) and the compliance that can attach to it - so that placing a relay of this model brings
all of it. This tool gives the bundle its name and its home: a CharacteristicSchema.AssetTemplate definition (a seeded
kind that had never held an instance) bound to the model through config.DefinitionAppliesTo, carrying the model-level
facts nothing else holds. The settings and the capabilities stay where they are and are found through the same model.

Source for every row: SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207
(Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf), page-cited.

Writes docs/schema/ddl/PostDeploy/Seed_config_AssetTemplate_SEL221F.sql.
"""
import io
import os

NL = chr(13) + chr(10)
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = "SEL221F_Template"
MODEL_CODES = ["SEL-221F Z1-3=.125-64 OHMS", "SEL-221F"]   # the same two codes the settings template and the capabilities bind to
NOTE = "seed v3 (#216): hardware configuration — the jumper positions the manual names (3-2, 3-8, 3-22, 6-2)"

# the closed lists a characteristic may take: (key, name, [(code, name)...]) — seeded as CharacteristicSchema.Enumeration
ENUMS = [
    ("SEL221F_BAUD", "SEL-221F serial port baud rate — set by jumper JMP105 (3-2, 6-2)",
     [("300", "300 baud"), ("600", "600 baud"), ("1200", "1200 baud"), ("2400", "2400 baud"), ("4800", "4800 baud"), ("9600", "9600 baud")]),
]

# (key, name, datatype, unit, group, order, description-with-cite[, enumeration key])
ROWS = [
    ("ManualReference", "Instruction manual", "Text", None, "Identity", 1,
     "SEL-221F-2, -3, -4 / SEL-121F-2, -3 Instruction Manual, date code 981207, Schweitzer Engineering Laboratories, "
     "December 7, 1998 (title page). Held at Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf."),
    ("Variations", "Model variations covered", "Text", None, "Identity", 2,
     "SEL-221F-2, -3, -4 and SEL-121F-2, -3: 'identical protection features but use different hardware designs' (1-1). "
     "'Firmware changes to the logic controlling reclosing, Relay Word bits, and command access level differentiate "
     "SEL-221F relay model variations' (1-1)."),
    ("BreakerFailureVariants", "Variations with breaker failure", "Text", None, "Identity", 3,
     "SEL-221F-3/121F-3 and SEL-221F-4 only: 'includes a breaker failure function ... the AITP setting is replaced with "
     "BFIN1 and the AITD setting is replaced with BFTD' (1-2). The -2 does not have it. The platform's model rows carry no "
     "variation suffix, so a person must know which relay is in front of them."),
    ("Application", "Intended application", "Text", None, "Identity", 4,
     "'designed to protect transmission, subtransmission, and distribution lines for all fault types' (1-1). Supports "
     "POTT, PUTT, DUTT and DTT communication-aided schemes (1-4)."),
    ("RatedInputs", "Rated inputs", "Text", None, "Inputs", 5,
     "115 V nominal phase-to-phase, three-phase four-wire; 5 A per phase nominal, 15 A continuous, 500 A one-second "
     "thermal (2-1)."),
    ("SettingsTemplate", "Settings list", "Text", None, "Bundle", 6,
     "The settings template SETTINGS_TEXT_SEL_221F (56 settings in the manual's twelve Specifications groups, #168), "
     "bound to this model through its firmware row; none hidden (#183)."),
    ("Capabilities", "What it can do", "Text", None, "Bundle", 7,
     "The fifteen elements of scheme.FunctionCapability for this model (#181, #182): ten with a C37.2 device number and "
     "five named in the manual's own words."),
    # #216 (2026-09-21): HARDWARE CONFIGURATION — per relay, not per type. The manual's port parameters are jumpers, not settings:
    # 'The baud rates of the ports are set by jumpers located near the front of the main board ... Available rates are 300, 600,
    # 1200, 2400, 4800, and 9600 baud' (3-2); the data format 'eight data bits, two stop bits, no parity bit ... cannot be
    # altered' (3-2). Recorded on the device, changed under a work request, never written to the settings file.
    ("Jmp105Port1Baud", "PORT 1 baud rate (JMP105)", "Enumeration", None, "Hardware", 10,
     "'JMP105 provides EIA RS-232-C baud rate selection. Available baud rates are 300, 600, 1200, 2400, 4800, and 9600. To select "
     "a baud rate for a particular port, place the jumper so it connects a pin labeled with the desired port to a pin labeled "
     "with the desired baud rate' (6-2). 'The relay is shipped with PORT 1 set to 300 baud' (3-2). 'Do not select two baud rates "
     "for the same port as this can damage the relay baud rate generator' (3-2).", "SEL221F_BAUD"),
    ("Jmp105Port2Baud", "PORT 2F/2R baud rate (JMP105)", "Enumeration", None, "Hardware", 11,
     "The same jumper, JMP105, for PORT 2 — the front PORT 2F and rear PORT 2R share it (3-2, 6-2). 'The relay is shipped with "
     "... PORT 2F/2R set to 2400 baud' (3-2). The serial data format is fixed: 'eight data bits, two stop bits, no parity bit. This "
     "format cannot be altered' (3-2).", "SEL221F_BAUD"),
    ("Jmp103PasswordProtection", "JMP103 installed — password protection disabled", "Boolean", None, "Hardware", 12,
     "'Put JMP103 in place to disable password protection. This feature is useful if passwords are not required or when "
     "passwords are forgotten' (6-2). 'The password is required unless you install jumper JMP103' (3-8). Y = the jumper is "
     "in place (no password asked); N = not in place (passwords required)."),
    ("Jmp104OpenClose", "JMP104 installed — OPEN and CLOSE commands enabled", "Boolean", None, "Hardware", 13,
     "'With jumper JMP104 in place, the OPEN and CLOSE commands are enabled. If you remove jumper JMP104, executing OPEN and "
     "CLOSE commands results in the message: \"Aborted.\"' (6-2); 'Close circuit breaker, if Jumper JMP104 is installed' "
     "(command summary). Y = in place (the commands work); N = not in place."),
]


def q(s):
    return "N'" + s.replace("'", "''") + "'" if s is not None else "NULL"


def sql():
    L = [
        "-- GENERATED by tools/template_bundle_sel221f.py - do not edit; edit the data there and regenerate.",
        "-- #184 (2026-09-18): the SEL-221F device template, " + KEY + ". The owner: a template is one per device type, one",
        "-- level below a scheme; it bundles the settings list, what the relay can do, and the compliance that can attach.",
        "-- CharacteristicSchema.AssetTemplate is the seeded kind that had never held an instance; this is its first.",
        "-- Bound to the model through config.DefinitionAppliesTo (dimension Model), one row per model code, so a screen",
        "-- opened from a relay of either code finds it. Idempotent: adds the version only when no Effective version",
        "-- carries this change note; binds a model only when not already bound.",
        "IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish",
        "GO",
        "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
        "DECLARE @sel UNIQUEIDENTIFIER = (SELECT TOP (1) [ManufacturerId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL');",
        "IF @sel IS NULL RETURN;",
        "DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @model UNIQUEIDENTIFIER, @code NVARCHAR(200), @enum UNIQUEIDENTIFIER;",
    ]
    # the closed lists (the settings template's pattern): seeded once, never re-versioned by this tool
    for (ekey, ename, values) in ENUMS:
        L += [
            "IF NOT EXISTS (SELECT 1 FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.Enumeration' AND [DefinitionKey] = " + q(ekey) + " AND [IsDeleted] = 0)",
            "BEGIN",
            "    SET @e = NULL; SET @v = NULL;",
            "    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.Enumeration', @DefinitionKey = " + q(ekey) + ", @Name = " + q(ename) + ", @ActorId = @author, @EntityId = @e OUTPUT;",
            "    EXEC [config].[AddDefinitionVersion] @DefinitionKey = " + q(ekey) + ", @DefinitionKind = N'CharacteristicSchema.Enumeration', @ChangeNote = N'seed (#216)', @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;",
        ]
        for i, (code, vname) in enumerate(values, 1):
            L.append("    EXEC [config].[EnumerationValue_Add] @DefinitionVersionRowId = @v, @ValueCode = " + q(code) + ", @Name = " + q(vname) + ", @DisplayOrder = " + str(i) + ", @ActorId = @author;")
        L += ["    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;", "END"]
    L += [
        "SET @e = NULL;",
        "SELECT @e = [EntityId] FROM [config].[Definition] WHERE [DefinitionKind] = N'CharacteristicSchema.AssetTemplate' AND [DefinitionKey] = " + q(KEY) + " AND [IsDeleted] = 0;",
        "IF @e IS NULL",
        "    EXEC [config].[AddDefinition] @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @DefinitionKey = " + q(KEY) + ",",
        "         @Name = N'SEL-221F device template', @Description = N'Everything true of the SEL-221F as a device type: its manual, its variations, its settings list, what it can do, and the compliance that can attach to it (#184). One template per device type, one level below a scheme.',",
        "         @ActorId = @author, @EntityId = @e OUTPUT;",
        "IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = " + q(NOTE) + ")",
        "BEGIN",
        "    EXEC [config].[AddDefinitionVersion] @DefinitionKey = " + q(KEY) + ", @DefinitionKind = N'CharacteristicSchema.AssetTemplate', @ChangeNote = " + q(NOTE) + ", @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;",
    ]
    for row in ROWS:
        (key, name, dt, unit, group, order, desc) = row[:7]; ekey = row[7] if len(row) > 7 else None
        if ekey:
            L.append("    SELECT @enum = dv.[RowId] FROM [config].[vDefinition] d JOIN [config].[vDefinitionVersion] dv ON dv.[DefinitionEntityId] = d.[EntityId] AND dv.[Status] = N'Effective' WHERE d.[DefinitionKind] = N'CharacteristicSchema.Enumeration' AND d.[DefinitionKey] = " + q(ekey) + ";")
        L.append("    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = " + q(key)
                 + ", @Name = " + q(name) + ", @DataType = " + q(dt) + ", @UnitCode = " + q(unit) + ", @DisplayGroup = " + q(group)
                 + ", @DisplayOrder = " + str(order) + (", @AllowedValuesDefinitionRowId = @enum" if ekey else "") + ", @Description = " + q(desc) + ", @ActorId = @author;")
    L += [
        "    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;",
        "END",
        "SELECT TOP (1) @v = [RowId] FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' ORDER BY [VersionNumber] DESC;",
        "-- bind the template to each model code it covers",
        "DECLARE mc CURSOR LOCAL FAST_FORWARD FOR SELECT [Code] FROM (VALUES " + ", ".join("(" + q(c) + ")" for c in MODEL_CODES) + ") x ([Code]);",
        "OPEN mc; FETCH NEXT FROM mc INTO @code;",
        "WHILE @@FETCH_STATUS = 0",
        "BEGIN",
        "    SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = @code;",
        "    IF @model IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionAppliesTo] WHERE [DefinitionVersionRowId] = @v AND [DimensionCode] = N'Model' AND [ValueEntityId] = @model)",
        "        EXEC [config].[DefinitionAppliesTo_Add] @DefinitionVersionRowId = @v, @DimensionCode = N'Model', @ValueEntityId = @model, @ActorId = @author;",
        "    FETCH NEXT FROM mc INTO @code;",
        "END",
        "CLOSE mc; DEALLOCATE mc;",
        "GO",
    ]
    return NL.join(L) + NL


def main():
    out = os.path.join(HERE, "docs", "schema", "ddl", "PostDeploy", "Seed_config_AssetTemplate_SEL221F.sql")
    io.open(out, "w", encoding="utf-8", newline="").write(sql())
    print(str(len(ROWS)) + " template facts -> " + out)


if __name__ == "__main__":
    main()
