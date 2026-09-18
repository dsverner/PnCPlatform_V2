"""capability_sel221f.py - what an SEL-221F can do (#181), from the instruction manual, as data.

The owner, 2026-09-17: "lets build the checklist on the device instead, you can build the list from the devices
manual... an admin would create an SEL-221F device template with all the possible capabilities so that when the user
selects the device to add to a panel it will populate with all the appropriate capabilities".

Source: SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207
(Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf) - the same document
tools/template_sel221f.py cites page by page for the settings.

The list below is the manual's OWN Functional Specifications headings (2-2 to 2-4), plus the two functions named on
the title page and in the Relay Overview (1-1) that Section 2 documents elsewhere. Nothing is inferred from the
relay's behaviour; every row cites where the manual says the relay has that function.

ANSI codes: the manual does not print device numbers. Each code below is the one tools/template_sel221f.py already
assigns to that function's SETTINGS (#168, reviewed then), so the capability list and the settings template agree.
Functions the manual describes for which this platform has NO established code are listed in UNCODED at the bottom
and are NOT seeded - they are the owner's to rule on, never guessed.

Writes two files from one list:
  docs/schema/ddl/PostDeploy/Seed_scheme_FunctionCapability_SEL221F.sql
  docs/design/examples/templates/sel-221f.capabilities.md
"""
import io
import os

NL = chr(13) + chr(10)
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_CODES = ["SEL-221F Z1-3=.125-64 OHMS", "SEL-221F"]   # the same two codes the settings template binds to
SOURCE = "Manual"          # scheme.FunctionCapability.Source: Template | Icd | Manual
CHANGE = "#181 from IM 981207"

# (ansi, the manual's own name for it, variants, manual heading and page, the sentence that says the relay has it)
ROWS = [
    ("21", "Phase and ground distance", "all",
     "Functional Specifications > Expanded Mho Characteristics for Phase-Ground, Phase-Phase, and Three-Phase Faults (2-2); Relay Overview (1-1)",
     "'Three zones of phase and ground distance protection'; 'Independent timers for Zone 2 phase, Zone 2 ground, and Zone 3 distance elements (time-step backup protection)' (2-2). Figure 2.1 'Three Zones of Phase and Ground Mho Distance Protection' (2-3)."),
    ("51N", "Residual time-overcurrent", "all",
     "Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "'Time-overcurrent element detects highly resistive ground faults - Four curve families (moderate, inverse, very inverse, and extremely inverse) - Nondirectional or forward-reaching, as enabled in relay settings' (2-3). Curve equations 2-41."),
    ("50N", "Instantaneous residual overcurrent", "all",
     "Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "'Instantaneous residual overcurrent element - Nondirectional or forward-reaching, as enabled' (2-3)."),
    ("67N", "Ground directional overcurrent", "all",
     "Title page; Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "The title page names the relay a 'GROUND DIRECTIONAL OVERCURRENT RELAY'. 'Negative-sequence directional polarization' (2-3); the negative-sequence directional element 'May polarize ground directional overcurrent protection, if enabled' (2-3)."),
    ("50", "Phase overcurrent (nondirectional)", "all",
     "Functional Specifications > Nondirectional Phase Overcurrent Elements (2-3, 2-4)",
     "'Low-set phase overcurrent elements supervise phase distance elements and release the TRIP output contacts...' (2-3); 'High-set phase overcurrent element provides switch-onto-fault protection for close-in three-phase faults' (2-4)."),
    ("79", "Reclosing", "all",
     "Title page; Functional Specifications > Reclosing (2-4)",
     "The title page names the relay a 'RECLOSING RELAY'. 'Single reclosing shot with settable open interval timer; Selectable reclose initiate and cancel conditions; Settable reclose reset timer' (2-4)."),
    ("25", "Synchronism check", "all",
     "Title page; Functional Specifications > Synchronism Checking (2-4)",
     "The title page names the relay a 'SYNCHRONISM CHECKING RELAY'. 'Closing may be supervised by a synchronism checking function... Relay setting allows synch-check potential to be taken from any phase' (2-4)."),
    ("27", "Undervoltage (dead-line / dead-bus check)", "all",
     "Functional Specifications > Voltage Checking (2-4)",
     "'Closing may be supervised by Live-line/Dead-Bus conditions, Live-bus/Dead-line conditions, or either condition' (2-4) - the dead half of that check. Its setting is 27VLO in the settings template (#168)."),
    ("59", "Overvoltage (live-line / live-bus check)", "all",
     "Functional Specifications > Voltage Checking (2-4)",
     "'Closing may be supervised by Live-line/Dead-Bus conditions, Live-bus/Dead-line conditions, or either condition' (2-4) - the live half of that check. Its setting is 59VHI in the settings template (#168)."),
    ("50BF", "Breaker failure", "SEL-221F-3, -4 only",
     "Introduction > Model Variations (1-2); Specifications > Breaker Failure Features of the SEL-221F-3/121F-3 and SEL-221F-4 Relays (2-50)",
     "'The SEL-221F-3/121F-3 Relay includes a breaker failure function... the A1TP setting is replaced with BFIN1 and the A1TD setting is replaced with BFTD' (1-2); 'The SEL-221F-4 Relay includes the same breaker failure functionality as the SEL-221F-3' (1-2). NOT present on the SEL-221F-2."),
]

# Described by the manual, but this platform has no established ANSI code for them. NOT seeded - the owner rules.
UNCODED = [
    ("Negative-sequence directional element", "Functional Specifications > Negative-Sequence Directional Element (2-3); Figure 2.2 '32Q Polarization Criteria' (2-10)",
     "'Directional polarization is based upon negative-sequence voltage and current; Adds security to phase and ground distance elements' (2-3). The manual calls it 32Q; no 32 or 32Q row exists in ref.AnsiFunction."),
    ("Loss-of-potential (LOP) detection", "Functional Specifications > Loss-of-Potential (LOP) Detection (2-3); Table 2.3 'LOPE Settings' (2-17)",
     "'Detects blown secondary potential fuse(s) condition... When enabled, an LOP condition blocks all mho distance elements' (2-3). Commonly device 60; the manual prints no number."),
    ("Switch-onto-fault (SOTF) protection", "Functional Specifications > Switch-Onto-Fault Protection (2-4)",
     "'User selected elements enabled to trip for 52BT time after the line breaker closes' (2-4). No C37.2 device number."),
    ("Remote-end-just-opened (REJO) protection", "Functional Specifications > Remote-End-Just-Opened (REJO) Protection (2-4)",
     "'User selected elements enabled to trip if remote breaker clears fault contribution; Provides pilotless accelerated tripping' (2-4). No C37.2 device number."),
    ("Fault locating", "Title page; Relay Overview (1-1); General Description (1-4)",
     "The title page names the relay a 'FAULT LOCATOR'; 'Fault locating' (1-1). A measurement, not a protective element; sometimes written 21FL."),
]


def q(s):
    return "N'" + s.replace("'", "''") + "'" if s is not None else "NULL"


def sql():
    L = [
        "-- GENERATED by tools/capability_sel221f.py - do not edit; edit the data there and regenerate.",
        "-- #181 (2026-09-17): what an SEL-221F can do, from the instruction manual (IM 981207). The owner asked for a",
        "-- checklist on the device built from the manual, so that placing a relay offers its elements rather than asking",
        "-- a person to invent them. scheme.FunctionCapability is the table the design already provided for this",
        "-- (SCHEMA-DESIGN 7.3, decision 117: 'what a relay model (or firmware) can do'); nothing had ever written a row.",
        "-- Every row cites the manual heading and page that says the relay has that function; the ANSI code is the one",
        "-- the settings template already assigns to that function's settings (#168), so the two agree.",
        "-- Idempotent: a capability already recorded for the model is left alone.",
        "IF OBJECT_ID(N'[scheme].[FunctionCapability_Add]') IS NULL RETURN;   -- bootstrap (tables-only) publish",
        "GO",
        "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';",
        "DECLARE @sel UNIQUEIDENTIFIER = (SELECT TOP (1) [ManufacturerId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL');",
        "IF @sel IS NULL RETURN;   -- the SEL templates seed the manufacturer; nothing to bind to yet",
        "DECLARE @model UNIQUEIDENTIFIER, @code NVARCHAR(200);",
        "DECLARE mc CURSOR LOCAL FAST_FORWARD FOR SELECT [Code] FROM (VALUES "
        + ", ".join("(" + q(c) + ")" for c in MODEL_CODES) + ") x ([Code]);",
        "OPEN mc; FETCH NEXT FROM mc INTO @code;",
        "WHILE @@FETCH_STATUS = 0",
        "BEGIN",
        "    SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = @code;",
        "    IF @model IS NOT NULL",
        "    BEGIN",
    ]
    for (ansi, name, variants, where, why) in ROWS:
        L.append("        -- " + ansi + " " + name + " (" + variants + ") - " + where)
        L.append("        IF NOT EXISTS (SELECT 1 FROM [scheme].[vFunctionCapability] WHERE [ModelId] = @model AND [AnsiCode] = "
                 + q(ansi) + ")")
        L.append("            EXEC [scheme].[FunctionCapability_Add] @ModelId = @model, @AnsiCode = " + q(ansi)
                 + ", @Source = " + q(SOURCE) + ", @ActorId = @author;")
    L += [
        "    END",
        "    FETCH NEXT FROM mc INTO @code;",
        "END",
        "CLOSE mc; DEALLOCATE mc;",
        "GO",
    ]
    return NL.join(L) + NL


def md():
    L = [
        "# SEL-221F - what the relay can do",
        "",
        "Generated by `tools/capability_sel221f.py`. Source: **SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date",
        "code 981207** (`Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf`).",
        "",
        "The list is the manual's own Functional Specifications headings (2-2 to 2-4) plus the functions named on the",
        "title page and in the Relay Overview (1-1). The ANSI code on each row is the one the settings template already",
        "assigns to that function's settings (#168), so the capability list and the settings agree.",
        "",
        "| ANSI | The manual's name | Variants | Where the manual says so |",
        "|---|---|---|---|",
    ]
    for (ansi, name, variants, where, why) in ROWS:
        L.append("| `" + ansi + "` | " + name + " | " + variants + " | " + where + " |")
    L += [
        "",
        "## Why each row is here (the manual's words)",
        "",
    ]
    for (ansi, name, variants, where, why) in ROWS:
        L.append("- **" + ansi + " " + name + "** - " + why)
    L += [
        "",
        "## Described by the manual, not seeded - no established ANSI code in this platform",
        "",
        "These are real functions of the relay. They are **not** in the capability list because `ref.AnsiFunction` has no",
        "code for them and this platform never invents one. Each needs a ruling before it can be offered.",
        "",
    ]
    for (name, where, why) in UNCODED:
        L.append("- **" + name + "** (" + where + ") - " + why)
    L += [
        "",
        "## One thing the platform cannot yet tell apart",
        "",
        "Breaker failure is on the **SEL-221F-3 and -4 only**; the **-2 does not have it** (1-2). The model rows in this",
        "platform are `SEL-221F Z1-3=.125-64 OHMS` and `SEL-221F`, neither of which carries the variation suffix, so the",
        "capability is recorded against both and a person must know which relay is in front of them. Splitting the model",
        "by variation is a separate decision.",
        "",
    ]
    return NL.join(L) + NL


def main():
    a = os.path.join(HERE, "docs", "schema", "ddl", "PostDeploy", "Seed_scheme_FunctionCapability_SEL221F.sql")
    b = os.path.join(HERE, "docs", "design", "examples", "templates", "sel-221f.capabilities.md")
    io.open(a, "w", encoding="utf-8", newline="").write(sql())
    io.open(b, "w", encoding="utf-8", newline="").write(md())
    print(str(len(ROWS)) + " capabilities, " + str(len(UNCODED)) + " described but uncoded ->")
    print("  " + a)
    print("  " + b)


if __name__ == "__main__":
    main()
