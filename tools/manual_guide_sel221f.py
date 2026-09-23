"""The SEL-221F manual guide: the instruction manual's own words on how each setting is set, with its page (#235).

Source: SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207
(Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf).

The owner, 2026-09-23, on the Settings tab's Comments column: "Instead of having generic comments on the right hand side ...
could we create custom floatovers which are excerpts from the manual on the various settings on how they should be set?" and
"the float over could also contain a hotlink to the exact location in the manual".

The rule (compliance and settings are never from memory): every quote below is the manual's text, VERBATIM, transcribed from the
page image — the PDF's own text layer is an OCR with errors ("SlNP" for S1NP), so it is only a draft. Each entry records the
printed page label the manual cites ("5-11") and the PDF's physical page (the link opens #page=N), both read off the page image,
and how it was checked. A subscript is written inline ("V l-n"); an equation set on its own line keeps its line ("\n"). "…" marks an elision. What the manual does not say is left out.
Sections are added a section at a time; a setting with no entry shows no floatover.

    python tools/manual_guide_sel221f.py   ->  docs/schema/ddl/PostDeploy/Seed_config_ManualGuide_SEL221F.sql
                                               docs/design/examples/templates/sel-221f.manual-guide.md
"""
import hashlib, io, json, os

NL = "\r\n"
KEY = "MANUAL_GUIDE_SEL_221F"
SETTINGS_TEMPLATE = "SETTINGS_TEXT_SEL_221F"
SOURCE = "SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207"
CHECKED = "transcribed from the page image, 2026-09-23"

# (setting code, [(printed page, PDF page, quote)])  — Close Supervision Settings, Section 5 Applications, 5-9 … 5-12
SETTINGS = [
    ("PSVC", [
        ("5-9", 133, "Enable the voltage checking function by selecting a PSVC setting of S, P, or E. Voltage checking is disabled when you select PSVC = N. When PSVC = S, the relay asserts Relay Word bit VSC when VS > 59VHI and VP1 < 27VLO (live sync/dead polarizing) for VCT time. When PSVC = P, the relay asserts Relay Word bit VSC when VP1 > 59VHI and VS < 27VLO (live polarizing/dead sync) for VCT time. When PSVC = E, the relay asserts Relay Word bit VSC when either voltage condition is true for VCT time."),
        ("5-12", 136, "The relay allows PSVC settings of S (for live-sync/dead-pol checking), P (for live-pol/dead-sync checking), E (closing is acceptable if either condition is valid), or N (voltage checking disabled)."),
    ]),
    ("27VLO", [
        ("5-9", 133, "Select 59VHI and 27VLO settings based upon your utility standards. Select standard voltage levels where the line is considered live and dead for reclosing purposes."),
        ("5-11", 135, "For the 27VLO setting, we assume that the line is dead for reclosing purposes if line voltage is below 20% of nominal voltage.\n27VLO = 0.20 x 132.8 kV = 26.6 kV"),
        ("5-12", 136, "The primary setting range check allows 27VLO, 59VHI, and 25DV voltage settings from 0 - 2,000 kV primary. The 27VLO and 59VHI secondary setting range is from 0 - 80.0 V l-n secondary on the polarizing inputs and 0 - 125 V l-n secondary on the synchronism checking input."),
    ]),
    ("59VHI", [
        ("5-9", 133, "Select 59VHI and 27VLO settings based upon your utility standards. Select standard voltage levels where the line is considered live and dead for reclosing purposes."),
        ("5-10", 134, "The relay checks the magnitudes of V1 and VS to ensure that both voltages are above the 59VHI setting. The relay only performs the sync check if both the bus and line are live."),
        ("5-12", 136, "For the 59VHI setting, we assume that the line is live for reclosing purposes if line voltage is above 80% of nominal voltage.\n59VHI = 0.80 x 132.8 kV = 106.2 kV"),
        ("5-12", 136, "The primary setting range check allows 27VLO, 59VHI, and 25DV voltage settings from 0 - 2,000 kV primary. The 27VLO and 59VHI secondary setting range is from 0 - 80.0 V l-n secondary on the polarizing inputs and 0 - 125 V l-n secondary on the synchronism checking input."),
    ]),
    ("25DV", [
        ("5-10", 134, "Referring to Figure 5.2, note that 25DV is determined from the known angle, ∅. The 25DV setting is approximated with the equation:\n25DV = sin(∅) x 59VHI\nThe value of ∅ should be the maximum angle across the breaker to allow closing."),
        ("5-11", 135, "For our example, for a maximum angle of 30° and 59VHI equal to 80% of nominal phase-neutral voltage on a 230 kV system:\n25DV = sin(30) x (0.8 x 132.8 kv) = 53.12 kv"),
        ("5-12", 136, "The primary setting range check allows 27VLO, 59VHI, and 25DV voltage settings from 0 - 2,000 kV primary. … The 25DV element setting range is 0 - 150 V secondary."),
    ]),
    ("SYNCP", [
        ("5-9", 133, "The voltage VS is taken from a bus-side PT attached to A-phase; SYNCP = A."),
        ("5-12", 136, "The VS input is taken from a bus-side PT connected to A-phase.\nSYNCP = A"),
    ]),
    ("25T", [
        ("5-10", 134, "If the 25T time is relatively short, the breaker close time may become a factor. For example, if 25T is set for 60 cycles and the breaker close time is 10 cycles, it actually takes 70 cycles to parallel the line. If this time is critical, the breaker close time should be taken into account when the 25T time is set so that, in this case, a 25T setting of 50 cycles might be more appropriate."),
        ("5-10", 134, "To set the relay, you must know the maximum angle (∅) between VPOL and VS that is allowed for the breaker to close. The slip frequency should be estimated to set the 25T time delay and the breaker close time should also be known."),
        ("5-11", 135, "The slip frequency is the maximum allowed frequency difference between VP and VS. The formula for slip is as follows:\nΔF = (2 x ∅) / (360 x 25T)\nWhere 25T is the sync-check time delay from the SEL-221F-2, -3, -4 relay setting."),
        ("5-12", 136, "The 25T setting is selected to allow closing under the synchronism conditions outlined above.\n25T = 5 sec = 300 cycles"),
    ]),
    ("VCT", [
        ("5-9", 133, "We only want to close if the voltage conditions have been valid for at least 30 cycles; VCT = 30 cycles."),
    ]),
]


def document():
    return {
        "g": 1, "kind": "manualGuide", "key": KEY, "name": "SEL-221F manual guide",
        "settingsTemplate": SETTINGS_TEMPLATE, "source": SOURCE,
        "settings": {code: [{"quote": q, "page": label, "pdfPage": pdf, "checked": CHECKED} for (label, pdf, q) in entries]
                     for (code, entries) in SETTINGS},
    }


def q(s):
    return "N'" + s.replace("'", "''") + "'"


def sql(doc):
    payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    note = "seed " + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
    desc = "What the SEL-221F instruction manual (IM 981207) says on how each setting is set, in its own words with the page."
    L = [
        "-- GENERATED by tools/manual_guide_sel221f.py - do not edit; edit the data there and regenerate.",
        "-- #235 (2026-09-23): the SEL-221F manual guide - the manual's own words on how each setting is set, verbatim from the page",
        "-- image, with the printed page and the PDF page (the Settings tab's floatover and its link into the manual). Idempotent and",
        "-- respectful of the Administrator, as the Relay Word seed: a key an Administrator has edited is left alone.",
        "IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish",
        "GO",
        "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
        "DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @payload NVARCHAR(MAX) = " + q(payload) + ";",
        "DECLARE @note NVARCHAR(200) = " + q(note) + ";",
        "SELECT @e = EntityId FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.ManualGuide' AND [DefinitionKey] = " + q(KEY) + " AND [IsDeleted] = 0;",
        "IF @e IS NULL",
        "    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.ManualGuide', @DefinitionKey = " + q(KEY) + ", @Name = N'SEL-221F manual guide', @Description = " + q(desc) + ", @ActorId = @author, @EntityId = @e OUTPUT;",
        "IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [ChangeNote] NOT LIKE N'seed %')      -- untouched by an Administrator",
        "   AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)",
        "BEGIN",
        "    EXEC [config].[AddDefinitionVersion] @DefinitionKey = " + q(KEY) + ", @DefinitionKind = N'Program.ManualGuide', @ChangeNote = @note, @PayloadText = @payload, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;",
        "    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;",
        "END",
        "GO",
    ]
    return NL.join(L) + NL


def md(doc):
    L = ["# SEL-221F manual guide - how each setting is set, in the manual's words", "",
         "Generated by `tools/manual_guide_sel221f.py` (#235). Source: **" + SOURCE + "**. Every quote is verbatim from the page",
         "image (" + CHECKED + "); the printed page is the manual's cite, the PDF page is where the link opens.", ""]
    for code, entries in SETTINGS:
        L += ["## " + code, ""]
        for label, pdf, text in entries:
            L += ["> " + text, ">", "> — p. " + label + " (PDF page " + str(pdf) + ")", ""]
    return NL.join(L) + NL


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    a = os.path.join(root, "docs", "schema", "ddl", "PostDeploy", "Seed_config_ManualGuide_SEL221F.sql")
    b = os.path.join(root, "docs", "design", "examples", "templates", "sel-221f.manual-guide.md")
    doc = document()
    io.open(a, "w", encoding="utf-8", newline="").write(sql(doc))
    io.open(b, "w", encoding="utf-8", newline="").write(md(doc))
    print(str(len(SETTINGS)) + " settings, " + str(sum(len(e) for _, e in SETTINGS)) + " quotes ->")
    print("  " + a)
    print("  " + b)


if __name__ == "__main__":
    main()
