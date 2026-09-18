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

Codes: the manual prints no C37.2 device numbers. Where a function has one, the code below is the one
tools/template_sel221f.py already assigns to that function's SETTINGS (#168), so the capability list and the settings
template agree. Where it has none, the code is the MANUFACTURER'S OWN ABBREVIATION as the manual prints it (32Q, LOP,
SOTF, REJO) and the row carries is_number=False, so a screen shows the words rather than pretending it is a number.

The owner, 2026-09-17: "there are elements in the relay that do not have ansi numbers assigned to them. That is to be
expected from those devices and should not be left out, they are part of the device and must be included. When no
numbers can be found for the functionality, wording will have to suffice."

One code is ours and is marked as such in its citation: the fault locator, which the manual names in words throughout
and never abbreviates.

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

# (code, the manual's own name for it, is_number, category, variants, manual heading and page, the sentence that says so)
ROWS = [
    # --- functions that DO carry a C37.2 device number ------------------------------------------------------------
    ("21", "Phase and ground distance", True, "Protection", "all",
     "Functional Specifications > Expanded Mho Characteristics for Phase-Ground, Phase-Phase, and Three-Phase Faults (2-2); Relay Overview (1-1)",
     "Three zones of phase and ground distance protection; independent timers for Zone 2 phase, Zone 2 ground and Zone 3 (time-step backup protection) (2-2). Figure 2.1 Three Zones of Phase and Ground Mho Distance Protection (2-3)."),
    ("51N", "Residual time-overcurrent", True, "Protection", "all",
     "Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "Time-overcurrent element detects highly resistive ground faults; four curve families (moderate, inverse, very inverse, extremely inverse); nondirectional or forward-reaching as enabled (2-3). Curve equations 2-41."),
    ("50N", "Instantaneous residual overcurrent", True, "Protection", "all",
     "Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "Instantaneous residual overcurrent element; nondirectional or forward-reaching, as enabled (2-3)."),
    ("67N", "Ground directional overcurrent", True, "Protection", "all",
     "Title page; Functional Specifications > Residual Overcurrent Backup Protection for Ground Faults (2-3)",
     "The title page names the relay a GROUND DIRECTIONAL OVERCURRENT RELAY. Negative-sequence directional polarization (2-3); the negative-sequence element may polarize ground directional overcurrent protection, if enabled (2-3)."),
    ("50", "Phase overcurrent (nondirectional)", True, "Protection", "all",
     "Functional Specifications > Nondirectional Phase Overcurrent Elements (2-3, 2-4)",
     "Low-set phase overcurrent elements supervise phase distance elements and release the TRIP output contacts (2-3); the high-set phase overcurrent element provides switch-onto-fault protection for close-in three-phase faults (2-4)."),
    ("79", "Reclosing", True, "Control", "all",
     "Title page; Functional Specifications > Reclosing (2-4)",
     "The title page names the relay a RECLOSING RELAY. Single reclosing shot with settable open interval timer; selectable reclose initiate and cancel conditions; settable reclose reset timer (2-4)."),
    ("25", "Synchronism check", True, "Control", "all",
     "Title page; Functional Specifications > Synchronism Checking (2-4)",
     "The title page names the relay a SYNCHRONISM CHECKING RELAY. Closing may be supervised by a synchronism checking function; the relay setting allows synch-check potential to be taken from any phase (2-4)."),
    ("27", "Undervoltage (dead-line / dead-bus check)", True, "Protection", "all",
     "Functional Specifications > Voltage Checking (2-4)",
     "Closing may be supervised by Live-line/Dead-Bus conditions, Live-bus/Dead-line conditions, or either (2-4) - the dead half of that check. Its setting is 27VLO in the settings template (#168)."),
    ("59", "Overvoltage (live-line / live-bus check)", True, "Protection", "all",
     "Functional Specifications > Voltage Checking (2-4)",
     "Closing may be supervised by Live-line/Dead-Bus conditions, Live-bus/Dead-line conditions, or either (2-4) - the live half of that check. Its setting is 59VHI in the settings template (#168)."),
    ("50BF", "Breaker failure", True, "Protection", "SEL-221F-3, -4 only",
     "Introduction > Model Variations (1-2); Specifications > Breaker Failure Features of the SEL-221F-3/121F-3 and SEL-221F-4 Relays (2-50)",
     "The SEL-221F-3/121F-3 includes a breaker failure function; the A1TP setting is replaced with BFIN1 and A1TD with BFTD (1-2); the SEL-221F-4 has the same breaker failure functionality (1-2). NOT present on the SEL-221F-2."),

    # --- functions with NO device number: the manufacturer's own abbreviation, and the words -----------------------
    # The owner, 2026-09-17: "there are elements in the relay that do not have ansi numbers assigned to them... they
    # are part of the device and must be included. When no numbers can be found for the functionality, wording will
    # have to suffice." Four of these five abbreviations are the MANUAL'S OWN; the fifth is marked as ours.
    ("32Q", "Negative-sequence directional element", False, "Protection", "all",
     "Functional Specifications > Negative-Sequence Directional Element (2-3); Figure 2.2 32Q Polarization Criteria (2-10)",
     "Directional polarization is based upon negative-sequence voltage and current; adds security to phase and ground distance elements; may polarize ground directional overcurrent protection, if enabled (2-3). The abbreviation 32Q is the manual's own, printed as the title of Figure 2.2. It is NOT a C37.2 device number."),
    ("LOP", "Loss-of-potential detection", False, "Protection", "all",
     "Functional Specifications > Loss-of-Potential (LOP) Detection (2-3); Table 2.3 LOPE Settings (2-17)",
     "Detects blown secondary potential fuse(s); enabled or disabled with a simple setting; when enabled an LOP condition blocks all mho distance elements (2-3). LOP is the manual's own abbreviation, in its heading. The manual prints no device number."),
    ("SOTF", "Switch-onto-fault protection", False, "Protection", "all",
     "Relay Overview (1-1); Functional Specifications > Switch-Onto-Fault Protection (2-4)",
     "Programmable switch-onto-fault logic (1-1); user selected elements enabled to trip for 52BT time after the line breaker closes, functioning independently from communications channel equipment (2-4). The manual prints no device number."),
    ("REJO", "Remote-end-just-opened protection", False, "Protection", "all",
     "Functional Specifications > Remote-End-Just-Opened (REJO) Protection (2-4)",
     "User selected elements enabled to trip if the remote breaker clears the fault contribution; provides pilotless accelerated tripping in many applications (2-4). REJO is the manual's own abbreviation, in its heading. The manual prints no device number."),
    ("FAULTLOC", "Fault locating", False, "Measurement", "all",
     "Title page; Relay Overview (1-1); General Description (1-4, 1-5)",
     "The title page names the relay a FAULT LOCATOR; Fault locating (1-1); an event report carries Fault location and Secondary ohms to the fault location (1-5). The manual names this in words throughout and never abbreviates it, so the code FAULTLOC IS OURS, chosen to be obviously not a device number."),
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
    for (ansi, name, is_number, category, variants, where, why) in ROWS:
        L.append("        -- " + ansi + " " + name + " (" + variants + ") - " + where)
        # the C37.2 name wins where there is one (Seed_ref_AnsiFunction_Core says so); this seed only NAMES a code
        # the catalogue does not hold yet, which is the five the manual gives no device number for
        L.append("        IF NOT EXISTS (SELECT 1 FROM [ref].[AnsiFunction] WHERE [AnsiCode] = " + q(ansi) + ")")
        L.append("            EXEC [ref].[AnsiFunction_Upsert] @AnsiCode = " + q(ansi) + ", @Name = " + q(name)
                 + ", @Category = " + q(category) + ", @ActorId = @author;")
        L.append("        UPDATE [ref].[AnsiFunction] SET [IsDeviceNumber] = " + ("1" if is_number else "0") + " WHERE [AnsiCode] = " + q(ansi) + ";")
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
        "| Code | The manual's name | Device number? | Variants | Where the manual says so |",
        "|---|---|---|---|---|",
    ]
    for (ansi, name, is_number, category, variants, where, why) in ROWS:
        L.append("| `" + ansi + "` | " + name + " | " + ("C37.2" if is_number else "no - words") + " | " + variants + " | " + where + " |")
    L += [
        "",
        "## Why each row is here (the manual's words)",
        "",
    ]
    for (ansi, name, is_number, category, variants, where, why) in ROWS:
        L.append("- **" + ansi + " " + name + "** - " + why)
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
    print(str(len(ROWS)) + " capabilities (" + str(sum(1 for r in ROWS if not r[2])) + " named in words, no device number) ->")
    print("  " + a)
    print("  " + b)


if __name__ == "__main__":
    main()
